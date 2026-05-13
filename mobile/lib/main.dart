import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

void main() {
  runApp(const DroidHarnessApp());
}

class DroidHarnessApp extends StatelessWidget {
  const DroidHarnessApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xff1f7a5a);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Droid Harness',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
          surface: const Color(0xff111417),
        ),
        scaffoldBackgroundColor: const Color(0xff0b0f10),
        useMaterial3: true,
      ),
      home: const HarnessHomePage(),
    );
  }
}

class HarnessHomePage extends StatefulWidget {
  const HarnessHomePage({super.key});

  @override
  State<HarnessHomePage> createState() => _HarnessHomePageState();
}

class _HarnessHomePageState extends State<HarnessHomePage> {
  final _llm = LocalLlmClient();
  final _bridge = TermuxBridgeClient();
  final _promptController = TextEditingController();
  final _terminalController = TextEditingController();
  final _scrollController = ScrollController();
  final List<TerminalLine> _terminal = [
    TerminalLine.system('Droid Harness pronto. Verifique o modelo local.'),
    TerminalLine.command('llama-server --host 127.0.0.1 --port 8080'),
  ];
  final List<ChatMessage> _messages = [
    const ChatMessage(
      role: MessageRole.assistant,
      text:
          'Conecte um llama-server em 127.0.0.1:8080 e envie uma tarefa. O app fala com a API OpenAI-compativel local.',
    ),
  ];

  bool _checking = false;
  bool _sending = false;
  ServerState _serverState = ServerState.unknown;
  ServerState _bridgeState = ServerState.unknown;
  Timer? _terminalPollTimer;
  int _lastTerminalEvent = 0;
  int _selectedCommand = 0;

  final List<QuickCommand> _commands = const [
    QuickCommand(
      title: 'Iniciar modelo',
      command:
          'llama-server -m ~/models/qwen-coder-1.5b-q4_k_m.gguf --host 127.0.0.1 --port 8080 -ngl 99 -c 4096 --mlock --no-mmap',
    ),
    QuickCommand(
      title: 'Modo pouca RAM',
      command:
          'llama-server -m ~/models/qwen-coder-1.5b-q4_k_m.gguf --host 127.0.0.1 --port 8080 -ngl 99 -c 2048 -b 64 -ub 64 --mlock --no-mmap',
    ),
    QuickCommand(
      title: 'Health check',
      command: 'curl http://127.0.0.1:8080/v1/models',
    ),
    QuickCommand(title: 'Ubuntu proot', command: 'proot-distro login ubuntu'),
  ];

