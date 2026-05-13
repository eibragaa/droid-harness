import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const DroidHarnessApp());
}

// ── Palette: Google AI Edge Gallery ────────────────────────────────
// seed: #80cbc4 (deep_teal_200), surfaces Material 3 dark
// ref: res/values/colors.xml from Edge Gallery v1.0.13 APK

class AppColors {
  static const scaffold = Color(0xff0f1114);
  static const surface = Color(0xff1a1c1e);
  static const card = Color(0xff1e2024);
  static const teal = Color(0xff80cbc4);
  static const tealDark = Color(0xff008577);
  static const tealText = Color(0xff00332e);
  static const greenAccent = Color(0xff69f0ae);
  static const redAccent = Color(0xffff7043);
  static const divider = Color(0xff2c2e30);
  static const inputBg = Color(0xff1e2024);
}

class DroidHarnessApp extends StatelessWidget {
  const DroidHarnessApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Droid Harness',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.teal,
          brightness: Brightness.dark,
          surface: AppColors.surface,
          primary: AppColors.teal,
          secondary: const Color(0xffa8e6cf),
          onPrimary: AppColors.tealText,
          onSecondary: const Color(0xff00382b),
          surfaceTint: AppColors.teal,
        ),
        scaffoldBackgroundColor: AppColors.scaffold,
        cardTheme: CardThemeData(
          color: AppColors.card,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.inputBg,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: AppColors.card,
          selectedColor: AppColors.teal.withAlpha(30),
          labelStyle: const TextStyle(fontSize: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: AppColors.surface,
          indicatorColor: AppColors.teal.withAlpha(30),
        ),
      ),
      home: const HarnessHomePage(),
    );
  }
}

// ── Enums ──────────────────────────────────────────────────────────

enum ServerState { unknown, online, offline }
enum MessageRole { user, assistant }
enum TerminalLineKind { command, system, output, error }

// ── Main Page ──────────────────────────────────────────────────────

class HarnessHomePage extends StatefulWidget {
  const HarnessHomePage({super.key});
  @override
  State<HarnessHomePage> createState() => _HarnessHomePageState();
}

class _HarnessHomePageState extends State<HarnessHomePage> {
  // ── Clients & Channels ──────────────────────────────────────────
  final _llm = LocalLlmClient();
  final _bridge = TermuxBridgeClient();
  static const _channel = MethodChannel('dev.droidharness/bridge');

  // ── Controllers ─────────────────────────────────────────────────
  final _prompt = TextEditingController();
  final _termCtrl = TextEditingController();
  final _chatScroll = ScrollController();
  final _termScroll = ScrollController();

  // ── State ───────────────────────────────────────────────────────
  final List<ChatMessage> _messages = [];
  final List<TerminalLine> _terminal = [
    TerminalLine.system('Droid Harness — IA local'),
    TerminalLine.system('Aguardando bridge Termux...'),
  ];

