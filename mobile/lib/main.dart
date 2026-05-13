import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const DroidHarnessApp());

// ═══════════════════════════════════════════════════════════════════
//  Palette — Google AI Edge Gallery
// ═══════════════════════════════════════════════════════════════════

class Palette {
  static const scaffold = Color(0xff0f1114);
  static const surface = Color(0xff1a1c1e);
  static const card = Color(0xff1e2024);
  static const teal = Color(0xff80cbc4);
  static const tealDark = Color(0xff008577);
  static const accent = Color(0xff69f0ae);
  static const error = Color(0xffff7043);
  static const divider = Color(0xff2c2e30);
  static const disabled = Color(0xff424242);
}

// ═══════════════════════════════════════════════════════════════════
//  Models
// ═══════════════════════════════════════════════════════════════════

enum ModelStatus { notDownloaded, downloading, downloaded, active }

class LocalModel {
  final String id, name, description, size, task, url;
  bool recommended;
  ModelStatus status;
  double progress; // 0.0 to 1.0 for download

  LocalModel({
    required this.id, required this.name, required this.description,
    required this.size, required this.task, required this.url,
    this.recommended = false,
    this.status = ModelStatus.notDownloaded,
    this.progress = 0.0,
  });
}

// HuggingFace download URLs — app baixa direto, sem bridge/termux
final List<LocalModel> kModels = [
  LocalModel(
    id: 'gemma-3-1b-q4_k_m', name: 'Gemma 3 1B',
    description: 'Google Gemma 3. Excelente para mobile. Leve e inteligente.',
    size: '~700 MB', task: 'Chat',
    url: 'https://huggingface.co/brittlewis12/Gemma-3-1B-it-Q4_K_M-GGUF/resolve/main/gemma-3-1b-it-q4_k_m.gguf',
  ),
  LocalModel(
    id: 'qwen3-0.6b-q4_k_m', name: 'Qwen3 0.6B',
    description: 'Leve e rápido. Ideal para dispositivos com menos de 7GB RAM.',
    size: '~500 MB', task: 'Chat',
    url: 'https://huggingface.co/rippertnt/Qwen3-0.6B-Q4_K_M-GGUF/resolve/main/qwen3-0.6b-q4_k_m.gguf',
  ),
  LocalModel(
    id: 'qwen3-1.7b-q4_k_m', name: 'Qwen3 1.7B',
    description: 'Equilíbrio entre qualidade e desempenho. 7-11GB RAM.',
    size: '~1 GB', task: 'Chat',
    url: 'https://huggingface.co/jc-builds/Qwen3-1.7B-Q4_K_M-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf',
  ),
  LocalModel(
    id: 'smol-v2-135m-q4_k_m', name: 'SmolV2 135M',
    description: 'Ultra-compacto. Testes rápidos.',
    size: '~100 MB', task: 'Chat',
    url: 'https://huggingface.co/HuggingFaceTB/SmolV2-135M-Instruct-GGUF/resolve/main/smolv2-135m-instruct-q4_k_m.gguf',
  ),
  LocalModel(
    id: 'qwen2.5-coder-1.5b-q4_k_m', name: 'Qwen Coder 1.5B',
    description: 'Focado em código. Recomendado para dispositivos potentes.',
    size: '~1 GB', task: 'Código',
    url: 'https://huggingface.co/Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF/resolve/main/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf',
  ),
  LocalModel(
    id: 'deepseek-coder-1.3b-q4_k_m', name: 'DeepSeek Coder 1.3B',
    description: 'Alternativa para code, menor consumo.',
    size: '~800 MB', task: 'Código',
    url: 'https://huggingface.co/deepseek-ai/deepseek-coder-1.3b-instruct-GGUF/resolve/main/deepseek-coder-1.3b-instruct-q4_k_m.gguf',
  ),
  LocalModel(
    id: 'gemma-3-4b-q4_k_m', name: 'Gemma 3 4B',
    description: 'Google Gemma 3 4B. Qualidade superior. 8GB+ RAM.',
    size: '~2.5 GB', task: 'Chat',
    url: 'https://huggingface.co/brittlewis12/Gemma-3-4B-it-Q4_K_M-GGUF/resolve/main/gemma-3-4b-it-q4_k_m.gguf',
  ),
  LocalModel(
    id: 'llama-3.2-3b-q4_k_m', name: 'Llama 3.2 3B',
    description: 'Maior qualidade, maior consumo. Snapdragon 8+.',
    size: '~2 GB', task: 'Chat',
    url: 'https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf',
  ),
];