  @override
  void initState() {
    super.initState();
    unawaited(_checkServer());
    unawaited(_checkBridge(startSession: true));
    _terminalPollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_pollTerminalEvents());
    });
  }

  @override
  void dispose() {
    _terminalPollTimer?.cancel();
    _promptController.dispose();
    _terminalController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _checkServer() async {
    setState(() {
      _checking = true;
    });

    final online = await _llm.healthCheck();
    if (!mounted) return;

    setState(() {
      _serverState = online ? ServerState.online : ServerState.offline;
      _checking = false;
      _terminal.add(
        online
            ? TerminalLine.system('llama-server online em 127.0.0.1:8080')
            : TerminalLine.system('llama-server offline ou inacessivel'),
      );
    });
    _scrollTerminalToEnd();
  }

  Future<void> _checkBridge({bool startSession = false}) async {
    final online = await _bridge.healthCheck();
    if (!mounted) return;

    setState(() {
      _bridgeState = online ? ServerState.online : ServerState.offline;
      _terminal.add(
        online
            ? TerminalLine.system('bridge Termux online em 127.0.0.1:8765')
            : TerminalLine.error(
                'bridge Termux offline. Rode scripts/start-termux-bridge.sh no Termux.',
              ),
      );
    });

    if (online && startSession) {
      await _startTerminalSession();
    }
    _scrollTerminalToEnd();
  }

  Future<void> _startTerminalSession() async {
    try {
      await _bridge.startSession();
      if (!mounted) return;
      setState(() {
        _bridgeState = ServerState.online;
      });
      await _pollTerminalEvents();
    } on BridgeException catch (error) {
      if (!mounted) return;
      setState(() {
        _bridgeState = ServerState.offline;
        _terminal.add(TerminalLine.error(error.message));
      });
    }
  }

  Future<void> _sendPrompt() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty || _sending) return;

    setState(() {
      _sending = true;
      _messages.add(ChatMessage(role: MessageRole.user, text: prompt));
      _terminal.add(TerminalLine.command('POST /v1/chat/completions'));
      _promptController.clear();
    });
    _scrollTerminalToEnd();

    try {
      final response = await _llm.chat(prompt);
      if (!mounted) return;
      setState(() {
        _messages.add(ChatMessage(role: MessageRole.assistant, text: response));
        _serverState = ServerState.online;
        _terminal.add(TerminalLine.system('Resposta recebida do modelo local'));
      });
    } on LocalLlmException catch (error) {
      if (!mounted) return;
      setState(() {
        _messages.add(
          ChatMessage(role: MessageRole.assistant, text: error.message),
        );
        _serverState = ServerState.offline;
        _terminal.add(TerminalLine.error(error.message));
      });
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
      _scrollTerminalToEnd();
    }
  }

  void _stageCommand(QuickCommand command) {
    setState(() {
      _terminalController.text = command.command;
      _terminalController.selection = TextSelection.collapsed(
        offset: command.command.length,
      );
    });
  }

  Future<void> _submitTerminalCommand() async {
    final command = _terminalController.text.trim();
    if (command.isEmpty) return;

    setState(() {
      _terminal.add(TerminalLine.command(command));
      _terminalController.clear();
    });
    _scrollTerminalToEnd();

    try {
      await _bridge.sendInput('$command\n');
      if (!mounted) return;
      setState(() {
        _bridgeState = ServerState.online;
      });
      await _pollTerminalEvents();
    } on BridgeException catch (error) {
      if (!mounted) return;
      setState(() {
        _bridgeState = ServerState.offline;
        _terminal.add(TerminalLine.error(error.message));
      });
      _scrollTerminalToEnd();
    }
  }

  Future<void> _pollTerminalEvents() async {
    if (_bridgeState == ServerState.offline) return;

    try {
      final result = await _bridge.events(after: _lastTerminalEvent);
      if (!mounted || result.events.isEmpty) {
        _lastTerminalEvent = result.next;
        return;
      }
      setState(() {
        _lastTerminalEvent = result.next;
        _bridgeState = ServerState.online;
        _terminal.addAll(
          result.events.map((event) => TerminalLine.fromBridge(event)),
        );
      });
      _scrollTerminalToEnd();
    } on BridgeException {
      if (!mounted) return;
      setState(() {
        _bridgeState = ServerState.offline;
      });
    }
  }

  void _scrollTerminalToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 900;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              serverState: _serverState,
              bridgeState: _bridgeState,
              checking: _checking,
              onRefresh: () {
                unawaited(_checkServer());
                unawaited(_checkBridge(startSession: true));
              },
            ),
            Expanded(
              child: isWide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _buildChatPanel()),
                        const VerticalDivider(width: 1),
                        Expanded(child: _buildTerminalPanel()),
                      ],
                    )
                  : _buildMobileLayout(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileLayout() {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.auto_awesome), text: 'IA local'),
              Tab(icon: Icon(Icons.terminal), text: 'Terminal'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [_buildChatPanel(), _buildTerminalPanel()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatPanel() {
    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemBuilder: (context, index) =>
                _ChatBubble(message: _messages[index]),
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemCount: _messages.length,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: _PromptBar(
            controller: _promptController,
            sending: _sending,
            onSend: _sendPrompt,
          ),
        ),
      ],
    );
  }

  Widget _buildTerminalPanel() {
    return Column(
      children: [
        SizedBox(
          height: 64,
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: IconButton.filledTonal(
                  tooltip: 'Iniciar sessao Termux',
                  onPressed: _startTerminalSession,
                  icon: const Icon(Icons.power_settings_new),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  scrollDirection: Axis.horizontal,
                  itemBuilder: (context, index) {
                    final command = _commands[index];
                    return ChoiceChip(
                      selected: _selectedCommand == index,
                      label: Text(command.title),
                      avatar: const Icon(Icons.play_arrow, size: 18),
                      onSelected: (_) {
                        setState(() {
                          _selectedCommand = index;
                        });
                        _stageCommand(command);
                      },
                    );
                  },
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 8),
                  itemCount: _commands.length,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xff050707),
              border: Border.all(color: Colors.white12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView.builder(
              controller: _scrollController,
              itemCount: _terminal.length,
              itemBuilder: (context, index) =>
                  _TerminalRow(line: _terminal[index]),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: _TerminalInput(
            controller: _terminalController,
            onSubmit: () => unawaited(_submitTerminalCommand()),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.serverState,
    required this.bridgeState,
    required this.checking,
    required this.onRefresh,
  });

  final ServerState serverState;
  final ServerState bridgeState;
  final bool checking;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white12)),
      ),
      child: Row(
        children: [
          const Icon(Icons.memory, size: 28),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Droid Harness',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                Text(
                  'Terminal + IA local no Android',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
          _ServerBadge(label: 'LLM', state: serverState),
          const SizedBox(width: 8),
          _ServerBadge(label: 'Termux', state: bridgeState),
          IconButton(
            tooltip: 'Atualizar status',
            onPressed: checking ? null : onRefresh,
            icon: checking
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }
}

class _ServerBadge extends StatelessWidget {
  const _ServerBadge({required this.label, required this.state});

  final String label;
  final ServerState state;

  @override
  Widget build(BuildContext context) {
    final (statusLabel, color) = switch (state) {
      ServerState.online => ('$label online', Colors.greenAccent),
      ServerState.offline => ('$label off', Colors.redAccent),
      ServerState.unknown => ('$label ?', Colors.amberAccent),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 9, color: color),
          const SizedBox(width: 6),
          Text(statusLabel, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;
    final alignment = isUser ? Alignment.centerRight : Alignment.centerLeft;
    final color = isUser ? const Color(0xff1f7a5a) : const Color(0xff1b2226);

    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white10),
          ),
          child: SelectableText(
            message.text,
            style: const TextStyle(height: 1.35),
          ),
        ),
      ),
    );
  }
}