  ServerState _server = ServerState.unknown;
  ServerState _bridgeState = ServerState.unknown;
  HardwareProfile? _profile;
  bool _sending = false;
  bool _downloading = false;
  bool _terminalReady = false;
  int _lastEvent = 0;
  int _tab = 0;
  Timer? _pollTimer;
  Timer? _retryTimer;
  int _retries = 0;
  static const _maxRetries = 25;
  static const _retryDelay = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_onMethodCall);
    unawaited(_checkInitialIntent());
    unawaited(_checkLlm());
    _startRetry();
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_bridgeState == ServerState.online) unawaited(_pollTerminal());
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _retryTimer?.cancel();
    _prompt.dispose();
    _termCtrl.dispose();
    _chatScroll.dispose();
    _termScroll.dispose();
    super.dispose();
  }

  // ── Connection ──────────────────────────────────────────────────

  void _startRetry() {
    _retries = 0;
    _retryTimer?.cancel();
    _tryConnect();
  }

  void _tryConnect() {
    if (_retries >= _maxRetries) {
      _retryTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _addTerm(TerminalLine.error('Falhou apos $_maxRetries tentativas'));
      });
      return;
    }
    _retries++;
    unawaited(_doConnect());
  }

  Future<void> _doConnect() async {
    try {
      if (await _bridge.healthCheck()) {
        _retryTimer?.cancel();
        if (!mounted) return;
        setState(() => _bridgeState = ServerState.online);
        _addTerm(TerminalLine.system('\u2713 Bridge conectado'));
        await _initSession();
        await _loadProfile();
        return;
      }
    } catch (_) {}

    if (!mounted) return;
    _retryTimer?.cancel();
    _retryTimer = Timer(_retryDelay, _tryConnect);
  }

  Future<void> _initSession() async {
    try {
      await _bridge.startSession();
      if (!mounted) return;
      setState(() => _terminalReady = true);
      _addTerm(TerminalLine.system('\u2713 Sessao terminal criada'));
    } catch (e) {
      _addTerm(TerminalLine.error('Erro ao criar sessao: $e'));
    }
  }

  Future<void> _loadProfile() async {
    try {
      final p = await _bridge.hardwareProfile();
      if (!mounted) return;
      setState(() => _profile = p);
      _addTerm(TerminalLine.system('Modelo: ${p.modelId} (${p.profile})'));
      _add(TerminalLine('assistant', 'Hardware **${p.profile}** detectado.\n\n'
          '\u{1f4e6} **${p.modelId}** \u00b7 ctx ${p.context} \u00b7 ngl ${p.ngl}\n\n'
          'Toque em **Baixar + Iniciar** para come\u00e7ar.'));
    } catch (e) {
      _addTerm(TerminalLine.error('Erro hardware: $e'));
    }
  }

  Future<void> _checkLlm() async {
    final ok = await _llm.healthCheck();
    if (!mounted) return;
    setState(() => _server = ok ? ServerState.online : ServerState.offline);
  }

  // ── Download + Start ────────────────────────────────────────────

  Future<void> _downloadAndStart() async {
    if (_downloading) return;

    // Garante sessao ativa
    if (!_terminalReady) {
      try {
        await _bridge.startSession();
        if (!mounted) return;
        setState(() => _terminalReady = true);
      } catch (e) {
        _addTerm(TerminalLine.error('Bridge offline: $e'));
        return;
      }
    }

    setState(() {
      _downloading = true;
      _addTerm(TerminalLine.system('\u{1f4e5} Baixando modelo...'));
      _add(TerminalLine('assistant', '\u{1f680} Baixando modelo + iniciando servidor...'));
    });

    try {
      // Step 1: download
      await _bridge.downloadModel('recommended').timeout(const Duration(minutes: 10));
      if (!mounted) return;
      _addTerm(TerminalLine.system('\u2713 Download concluido'));

      // Step 2: start server
      await _bridge.startLocalModel('auto').timeout(const Duration(seconds: 15));
      if (!mounted) return;

      setState(() {
        _downloading = false;
        _server = ServerState.online;
        _addTerm(TerminalLine.system('\u2713 llama-server iniciado!'));
        _add(TerminalLine('assistant', '\u2705 Pronto! Envie prompts no chat.'));
      });
      unawaited(_checkLlm());
    } on TimeoutException {
      if (!mounted) return;
      setState(() => _downloading = false);
      _addTerm(TerminalLine.error('Timeout no download. Tente novamente.'));
    } on BridgeException catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _bridgeState = ServerState.offline;
        _addTerm(TerminalLine.error('Bridge: ${e.message}'));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _downloading = false);
      _addTerm(TerminalLine.error('Erro: $e'));
    }
  }

  // ── Chat ────────────────────────────────────────────────────────

  Future<void> _send() async {
    final t = _prompt.text.trim();
    if (t.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _add(TerminalLine('user', t));
      _prompt.clear();
    });
    _scrollChat();
    try {
      final r = await _llm.chat(t);
      if (!mounted) return;
      setState(() {
        _add(TerminalLine('assistant', r));
        _server = ServerState.online;
      });
    } on LocalLlmException catch (e) {
      if (!mounted) return;
      setState(() {
        _add(TerminalLine('assistant', '\u26a0 $e'));
        _server = ServerState.offline;
      });
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollChat();
    }
  }

  // ── Terminal ────────────────────────────────────────────────────

  Future<void> _submitTerm() async {
    final c = _termCtrl.text.trim();
    if (c.isEmpty) return;
    setState(() {
      _addTerm(TerminalLine.command(c));
      _termCtrl.clear();
    });
    if (!_terminalReady) {
      _addTerm(TerminalLine.error('Sessao terminal nao iniciada'));
      return;
    }
    try {
      await _bridge.sendInput('$c\n');
      if (!mounted) return;
      setState(() => _bridgeState = ServerState.online);
    } on BridgeException catch (e) {
      if (!mounted) return;
      setState(() {
        _bridgeState = ServerState.offline;
        _addTerm(TerminalLine.error(e.message));
      });
    }
  }

  Future<void> _pollTerminal() async {
    try {
      final r = await _bridge.events(after: _lastEvent);
      if (r.events.isEmpty) {
        _lastEvent = r.next;
        return;
      }
      if (!mounted) return;
      setState(() {
        _lastEvent = r.next;
        _bridgeState = ServerState.online;
        for (final e in r.events) {
          _terminal.add(TerminalLine.fromBridge(e));
        }
      });
    } catch (_) {
      if (mounted) setState(() => _bridgeState = ServerState.offline);
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────

  void _add(TerminalLine l) {
    _messages.add(ChatMessage(role: l.role == 'user' ? MessageRole.user : MessageRole.assistant, text: l.text));
  }

  void _addTerm(TerminalLine l) {
    _terminal.add(l);
  }

  void _scrollChat() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScroll.hasClients) {
        _chatScroll.animateTo(_chatScroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  // ── MethodChannel ──────────────────────────────────────────────

  Future<void> _checkInitialIntent() async {
    try {
      final d = await _channel.invokeMethod<Map<dynamic, dynamic>>('getInitialIntent');
      if (d != null && d['type'] != 'none') _onIntent(d);
    } catch (_) {}
  }

  Future<void> _onMethodCall(MethodCall c) async {
    _onIntent(Map<dynamic, dynamic>.from(c.arguments as Map));
  }

  void _onIntent(Map d) {
    if (!mounted) return;
    _add(TerminalLine('assistant', '\u{1f4e5} Conteudo recebido. Digite um prompt.'));
  }

  // ── Terminal Sheet ──────────────────────────────────────────────

  void _showTerminalSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, sc) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(40),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              Text('Terminal',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                      color: Theme.of(ctx).colorScheme.onSurface)),
              Text('127.0.0.1:8765',
                  style: TextStyle(fontSize: 11,
                      color: Theme.of(ctx).colorScheme.onSurface.withAlpha(80))),
              const Divider(height: 20, color: AppColors.divider),
              Expanded(
                child: ListView.builder(
                  controller: _termScroll,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _terminal.length,
                  itemBuilder: (ctx, i) => _TerminalRow(l: _terminal[i]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _termCtrl,
                        style: const TextStyle(fontSize: 13,
                            fontFamily: 'monospace', color: AppColors.teal),
                        decoration: InputDecoration(
                          hintText: 'Comando...',
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _submitTerm(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      onPressed: _submitTerm,
                      icon: const Icon(Icons.send, size: 18),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── UI ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: _AppBar(server: _server, bridge: _bridgeState, profile: _profile),
      body: _tab == 0 ? _ChatTab(this) : _ModelTab(this),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'Chat'),
          NavigationDestination(icon: Icon(Icons.model_training_outlined), selectedIcon: Icon(Icons.model_training), label: 'Modelo'),
        ],
      ),
    );
  }
}