// ═══════════════════════════════════════════════════════════════════
//  App
// ═══════════════════════════════════════════════════════════════════

class DroidHarnessApp extends StatelessWidget {
  const DroidHarnessApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Droid Harness',
      theme: ThemeData(
        useMaterial3: true, brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Palette.teal, brightness: Brightness.dark,
          surface: Palette.surface, primary: Palette.teal,
          onPrimary: const Color(0xff00332e),
          surfaceTint: Palette.teal,
        ),
        scaffoldBackgroundColor: Palette.scaffold,
        cardTheme: CardThemeData(
          color: Palette.card, elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true, fillColor: Palette.card,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      home: const DroidHarnessShell(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  Shell
// ═══════════════════════════════════════════════════════════════════

class DroidHarnessShell extends StatefulWidget {
  const DroidHarnessShell({super.key});
  @override
  State<DroidHarnessShell> createState() => _ShellState();
}

class _ShellState extends State<DroidHarnessShell> {
  int _tab = 0;
  final _bridge = _BridgeService();
  String? _modelsDir;
  Map? _nativeHw;

  @override
  void initState() {
    super.initState();
    _bridge.start();
    _loadNativeHardware();
  }

  @override
  void dispose() {
    _bridge.dispose();
    super.dispose();
  }

  Future<void> _loadNativeHardware() async {
    try {
      final hw = await _channel.invokeMethod<Map<dynamic, dynamic>>('getHardwareProfile');
      if (hw != null && mounted) {
        setState(() => _nativeHw = Map<String, dynamic>.from(hw));
        // Marca modelo recomendado
        final recId = hw['recommendedModelId']?.toString() ?? '';
        for (final m in kModels) {
          m.recommended = m.id == recId;
        }
      }
      final dir = await _channel.invokeMethod<String>('getModelsDir');
      if (dir != null && mounted) setState(() => _modelsDir = dir);
    } catch (_) {}
  }

  static const _channel = MethodChannel('dev.droidharness/bridge');

  String _platformDir() => _modelsDir ?? '/no-dir';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.scaffold,
      appBar: AppBar(
        backgroundColor: Palette.scaffold, elevation: 0, scrolledUnderElevation: 0,
        title: Row(
          children: [
            _Dot(_bridge.llmOk, Colors.greenAccent),
            const SizedBox(width: 8),
            Text('Droid Harness', style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface, letterSpacing: -0.3)),
            const Spacer(),
            if (_nativeHw != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Palette.teal.withAlpha(20),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Palette.teal.withAlpha(40)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.phone_android, size: 14, color: Palette.teal),
                    const SizedBox(width: 6),
                    Text('${_nativeHw!['profile']}',
                        style: TextStyle(fontSize: 11, color: Palette.teal)),
                  ],
                ),
              ),
            const SizedBox(width: 8),
            _Dot(_bridge.bridgeOk, Palette.teal),
          ],
        ),
      ),
      body: _tab == 0 ? _ModelList(
        bridge: _bridge, nativeHw: _nativeHw, modelsDir: _platformDir(),
        onChat: () => setState(() => _tab = 1),
      ) : _ChatView(
        bridge: _bridge, onBack: () => setState(() => _tab = 0)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        backgroundColor: Palette.surface,
        indicatorColor: Palette.teal.withAlpha(30),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.model_training_outlined), selectedIcon: Icon(Icons.model_training), label: 'Modelos'),
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'Chat'),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final bool on;
  final Color active;
  const _Dot(this.on, this.active);
  @override
  Widget build(BuildContext context) {
    final c = on ? active : Palette.error;
    return Container(
      width: 8, height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle, color: c,
        boxShadow: on ? [BoxShadow(color: c.withAlpha(80), blurRadius: 4)] : null,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  Model List — funciona offline, baixa modelos direto
// ═══════════════════════════════════════════════════════════════════

class _ModelList extends StatelessWidget {
  final _BridgeService bridge;
  final Map? nativeHw;
  final String modelsDir;
  final VoidCallback onChat;

  const _ModelList({
    required this.bridge, required this.nativeHw,
    required this.modelsDir, required this.onChat,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bridgeOk = bridge.bridgeOk || bridge.connecting;

    final rec = kModels.where((m) => m.recommended).toList();
    final avail = kModels.where((m) => !m.recommended).toList();

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        // Hardware card (Edge Gallery: mostra dispositivo)
        if (nativeHw != null)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Palette.teal.withAlpha(10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Palette.teal.withAlpha(30)),
            ),
            child: Row(
              children: [
                Icon(Icons.phone_android, size: 20, color: Palette.teal),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${nativeHw!['device']}',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                              color: cs.onSurface)),
                      Text('${nativeHw!['totalRamMb']}MB RAM · ${nativeHw!['cores']} cores · ${nativeHw!['gpu']}',
                          style: TextStyle(fontSize: 11, color: cs.onSurface.withAlpha(120))),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Palette.teal.withAlpha(25),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('${nativeHw!['profile']}',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                          color: Palette.teal)),
                ),
              ],
            ),
          ),

        // Bridge offline warning
        if (!bridgeOk && !bridge.connecting)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Palette.error.withAlpha(15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Palette.error.withAlpha(40)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: Palette.error),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Para rodar o modelo, inicie o bridge no Termux',
                          style: TextStyle(fontSize: 12, color: Palette.error)),
                      const SizedBox(height: 2),
                      Text('cd ~/droid-harness && bash scripts/start-termux-bridge.sh',
                          style: TextStyle(fontSize: 11, fontFamily: 'monospace',
                              color: Palette.error.withAlpha(150))),
                    ],
                  ),
                ),
              ],
            ),
          ),

        // Download info banner
        if (bridge.connecting)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Palette.teal.withAlpha(15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 10),
                Text('Conectando ao bridge...',
                    style: TextStyle(fontSize: 12, color: Palette.teal)),
              ],
            ),
          ),

        // Recommended section
        if (rec.isNotEmpty) ...[
          _SectionHeader(title: 'Recomendado', icon: Icons.star, color: Palette.teal),
          ...rec.map((m) => _ModelCard(m, bridge, modelsDir, onChat)),
        ],

        // Available section
        _SectionHeader(title: 'Disponíveis', icon: Icons.cloud_outlined,
            color: cs.onSurface.withAlpha(120)),
        ...avail.map((m) => _ModelCard(m, bridge, modelsDir, onChat)),

        const SizedBox(height: 24),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  const _SectionHeader({required this.title, required this.icon, required this.color});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 4),
      child: Row(children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color)),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  Model Card — com download direto via HttpClient