class _PromptBar extends StatelessWidget {
  const _PromptBar({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            minLines: 1,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'Peça uma tarefa para a IA local...',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.edit_note),
            ),
            onSubmitted: (_) => onSend(),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          tooltip: 'Enviar',
          onPressed: sending ? null : onSend,
          icon: sending
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send),
        ),
      ],
    );
  }
}

class _TerminalRow extends StatelessWidget {
  const _TerminalRow({required this.line});

  final TerminalLine line;

  @override
  Widget build(BuildContext context) {
    final color = switch (line.kind) {
      TerminalLineKind.command => Colors.lightGreenAccent,
      TerminalLineKind.error => Colors.redAccent,
      TerminalLineKind.output => Colors.white,
      TerminalLineKind.system => Colors.white70,
    };
    final prefix = switch (line.kind) {
      TerminalLineKind.command => r'$',
      TerminalLineKind.error => '!',
      TerminalLineKind.output => '|',
      TerminalLineKind.system => '>',
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: SelectableText(
        '$prefix ${line.text}',
        style: TextStyle(
          color: color,
          fontFamily: 'monospace',
          fontSize: 13,
          height: 1.25,
        ),
      ),
    );
  }
}

class _TerminalInput extends StatelessWidget {
  const _TerminalInput({required this.controller, required this.onSubmit});

  final TextEditingController controller;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            style: const TextStyle(fontFamily: 'monospace'),
            decoration: const InputDecoration(
              hintText: 'Digite ou selecione um comando',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.terminal),
            ),
            onSubmitted: (_) => onSubmit(),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: 'Executar',
          onPressed: onSubmit,
          icon: const Icon(Icons.keyboard_return),
        ),
      ],
    );
  }
}

class LocalLlmClient {
  LocalLlmClient({
    this.baseUrl = 'http://127.0.0.1:8080',
    HttpClient? httpClient,
  }) : _httpClient = httpClient ?? HttpClient();

  final String baseUrl;
  final HttpClient _httpClient;

  Future<bool> healthCheck() async {
    try {
      final uri = Uri.parse('$baseUrl/v1/models');
      final request = await _httpClient
          .getUrl(uri)
          .timeout(const Duration(seconds: 2));
      final response = await request.close().timeout(
        const Duration(seconds: 2),
      );
      await response.drain<void>();
      return response.statusCode >= 200 && response.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  Future<String> chat(String prompt) async {
    try {
      final uri = Uri.parse('$baseUrl/v1/chat/completions');
      final request = await _httpClient
          .postUrl(uri)
          .timeout(const Duration(seconds: 4));
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({
          'model': 'local-model',
          'messages': [
            {
              'role': 'system',
              'content':
                  'Voce e o agente local do Droid Harness. Responda de forma direta e util para tarefas de terminal e codigo no Android.',
            },
            {'role': 'user', 'content': prompt},
          ],
          'temperature': 0.2,
          'stream': false,
        }),
      );

      final response = await request.close().timeout(
        const Duration(minutes: 2),
      );
      final body = await utf8.decodeStream(response);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw LocalLlmException('Falha HTTP ${response.statusCode}: $body');
      }

      final decoded = jsonDecode(body);
      final choices = decoded['choices'];
      if (choices is! List || choices.isEmpty) {
        throw const LocalLlmException('Resposta sem choices do modelo local.');
      }

      final message = choices.first['message'];
      final content = message is Map ? message['content'] : null;
      if (content is! String || content.trim().isEmpty) {
        throw const LocalLlmException('Resposta vazia do modelo local.');
      }

      return content.trim();
    } on LocalLlmException {
      rethrow;
    } on TimeoutException {
      throw const LocalLlmException(
        'Tempo esgotado falando com 127.0.0.1:8080.',
      );
    } on SocketException {
      throw const LocalLlmException(
        'Nao consegui conectar ao llama-server. Inicie o modelo local no Termux.',
      );
    } on FormatException {
      throw const LocalLlmException('O servidor respondeu JSON invalido.');
    } catch (error) {
      throw LocalLlmException('Erro inesperado: $error');
    }
  }
}