// ── AppBar (Edge Gallery style: minimal + status dot + model chip) ─

class _AppBar extends StatelessWidget implements PreferredSizeWidget {
  const _AppBar({required this.server, required this.bridge, required this.profile});

  final ServerState server;
  final ServerState bridge;
  final HardwareProfile? profile;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  Color _dot(ServerState s, Color active) => switch (s) {
        ServerState.online => active,
        ServerState.offline => AppColors.redAccent,
        ServerState.unknown => Colors.white24,
      };

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.scaffold,
      elevation: 0,
      scrolledUnderElevation: 0,
      title: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _dot(server, Colors.greenAccent),
              boxShadow: server == ServerState.online
                  ? [BoxShadow(color: Colors.greenAccent.withAlpha(80), blurRadius: 4)]
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          Text('Droid Harness',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface, letterSpacing: -0.3)),
          const Spacer(),
          if (profile != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.teal.withAlpha(20),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.teal.withAlpha(40)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.memory, size: 14, color: AppColors.teal),
                  const SizedBox(width: 6),
                  Text(profile!.modelId,
                      style: TextStyle(fontSize: 11, color: AppColors.teal)),
                ],
              ),
            ),
          if (profile != null) const SizedBox(width: 8),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _dot(bridge, AppColors.teal),
              boxShadow: bridge == ServerState.online
                  ? [BoxShadow(color: AppColors.teal.withAlpha(80), blurRadius: 4)]
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Chat Tab ───────────────────────────────────────────────────────