// ═══════════════════════════════════════════════════════════════════

class _ModelCard extends StatefulWidget {
  final LocalModel model;
  final _BridgeService bridge;
  final String modelsDir;
  final VoidCallback onChat;
  const _ModelCard(this.model, this.bridge, this.modelsDir, this.onChat);
  @override
  State<_ModelCard> createState() => _ModelCardState();
}

class _ModelCardState extends State<_ModelCard> {
  LocalModel get m => widget.model;
  HttpClient? _downloadClient;
  int _downloadedBytes = 0;
  int _totalBytes = 1;

  bool get _downloading => m.status == ModelStatus.downloading;

  @override
  void initState() {
    super.initState();
    // Verifica se o modelo já foi baixado
    _checkIfDownloaded();
  }

  Future<void> _checkIfDownloaded() async {
    final dir = Directory('${widget.modelsDir}/${m.id}');
    final file = File('${dir.path}/${m.id}.gguf');
    if (await file.exists()) {
      if (mounted) setState(() => m.status = ModelStatus.downloaded);
    }
  }

  Future<void> _download() async {
    if (_downloading) return;

    setState(() {
      m.status = ModelStatus.downloading;
      m.progress = 0.001;
    });

    try {
      final dir = Directory('${widget.modelsDir}/${m.id}');
      await dir.create(recursive: true);
      final file = File('${dir.path}/${m.id}.gguf');
      final tempFile = File('${dir.path}/${m.id}.gguf.part');

      _downloadClient = HttpClient();
      _downloadClient!.connectionTimeout = const Duration(seconds: 30);

      final request = await _downloadClient!
          .getUrl(Uri.parse(m.url))
          .timeout(const Duration(seconds: 15));

      request.headers.set('User-Agent', 'DroidHarness/1.0');

      final response = await request.close().timeout(
          const Duration(minutes: 30));

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      _totalBytes = response.contentLength;
      if (_totalBytes <= 0) _totalBytes = 1;

      final sink = tempFile.openWrite();
      sink.close();

      // Na verdade, precisamos de download binário. Vou usar HttpClient
      // com stream de bytes direto.
      await _downloadBinary(response, file, tempFile);

      if (mounted) {
        setState(() {
          m.status = ModelStatus.downloaded;
          m.progress = 1.0;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => m.status = ModelStatus.notDownloaded);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    }
  }

  Future<void> _downloadBinary(
      HttpClientResponse response, File file, File tempFile) async {
    final sink = tempFile.openWrite();
    _downloadedBytes = 0;
    _totalBytes = response.contentLength;

    await for (final chunk in response) {
      sink.add(chunk);
      _downloadedBytes += chunk.length;
      if (_totalBytes > 0 && mounted) {
        setState(() => m.progress = _downloadedBytes / _totalBytes);
      }
    }
    await sink.close();
    await tempFile.rename(file.path);
  }

  Future<void> _start() async {
    if (!widget.bridge.bridgeOk) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bridge offline. Inicie no Termux primeiro.')),
      );
      return;
    }
    m.status = ModelStatus.downloading;
    try {
      // Bridge precisa saber onde está o modelo
      await widget.bridge.client.startLlm('auto');
      m.status = ModelStatus.active;
      widget.onChat();
      if (mounted) setState(() {});
    } catch (e) {
      m.status = ModelStatus.downloaded;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao iniciar: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isActive = m.status == ModelStatus.active;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.memory, size: 20, color: Palette.teal),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text(m.name, style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600,
                            color: cs.onSurface)),
                        const SizedBox(width: 8),
                        if (m.recommended)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Palette.teal.withAlpha(25),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Palette.teal.withAlpha(50)),
                            ),
                            child: Text('Recomendado',
                                style: TextStyle(fontSize: 9, color: Palette.teal)),
                          ),
                      ]),
                      Text('${m.size} · ${m.task}',
                          style: TextStyle(fontSize: 12,
                              color: cs.onSurface.withAlpha(100))),
                    ],
                  ),
                ),
                if (isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Palette.accent.withAlpha(25),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.play_circle, size: 14, color: Palette.accent),
                        const SizedBox(width: 4),
                        Text('Ativo', style: TextStyle(fontSize: 11, color: Palette.accent)),
                      ],
                    ),
                  ),
              ]),
              const SizedBox(height: 8),
              Text(m.description, style: TextStyle(
                  fontSize: 12, color: cs.onSurface.withAlpha(150))),

              // Download progress
              if (_downloading) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: m.progress,
                    backgroundColor: cs.surface,
                    color: Palette.teal,
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 4),
                Text('${(m.progress * 100).toStringAsFixed(0)}% · '
                    '${(_downloadedBytes ~/ 1048576)}MB / ${(_totalBytes ~/ 1048576)}MB',
                    style: TextStyle(fontSize: 10, color: Palette.teal)),
              ],

              // Action button
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: m.status == ModelStatus.notDownloaded
                    ? OutlinedButton.icon(
                        onPressed: _download,
                        icon: const Icon(Icons.download, size: 16),
                        label: const Text('Baixar modelo'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Palette.teal,
                          side: BorderSide(color: Palette.teal.withAlpha(80)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      )
                    : m.status == ModelStatus.downloaded
                        ? FilledButton.icon(
                            onPressed: widget.bridge.bridgeOk ? _start : null,
                            icon: Icon(widget.bridge.bridgeOk
                                ? Icons.play_arrow : Icons.cloud_off, size: 16),
                            label: Text(widget.bridge.bridgeOk
                                ? 'Iniciar modelo' : 'Bridge offline'),
                            style: FilledButton.styleFrom(
                              backgroundColor: widget.bridge.bridgeOk
                                  ? Palette.tealDark : Palette.disabled,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          )
                        : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


// ═══════════════════════════════════════════════════════════════════
//  Chat
// ═══════════════════════════════════════════════════════════════════

class _ChatView extends StatefulWidget {
  final _BridgeService bridge;
  final VoidCallback onBack;
  const _ChatView({required this.bridge, required this.onBack});
  @override
  State<_ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<_ChatView> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final _msgs = <_Msg>[];
  bool _sending = false;

  @override
  void dispose() { _ctrl.dispose(); _scroll.dispose(); super.dispose(); }

  Future<void> _send() async {
    final t = _ctrl.text.trim();
    if (t.isEmpty || _sending || !widget.bridge.llmOk) return;
    setState(() { _sending = true; _msgs.add(_Msg('user', t)); _ctrl.clear(); });
    _scrollDown();
    try {
      final r = await widget.bridge.client.chat(t);
      if (mounted) setState(() { _msgs.add(_Msg('assistant', r)); _sending = false; });
    } catch (e) {
      if (mounted) setState(() { _msgs.add(_Msg('assistant', 'Erro: $e')); _sending = false; });
    }
    _scrollDown();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ok = widget.bridge.llmOk;
    return Column(children: [
      if (!ok)
        Container(
          width: double.infinity, padding: const EdgeInsets.all(10),
          color: Palette.error.withAlpha(20),
          child: Text('Modelo offline. Baixe e inicie na aba Modelos.',
              style: TextStyle(fontSize: 12, color: Palette.error)),
        ),
      Expanded(
        child: _msgs.isEmpty
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.auto_awesome, size: 48, color: Palette.teal.withAlpha(80)),
                const SizedBox(height: 16),
                Text('Chat com IA local', style: TextStyle(
                    fontSize: 16, color: cs.onSurface.withAlpha(120))),
                const SizedBox(height: 8),
                Text('Baixe um modelo na aba Modelos',
                    style: TextStyle(fontSize: 13, color: cs.onSurface.withAlpha(60))),
              ]))
            : ListView.builder(
                controller: _scroll, padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                itemCount: _msgs.length,
                itemBuilder: (ctx, i) => _Bubble(msg: _msgs[i])),
      ),
      Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: BoxDecoration(
          color: Palette.scaffold,
          border: Border(top: BorderSide(color: Palette.divider))),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _ctrl, enabled: ok && !_sending,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: ok ? 'Digite um prompt...' : 'Modelo offline',
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send()),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: ok && !_sending ? _send : null,
            icon: _sending
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.arrow_upward),
            style: IconButton.styleFrom(
              backgroundColor: Palette.teal, foregroundColor: const Color(0xff00332e),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
          ),
        ]),
      ),
    ]);
  }
}