class TermuxBridgeClient {
  TermuxBridgeClient({
    this.baseUrl = 'http://127.0.0.1:8765',
    HttpClient? httpClient,
  }) : _httpClient = httpClient ?? HttpClient();

  final String baseUrl;
  final HttpClient _httpClient;

  Future<bool> healthCheck() async {
    try {
      final response = await _get(
        '/health',
      ).timeout(const Duration(seconds: 2));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  Future<void> startSession() async {
    await _post('/terminal/session', const {});
  }

  Future<void> sendInput(String data) async {
    await _post('/terminal/input', {'data': data});
  }

  Future<TerminalEventsResult> events({required int after}) async {
    final response = await _get('/terminal/events?after=$after');
    final body = await utf8.decodeStream(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BridgeException('Bridge HTTP ${response.statusCode}: $body');
    }

    final decoded = jsonDecode(body);
    final events = decoded['events'];
    final next = decoded['next'];
    if (events is! List || next is! int) {
      throw const BridgeException('Bridge retornou eventos invalidos.');
    }

    return TerminalEventsResult(
      events: events
          .whereType<Map>()
          .map((event) => BridgeTerminalEvent.fromJson(event))
          .toList(),
      next: next,
    );
  }

  Future<HttpClientResponse> _get(String path) async {
    try {
      final request = await _httpClient
          .getUrl(Uri.parse('$baseUrl$path'))
          .timeout(const Duration(seconds: 2));
      return request.close().timeout(const Duration(seconds: 3));
    } on TimeoutException {
      throw const BridgeException(
        'Tempo esgotado falando com o bridge Termux.',
      );
    } on SocketException {
      throw const BridgeException(
        'Bridge Termux offline. Rode scripts/start-termux-bridge.sh no Termux.',
      );
    }
  }

  Future<void> _post(String path, Map<String, Object?> body) async {
    try {
      final request = await _httpClient
          .postUrl(Uri.parse('$baseUrl$path'))
          .timeout(const Duration(seconds: 2));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
      final response = await request.close().timeout(
        const Duration(seconds: 3),
      );
      final responseBody = await utf8.decodeStream(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw BridgeException(
          'Bridge HTTP ${response.statusCode}: $responseBody',
        );
      }
    } on BridgeException {
      rethrow;
    } on TimeoutException {
      throw const BridgeException(
        'Tempo esgotado falando com o bridge Termux.',
      );
    } on SocketException {
      throw const BridgeException(
        'Bridge Termux offline. Rode scripts/start-termux-bridge.sh no Termux.',
      );
    }
  }
}

class TerminalEventsResult {
  const TerminalEventsResult({required this.events, required this.next});

  final List<BridgeTerminalEvent> events;
  final int next;
}

class BridgeTerminalEvent {
  const BridgeTerminalEvent({
    required this.id,
    required this.kind,
    required this.text,
  });

  factory BridgeTerminalEvent.fromJson(Map<dynamic, dynamic> json) {
    return BridgeTerminalEvent(
      id: (json['id'] as num?)?.toInt() ?? 0,
      kind: json['kind']?.toString() ?? 'stdout',
      text: json['text']?.toString() ?? '',
    );
  }

  final int id;
  final String kind;
  final String text;
}

class LocalLlmException implements Exception {
  const LocalLlmException(this.message);

  final String message;
}

class BridgeException implements Exception {
  const BridgeException(this.message);

  final String message;
}

class ChatMessage {
  const ChatMessage({required this.role, required this.text});

  final MessageRole role;
  final String text;
}

class TerminalLine {
  const TerminalLine._(this.kind, this.text);

  factory TerminalLine.fromBridge(BridgeTerminalEvent event) {
    return switch (event.kind) {
      'error' => TerminalLine.error(event.text),
      'system' => TerminalLine.system(event.text),
      _ => TerminalLine.output(event.text),
    };
  }

  factory TerminalLine.command(String text) {
    return TerminalLine._(TerminalLineKind.command, text);
  }

  factory TerminalLine.error(String text) {
    return TerminalLine._(TerminalLineKind.error, text);
  }

  factory TerminalLine.output(String text) {
    return TerminalLine._(TerminalLineKind.output, text);
  }

  factory TerminalLine.system(String text) {
    return TerminalLine._(TerminalLineKind.system, text);
  }

  final TerminalLineKind kind;
  final String text;
}

class QuickCommand {
  const QuickCommand({required this.title, required this.command});

  final String title;
  final String command;
}

enum MessageRole { user, assistant }

enum TerminalLineKind { command, system, output, error }

enum ServerState { unknown, online, offline }