class _ChatTab extends StatefulWidget {
  final _HarnessHomePageState parent;
  const _ChatTab(this.parent);
  @override
  State<_ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<_ChatTab> {
  _HarnessHomePageState get p => widget.parent;

  @override
  Widget build(BuildContext context) {
    final hasProfile = p._profile != null;
    final isOnline = p._server == ServerState.online;
    final isDownloading = p._downloading;
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        // Status bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              _StatusDot(label: 'LLM', state: p._server, activeColor: Colors.greenAccent),
              const SizedBox(width: 12),
              _StatusDot(label: 'Bridge', state: p._bridgeState, activeColor: AppColors.teal),
              if (p._profile != null) ...[
                const SizedBox(width: 12),
                Text(p._profile!.modelId.split('-').first,
                    style: TextStyle(fontSize: 11, color: cs.onSurface.withAlpha(80))),
              ],
              const Spacer(),
              // Terminal button
              _TerminalButton(parent: p),
            ],
          ),
        ),
        const Divider(height: 1, color: AppColors.divider),

        // Messages
        Expanded(
          child: p._messages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_awesome, size: 48, color: AppColors.teal.withAlpha(80)),
                      const SizedBox(height: 16),
                      Text(p._bridgeState == ServerState.online
                          ? 'Modelo pronto para download'
                          : 'Aguardando bridge Termux...',
                          style: TextStyle(color: cs.onSurface.withAlpha(120), fontSize: 15)),
                      const SizedBox(height: 8),
                      Text(p._bridgeState == ServerState.online
                          ? 'Toque em Baixar + Iniciar abaixo'
                          : 'O app tenta conectar automaticamente',
                          style: TextStyle(color: cs.onSurface.withAlpha(60), fontSize: 13)),
                    ],
                  ),
                )
              : ListView.separated(
                  controller: p._chatScroll,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  itemCount: p._messages.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (ctx, i) => _ChatBubble(m: p._messages[i]),
                ),
        ),

        // Input bar
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          decoration: BoxDecoration(
            color: AppColors.scaffold,
            border: Border(top: BorderSide(color: AppColors.divider)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Download button (Edge Gallery: prominent, cards-style)
              if (hasProfile && !isOnline && !isDownloading)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => p._downloadAndStart(),
                    icon: const Icon(Icons.rocket_launch, size: 18),
                    label: const Text('Baixar + Iniciar modelo',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.tealDark,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              if (isDownloading)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: null,
                    icon: const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                    label: const Text('Baixando modelo...',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.tealDark,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              if (hasProfile && isDownloading || hasProfile && !isOnline) const SizedBox(height: 8),

              // Text input (Edge Gallery: rounded, minimal)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: p._prompt,
                      enabled: isOnline && !p._sending,
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: isOnline
                            ? 'Digite um prompt...'
                            : 'Modelo offline',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => p._send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: isOnline && !p._sending ? () => p._send() : null,
                    icon: p._sending
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.arrow_upward),
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.teal,
                      foregroundColor: AppColors.tealText,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Model Tab (Edge Gallery Model Manager style) ───────────────────

class _ModelTab extends StatefulWidget {
  final _HarnessHomePageState parent;
  const _ModelTab(this.parent);
  @override
  State<_ModelTab> createState() => _ModelTabState();
}

class _ModelTabState extends State<_ModelTab> {
  _HarnessHomePageState get p => widget.parent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Model Card (Edge Gallery: card with icon, model info, status, action)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.memory, color: AppColors.teal),
                    const SizedBox(width: 12),
                    Text('Modelo Local',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
                            color: cs.onSurface)),
                    const Spacer(),
                    _StatusDot(label: p._server == ServerState.online ? 'Online' : 'Offline',
                        state: p._server, activeColor: Colors.greenAccent),
                  ],
                ),
                const SizedBox(height: 16),
                if (p._profile != null) ...[
                  _InfoRow('Modelo', p._profile!.modelId),
                  _InfoRow('Perfil', p._profile!.profile),
                  _InfoRow('Contexto', '${p._profile!.context} tokens'),
                  _InfoRow('GPU layers', 'ngl=${p._profile!.ngl}'),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: p._downloading ? null : () => p._downloadAndStart(),
                          icon: p._downloading
                              ? const SizedBox(width: 16, height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.download, size: 18),
                          label: Text(p._downloading ? 'Baixando...' : 'Baixar + Iniciar'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.tealDark,
                            minimumSize: const Size.fromHeight(44),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  Text('Aguardando deteccao...',
                      style: TextStyle(color: cs.onSurface.withAlpha(100))),
                  const SizedBox(height: 8),
                  if (p._bridgeState == ServerState.offline)
                    Text('Bridge offline. Inicie o bridge no Termux.',
                        style: TextStyle(fontSize: 12, color: AppColors.redAccent)),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Bridge Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.terminal, color: AppColors.teal),
                    const SizedBox(width: 12),
                    Text('Bridge Termux',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
                            color: cs.onSurface)),
                    const Spacer(),
                    _StatusDot(label: p._bridgeState == ServerState.online ? 'Online' : 'Offline',
                        state: p._bridgeState, activeColor: AppColors.teal),
                  ],
                ),
                const SizedBox(height: 12),
                Text(p._bridgeState == ServerState.online
                    ? 'Conectado em 127.0.0.1:8765'
                    : 'Bridge desconectado',
                    style: TextStyle(fontSize: 13, color: cs.onSurface.withAlpha(120))),
                if (p._bridgeState == ServerState.offline) ...[
                  const SizedBox(height: 8),
                  Text('No Termux, execute:',
                      style: TextStyle(fontSize: 12, color: cs.onSurface.withAlpha(100))),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(60),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('cd ~/droid-harness\nbash scripts/start-termux-bridge.sh',
                        style: TextStyle(fontSize: 11, fontFamily: 'monospace',
                            color: AppColors.teal)),
                  ),
                ],
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => p._showTerminalSheet(),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Abrir terminal'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Terminal Bottom Sheet (Edge Gallery: bottom sheet modal) ──────