class _Msg {
  final String role, text;
  _Msg(this.role, this.text);
}

class _Bubble extends StatelessWidget {
  final _Msg msg;
  const _Bubble({required this.msg});
  @override
  Widget build(BuildContext context) {
    final isUser = msg.role == 'user';
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(top: 4, bottom: 4,
          left: isUser ? 48 : 0, right: isUser ? 0 : 48),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser)
            CircleAvatar(radius: 14,
                backgroundColor: Palette.teal.withAlpha(30),
                child: Icon(Icons.auto_awesome, size: 14, color: Palette.teal)),
          if (!isUser) const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isUser ? Palette.tealDark.withAlpha(50) : Palette.card,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(24), topRight: const Radius.circular(24),
                  bottomLeft: isUser ? const Radius.circular(24) : const Radius.circular(4),
                  bottomRight: isUser ? const Radius.circular(4) : const Radius.circular(24),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isUser)
                    Padding(padding: const EdgeInsets.only(bottom: 6),
                        child: Text('Droid Harness', style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w600,
                            color: Palette.teal))),
                  SelectableText(msg.text, style: TextStyle(
                      fontSize: 14, height: 1.5,
                      color: isUser ? Colors.white : cs.onSurface)),
                ],
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 8),
          if (isUser)
            CircleAvatar(radius: 14,
                backgroundColor: Palette.tealDark.withAlpha(40),
                child: const Icon(Icons.person, size: 14, color: Colors.white54)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  Bridge Service
// ═══════════════════════════════════════════════════════════════════

class _BridgeService {
  bool bridgeOk = false;
  bool llmOk = false;
  bool connecting = true;
  final client = TermuxClient();
  Timer? _retryTimer;
  int _retries = 0;

  void start() {
    _tryConnect();
    Timer.periodic(const Duration(seconds: 2), (_) => _checkLlm());
  }

  void dispose() { _retryTimer?.cancel(); }

  void _tryConnect() {
    if (_retries >= 25) { connecting = false; return; }
    _retries++;
    unawaited(_connect());
  }

  Future<void> _connect() async {
    try {
      if (await client.health()) {
        _retryTimer?.cancel();
        bridgeOk = true;
        connecting = false;
        return;
      }
    } catch (_) {}
    connecting = _retries < 25;
    _retryTimer = Timer(const Duration(seconds: 3), _tryConnect);
  }

  Future<void> _checkLlm() async {
    try {
      final c = HttpClient();
      final r = await c.getUrl(Uri.parse('http://127.0.0.1:8080/v1/models'))
          .timeout(const Duration(seconds: 2));
      llmOk = (await r.close()).statusCode == 200;
    } catch (_) { llmOk = false; }
  }
}

class TermuxClient {
  static final _http = HttpClient();

  Future<bool> health() async {
    try {
      final r = await _http.getUrl(Uri.parse('http://127.0.0.1:8765/health'))
          .timeout(const Duration(seconds: 2));
      return (await r.close()).statusCode == 200;
    } catch (_) { return false; }
  }

  Future<void> startLlm(String p) => _post('/llm/start', {'profile': p});

  Future<String> chat(String prompt) async {
    final r = await _http
        .postUrl(Uri.parse('http://127.0.0.1:8080/v1/chat/completions'))
        .timeout(const Duration(seconds: 2));
    r.headers.contentType = ContentType.json;
    r.write(jsonEncode({
      'model': 'local-model',
      'messages': [{'role': 'user', 'content': prompt}],
      'max_tokens': 512, 'temperature': 0.7,
    }));
    final res = await r.close().timeout(const Duration(seconds: 30));
    final body = await utf8.decodeStream(res);
    if (res.statusCode < 200 || res.statusCode >= 300) throw Exception('HTTP ${res.statusCode}');
    final d = jsonDecode(body) as Map<String, dynamic>;
    return (d['choices'] as List?)?.firstOrNull?['message']?['content']?.toString() ?? '';
  }

  Future<void> _post(String path, Map<String, Object?> body) async {
    try {
      final r = await _http.postUrl(Uri.parse('http://127.0.0.1:8765$path'))
          .timeout(const Duration(seconds: 2));
      r.headers.contentType = ContentType.json;
      r.write(jsonEncode(body));
      final res = await r.close().timeout(const Duration(seconds: 3));
      if (res.statusCode < 200 || res.statusCode >= 300) throw Exception('HTTP ${res.statusCode}');
    } on TimeoutException { throw Exception('Timeout bridge'); }
    on SocketException { throw Exception('Bridge offline'); }
  }
}