// ── Widget: Status Dot (Edge Gallery style) ───────────────────────

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.label, required this.state, required this.activeColor});
  final String label;
  final ServerState state;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    final c = switch (state) {
      ServerState.online => activeColor,
      ServerState.offline => AppColors.redAccent,
      ServerState.unknown => Colors.white24,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6, height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c,
            boxShadow: state == ServerState.online
                ? [BoxShadow(color: c.withAlpha(80), blurRadius: 4)]
                : null,
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 11, color: c.withAlpha(200))),
      ],
    );
  }
}

class _TerminalButton extends StatelessWidget {
  final _HarnessHomePageState parent;
  const _TerminalButton({required this.parent});
  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.terminal, size: 20),
      onPressed: () => parent._showTerminalSheet(),
      tooltip: 'Terminal',
      style: IconButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.onSurface.withAlpha(120),
        backgroundColor: AppColors.card,
        padding: const EdgeInsets.all(8),
        minimumSize: const Size(36, 36),
      ),
    );
  }
}

// ── Widget: Info Row ──────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text('$label  ',
              style: const TextStyle(fontSize: 13, color: Colors.white54)),
          Text(value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500,
                  color: Colors.white)),
        ],
      ),
    );
  }
}

// ── Widget: Chat Bubble (Edge Gallery: 24px radius, asymmetric) ──

class _ChatBubble extends StatelessWidget {
  final ChatMessage m;
  const _ChatBubble({required this.m});

  @override
  Widget build(BuildContext context) {
    final isUser = m.role == MessageRole.user;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(top: 4, bottom: 4, left: isUser ? 48 : 0, right: isUser ? 0 : 48),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser)
            CircleAvatar(radius: 14,
                backgroundColor: AppColors.teal.withAlpha(30),
                child: Icon(Icons.auto_awesome, size: 14, color: AppColors.teal)),
          if (!isUser) const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isUser ? AppColors.tealDark.withAlpha(50) : AppColors.card,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(24),
                  topRight: const Radius.circular(24),
                  bottomLeft: isUser ? const Radius.circular(24) : const Radius.circular(4),
                  bottomRight: isUser ? const Radius.circular(4) : const Radius.circular(24),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isUser)
                    Padding(padding: const EdgeInsets.only(bottom: 6),
                        child: Text('Droid Harness',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                                color: AppColors.teal))),
                  SelectableText(m.text,
                      style: TextStyle(fontSize: 14, height: 1.5,
                          color: isUser ? Colors.white : cs.onSurface)),
                ],
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 8),
          if (isUser)
            CircleAvatar(radius: 14,
                backgroundColor: AppColors.tealDark.withAlpha(40),
                child: const Icon(Icons.person, size: 14, color: Colors.white54)),
        ],
      ),
    );
  }
}

// ── Widget: Terminal Row ──────────────────────────────────────────

class _TerminalRow extends StatelessWidget {
  final TerminalLine l;
  const _TerminalRow({required this.l});

  Color _c() => switch (l.kind) {
        TerminalLineKind.command => AppColors.teal,
        TerminalLineKind.system => Colors.white54,
        TerminalLineKind.error => AppColors.redAccent,
        TerminalLineKind.output => Colors.white,
      };

  String _p() => switch (l.kind) {
        TerminalLineKind.command => '\u25b6 ',
        TerminalLineKind.system => '  ',
        TerminalLineKind.error => '\u2717 ',
        TerminalLineKind.output => '  ',
      };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Text.rich(TextSpan(
        children: [
          TextSpan(text: _p(), style: TextStyle(color: _c(), fontSize: 12)),
          TextSpan(text: l.text, style: TextStyle(
            color: _c().withAlpha(l.kind == TerminalLineKind.output ? 255 : 200),
            fontSize: 12, fontFamily: 'monospace')),
        ],
      )),
    );
  }
}

// ── Temperature type for instant messages ──────────────────────────

class TerminalLine {
  const TerminalLine._(this.role, this.text, this.kind);

  factory TerminalLine(String role, String text) =>
      TerminalLine._(role, text, TerminalLineKind.system);

  factory TerminalLine.fromBridge(BridgeTerminalEvent e) => switch (e.kind) {
        'error' => TerminalLine.error(e.text),
        'system' => TerminalLine.system(e.text),
        _ => TerminalLine.output(e.text),
      };

  factory TerminalLine.command(String t) =>
      TerminalLine._('system', t, TerminalLineKind.command);
  factory TerminalLine.error(String t) =>
      TerminalLine._('system', t, TerminalLineKind.error);
  factory TerminalLine.output(String t) =>
      TerminalLine._('system', t, TerminalLineKind.output);
  factory TerminalLine.system(String t) =>
      TerminalLine._('system', t, TerminalLineKind.system);

  final String role;
  final String text;
  final TerminalLineKind kind;
}

// ── Clients ────────────────────────────────────────────────────────

class LocalLlmClient {
  static final _http = HttpClient();

  Future<bool> healthCheck() async {
    try {
      final r = await _http
          .getUrl(Uri.parse('http://127.0.0.1:8080/v1/models'))
          .timeout(const Duration(seconds: 2));
      return (await r.close()).statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<String> chat(String prompt) async {
    try {
      final r = await _http
          .postUrl(Uri.parse('http://127.0.0.1:8080/v1/chat/completions'))
          .timeout(const Duration(seconds: 2));
      r.headers.contentType = ContentType.json;
      r.write(jsonEncode({
        'model': 'local-model',
        'messages': [{'role': 'user', 'content': prompt}],
        'max_tokens': 512,
        'temperature': 0.7,
      }));
      final res = await r.close().timeout(const Duration(seconds: 30));
      final body = await utf8.decodeStream(res);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw LocalLlmException('HTTP ${res.statusCode}');
      }
      final d = jsonDecode(body) as Map<String, dynamic>;
      return (d['choices'] as List?)?.firstOrNull?['message']?['content']?.toString() ?? '';
    } on LocalLlmException {
      rethrow;
    } on TimeoutException {
      throw const LocalLlmException('Timeout. Modelo sobrecarregado.');
    } on SocketException {
      throw const LocalLlmException('llama-server offline');
    }
  }
}

class TermuxBridgeClient {
  static const _base = 'http://127.0.0.1:8765';
  static final _http = HttpClient();

  Future<bool> healthCheck() async {
    try {
      final r = await _http.getUrl(Uri.parse('$_base/health'))
          .timeout(const Duration(seconds: 2));
      return (await r.close()).statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<HardwareProfile> hardwareProfile() async {
    final b = await _get('/hardware');
    return HardwareProfile.fromJson(jsonDecode(b) as Map<String, dynamic>);
  }

  Future<void> startSession() => _post('/terminal/session', {});
  Future<void> sendInput(String d) => _post('/terminal/input', {'data': d});

  Future<TerminalEventsResult> events({required int after}) async {
    final b = await _get('/terminal/events?after=$after');
    final d = jsonDecode(b) as Map<String, dynamic>;
    return TerminalEventsResult(
      events: (d['events'] as List).map((e) =>
          BridgeTerminalEvent.fromJson(e as Map)).toList(),
      next: (d['next'] as num?)?.toInt() ?? after,
    );
  }

  Future<void> downloadModel(String m) => _post('/models/download', {'model': m});
  Future<void> startLocalModel(String p) => _post('/llm/start', {'profile': p});

  Future<String> _get(String path) async {
    try {
      final r = await _http.getUrl(Uri.parse('$_base$path'))
          .timeout(const Duration(seconds: 2));
      final res = await r.close().timeout(const Duration(seconds: 3));
      final b = await utf8.decodeStream(res);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw BridgeException('HTTP ${res.statusCode}');
      }
      return b;
    } on BridgeException {
      rethrow;
    } on TimeoutException {
      throw const BridgeException('Timeout bridge');
    } on SocketException {
      throw const BridgeException('Bridge offline');
    }
  }

  Future<void> _post(String path, Map<String, Object?> body) async {
    try {
      final r = await _http.postUrl(Uri.parse('$_base$path'))
          .timeout(const Duration(seconds: 2));
      r.headers.contentType = ContentType.json;
      r.write(jsonEncode(body));
      final res = await r.close().timeout(const Duration(seconds: 3));
      final b = await utf8.decodeStream(res);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw BridgeException('HTTP ${res.statusCode}: $b');
      }
    } on BridgeException {
      rethrow;
    } on TimeoutException {
      throw const BridgeException('Timeout bridge');
    } on SocketException {
      throw const BridgeException('Bridge offline');
    }
  }
}

// ── Models ─────────────────────────────────────────────────────────

class TerminalEventsResult {
  final List<BridgeTerminalEvent> events;
  final int next;
  TerminalEventsResult({required this.events, required this.next});
}

class BridgeTerminalEvent {
  final int id;
  final String kind;
  final String text;
  BridgeTerminalEvent({required this.id, required this.kind, required this.text});

  factory BridgeTerminalEvent.fromJson(Map d) => BridgeTerminalEvent(
    id: (d['id'] as num?)?.toInt() ?? 0,
    kind: d['kind']?.toString() ?? 'stdout',
    text: d['text']?.toString() ?? '',
  );
}

class HardwareProfile {
  final String profile;
  final String modelId;
  final String modelPath;
  final int context;
  final int ngl;

  HardwareProfile({required this.profile, required this.modelId,
      required this.modelPath, required this.context, required this.ngl});

  factory HardwareProfile.fromJson(Map<String, dynamic> j) => HardwareProfile(
    profile: j['profile']?.toString() ?? 'weak',
    modelId: j['model_id']?.toString() ?? 'qwen3-0.6b-q4_k_m',
    modelPath: j['model_path']?.toString() ?? '',
    context: (j['context'] as num?)?.toInt() ?? 1536,
    ngl: (j['ngl'] as num?)?.toInt() ?? 0,
  );
}

class ChatMessage {
  final MessageRole role;
  final String text;
  ChatMessage({required this.role, required this.text});
}

class LocalLlmException implements Exception {
  final String message;
  const LocalLlmException(this.message);
}

class BridgeException implements Exception {
  final String message;
  const BridgeException(this.message);
}
