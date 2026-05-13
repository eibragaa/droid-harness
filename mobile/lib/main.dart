import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════
//  Droid Harness Mobile v1.4.0 — Google AI Edge Gallery style
// ═══════════════════════════════════════════════════════════════════
//
//  Screens:  ModelList (home) → Chat (when model online)
//            Terminal (drawer/bottom sheet)
//  Design:   Material 3 Dark, teal #80cbc4 seed
//            Drawer navigation: Models | Chat | Terminal
//  Bridge:   Auto-retry 25x, session + profile on connect
// ═══════════════════════════════════════════════════════════════════

void main() => runApp(const DroidHarnessApp());

// ── Colors (Google AI Edge Gallery palette) ────────────────────────

class Palette {
  static const scaffold  = Color(0xff0f1114);
  static const surface   = Color(0xff1a1c1e);
  static const card      = Color(0xff1e2024);
  static const teal      = Color(0xff80cbc4);
  static const tealDark  = Color(0xff008577);
  static const tealDim   = Color(0xff00332e);
  static const accent    = Color(0xff69f0ae);
  static const error     = Color(0xffff7043);
  static const divider   = Color(0xff2c2e30);
  static const disabled  = Color(0xff424242);
}

// ── Models ─────────────────────────────────────────────────────────

enum ModelStatus { notDownloaded, downloading, downloaded, active }

class LocalModel {
  final String id;
  final String name;
  final String description;
  final String size;
  final String task;
  bool recommended;
  ModelStatus status;

  LocalModel({
    required this.id, required this.name, required this.description,
    required this.size, required this.task,
    this.recommended = false,
    this.status = ModelStatus.notDownloaded,
  });
}

final List<LocalModel> kModels = [
  LocalModel(
    id: 'qwen3-0.6b-q4_k_m',
    name: 'Qwen3 0.6B',
    description: 'Leve e rápido. Ideal para dispositivos com menos de 7GB RAM.',
    size: '~500 MB', task: 'Chat',
  ),
  LocalModel(
    id: 'qwen3-1.7b-q4_k_m',
    name: 'Qwen3 1.7B',
    description: 'Equilíbrio entre qualidade e desempenho. 7-11GB RAM.',
    size: '~1 GB', task: 'Chat',
  ),
  LocalModel(
    id: 'qwen2.5-coder-1.5b-q4_k_m',
    name: 'Qwen Coder 1.5B',
    description: 'Focado em código. Recomendado para dispositivos potentes.',
    size: '~1 GB', task: 'Código',
  ),
  LocalModel(
    id: 'deepseek-coder-1.3b-q4_k_m',
    name: 'DeepSeek Coder 1.3B',
    description: 'Alternativa para code, menor consumo.',
    size: '~800 MB', task: 'Código',
  ),
  LocalModel(
    id: 'smol-v2-135m-q4_k_m',
    name: 'SmolV2 135M',
    description: 'Ultra-compacto. Testes rápidos e dispositivos muito limitados.',
    size: '~100 MB', task: 'Chat',
  ),
  LocalModel(
    id: 'llama-3.2-3b-q4_k_m',
    name: 'Llama 3.2 3B',
    description: 'Maior qualidade, maior consumo. Snapdragon 8+ Gen 1.',
    size: '~2 GB', task: 'Chat',
  ),
];

// ── Enums ──────────────────────────────────────────────────────────

enum ServerState { unknown, online, offline }
enum TerminalLineKind { command, system, output, error }

// ── App ────────────────────────────────────────────────────────────

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
          onPrimary: Palette.tealDim,
          surfaceTint: Palette.teal,
        ),
        scaffoldBackgroundColor: Palette.scaffold,
        cardTheme: CardThemeData(
          color: Palette.card, elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        navigationDrawerTheme: NavigationDrawerThemeData(
          backgroundColor: Palette.surface,
          indicatorColor: Palette.teal.withAlpha(30),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true, fillColor: Palette.card,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: Palette.card, selectedColor: Palette.teal.withAlpha(30),
          labelStyle: const TextStyle(fontSize: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
      ),
      home: const DroidHarnessShell(),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  Shell — Drawer + screen switching
// ══════════════════════════════════════════════════════════════════

class DroidHarnessShell extends StatefulWidget {
  const DroidHarnessShell({super.key});
  @override
  State<DroidHarnessShell> createState() => _DroidHarnessShellState();
}

class _DroidHarnessShellState extends State<DroidHarnessShell> {
  int _page = 0; // 0=Models, 1=Chat
  final _bridgeState = _BridgeState();
  final _chatState = _ChatState();
  final _termState = _TerminalState();

  @override
  void initState() {
    super.initState();
    _bridgeState.start(_chatState, _termState);
  }

  @override
  void dispose() {
    _bridgeState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bridge = _bridgeState;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Palette.scaffold,
      appBar: AppBar(
        backgroundColor: Palette.scaffold, elevation: 0, scrolledUnderElevation: 0,
        title: Row(
          children: [
            _Dot(bridge.llmState, Colors.greenAccent),
            const SizedBox(width: 8),
            Text('Droid Harness',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600,
                    color: cs.onSurface, letterSpacing: -0.3)),
            const Spacer(),
            if (bridge.profile != null)
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
                    Icon(Icons.memory, size: 14, color: Palette.teal),
                    const SizedBox(width: 6),
                    Text(bridge.profile!.modelId.split('-').first,
                        style: TextStyle(fontSize: 11, color: Palette.teal)),
                  ],
                ),
              ),
            const SizedBox(width: 8),
            _Dot(bridge.bridgeState, Palette.teal),
          ],
        ),
      ),
      drawer: NavigationDrawer(
        selectedIndex: _page,
        onDestinationSelected: (i) {
          setState(() => _page = i);
          Navigator.pop(context);
        },
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 16, 8),
            child: Text('Droid Harness',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                    color: cs.onSurface.withAlpha(150))),
          ),
          NavigationDrawerDestination(
            icon: const Icon(Icons.model_training_outlined),
            selectedIcon: const Icon(Icons.model_training),
            label: const Text('Modelos'),
          ),
          NavigationDrawerDestination(
            icon: const Icon(Icons.chat_bubble_outline),
            selectedIcon: const Icon(Icons.chat_bubble),
            label: const Text('Chat'),
          ),
          const Divider(height: 1, color: Palette.divider),
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 16, 16, 8),
            child: Text('Utilitários',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500,
                    color: cs.onSurface.withAlpha(100))),
          ),
          /* Terminal is opened from the status bar button */
          NavigationDrawerDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: const Text('Configurações'),
          ),
        ],
      ),
      body: _page == 0
          ? _ModelListPage(bridge: bridge, chat: _chatState, term: _termState,
              onChatOpen: () => setState(() => _page = 1))
          : _ChatPage(bridge: bridge, chat: _chatState, term: _termState,
              onBack: () => setState(() => _page = 0)),
    );
  }
}

// ── Dot widget ─────────────────────────────────────────────────────

class _Dot extends StatelessWidget {
  final ServerState state;
  final Color active;
  const _Dot(this.state, this.active);

  @override
  Widget build(BuildContext context) {
    final c = switch (state) {
      ServerState.online => active,
      ServerState.offline => Palette.error,
      ServerState.unknown => Colors.white24,
    };
    return Container(
      width: 8, height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle, color: c,
        boxShadow: state == ServerState.online
            ? [BoxShadow(color: c.withAlpha(80), blurRadius: 4)]
            : null,
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  Model List Page — Edge Gallery style
// ══════════════════════════════════════════════════════════════════

class _ModelListPage extends StatelessWidget {
  final _BridgeState bridge;
  final _ChatState chat;
  final _TerminalState term;
  final VoidCallback onChatOpen;

  const _ModelListPage({
    required this.bridge, required this.chat,
    required this.term, required this.onChatOpen,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final recommended = bridge.profile?.modelId ?? '';
    // Marca modelo recomendado e ativo
    for (final m in kModels) {
      m.recommended = m.id == recommended;
      m.status = m.id == chat.activeModelId
          ? ModelStatus.active
          : m.status == ModelStatus.active
              ? (m.status == ModelStatus.downloaded ? ModelStatus.downloaded : ModelStatus.notDownloaded)
              : m.status;
    }

    final recommendedModels = kModels.where((m) => m.recommended).toList();
    final availableModels = kModels.where((m) => !m.recommended).toList();

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        // Status bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              _LabelDot('LLM', bridge.llmState, Colors.greenAccent),
              const SizedBox(width: 12),
              _LabelDot('Bridge', bridge.bridgeState, Palette.teal),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.terminal, size: 20),
                onPressed: () => showModalBottomSheet(
                  context: context, isScrollControlled: true,
                  backgroundColor: Palette.surface,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
                  builder: (_) => _TerminalSheet(term: term),
                ),
                tooltip: 'Terminal',
                style: IconButton.styleFrom(
                  foregroundColor: cs.onSurface.withAlpha(120),
                  backgroundColor: Palette.card, padding: const EdgeInsets.all(8),
                  minimumSize: const Size(36, 36),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Palette.divider),

        // Recommended section (Edge Gallery: "Recommended models")
        if (recommendedModels.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 16, 8),
            child: Row(
              children: [
                Icon(Icons.star, size: 16, color: Palette.teal),
                const SizedBox(width: 8),
                Text('Recomendados',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                        color: cs.onSurface)),
              ],
            ),
          ),
          ...recommendedModels.map((m) => _ModelCard(
            model: m, bridge: bridge, chat: chat, onChatOpen: onChatOpen,
          )),
        ],

        // Available section
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
          child: Row(
            children: [
              Icon(Icons.cloud_outlined, size: 16, color: cs.onSurface.withAlpha(120)),
              const SizedBox(width: 8),
              Text('Disponíveis',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                      color: cs.onSurface)),
            ],
          ),
        ),
        ...availableModels.map((m) => _ModelCard(
          model: m, bridge: bridge, chat: chat, onChatOpen: onChatOpen,
        )),

        const SizedBox(height: 24),
      ],
    );
  }
}

// ── Model Card ─────────────────────────────────────────────────────

class _ModelCard extends StatelessWidget {
  final LocalModel model;
  final _BridgeState bridge;
  final _ChatState chat;
  final VoidCallback onChatOpen;

  void _rebuild(BuildContext context) {
    (context as Element).markNeedsBuild();
  }

  const _ModelCard({
    required this.model, required this.bridge,
    required this.chat, required this.onChatOpen,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isActive = model.status == ModelStatus.active;
    final isDownloading = model.status == ModelStatus.downloading;
    final isDownloaded = model.status == ModelStatus.downloaded;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: isActive
              ? onChatOpen
              : isDownloaded
                  ? () => _startModel(context)
                  : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.memory, size: 20, color: Palette.teal),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(model.name,
                                  style: TextStyle(fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: cs.onSurface)),
                              const SizedBox(width: 8),
                              if (model.recommended)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Palette.teal.withAlpha(25),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                        color: Palette.teal.withAlpha(50)),
                                  ),
                                  child: Text('Recomendado',
                                      style: TextStyle(fontSize: 9,
                                          color: Palette.teal)),
                                ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text('${model.size} · ${model.task}',
                              style: TextStyle(fontSize: 12,
                                  color: cs.onSurface.withAlpha(100))),
                        ],
                      ),
                    ),
                    // Status icon (Edge Gallery style)
                    if (!isActive)
                      IconButton(
                        onPressed: isDownloading
                            ? null
                            : isDownloaded
                                ? () => _startModel(context)
                                : () => _downloadModel(context),
                        icon: isDownloading
                            ? const SizedBox(
                                width: 20, height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : Icon(_statusIcon(model.status),
                                color: _statusColor(model.status), size: 24),
                        tooltip: _statusLabel(model.status),
                      ),
                    if (isActive)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Palette.accent.withAlpha(25),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.play_circle, size: 14,
                                color: Palette.accent),
                            const SizedBox(width: 4),
                            Text('Ativo',
                                style: TextStyle(fontSize: 11,
                                    color: Palette.accent)),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(model.description,
                    style: TextStyle(fontSize: 12,
                        color: cs.onSurface.withAlpha(150))),
                // Bottom row with action
                if (!isActive && !isDownloaded) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _downloadModel(context),
                      icon: const Icon(Icons.download, size: 16),
                      label: const Text('Baixar modelo'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Palette.teal,
                        side: BorderSide(color: Palette.teal.withAlpha(80)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
                if (isDownloaded && !isActive) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => _startModel(context),
                      icon: const Icon(Icons.play_arrow, size: 16),
                      label: const Text('Iniciar modelo'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Palette.tealDark,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _statusIcon(ModelStatus s) => switch (s) {
    ModelStatus.notDownloaded => Icons.cloud_download_outlined,
    ModelStatus.downloading => Icons.hourglass_top,
    ModelStatus.downloaded => Icons.check_circle,
    ModelStatus.active => Icons.play_circle,
  };

  Color _statusColor(ModelStatus s) => switch (s) {
    ModelStatus.notDownloaded => Colors.white38,
    ModelStatus.downloading => Palette.teal,
    ModelStatus.downloaded => Palette.accent,
    ModelStatus.active => Palette.teal,
  };

  String _statusLabel(ModelStatus s) => switch (s) {
    ModelStatus.notDownloaded => 'Baixar',
    ModelStatus.downloading => 'Baixando...',
    ModelStatus.downloaded => 'Downloaded',
    ModelStatus.active => 'Em uso',
  };

  void _downloadModel(BuildContext context) async {
    model.status = ModelStatus.downloading;
    if (context.mounted) _rebuild(context);

    try {
      await bridge.downloadModel(model.id);
      if (!context.mounted) return;
      model.status = ModelStatus.downloaded;
      if (context.mounted) _rebuild(context);

    } catch (e) {
      model.status = ModelStatus.notDownloaded;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    }
  }

  void _startModel(BuildContext context) async {
    model.status = ModelStatus.downloading;
    if (context.mounted) _rebuild(context);

    try {
      await bridge.startModel('auto');
      model.status = ModelStatus.active;
      chat.activeModelId = model.id;
      if (context.mounted) {
        _rebuild(context);

        onChatOpen();
      }
    } catch (e) {
      model.status = ModelStatus.downloaded;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao iniciar: $e')),
        );
      }
    }
  }
}

// ── Label Dot ──────────────────────────────────────────────────────

class _LabelDot extends StatelessWidget {
  final String label;
  final ServerState state;
  final Color active;
  const _LabelDot(this.label, this.state, this.active);

  @override
  Widget build(BuildContext context) {
    final c = switch (state) {
      ServerState.online => active,
      ServerState.offline => Palette.error,
      ServerState.unknown => Colors.white24,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6, height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle, color: c,
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

// ══════════════════════════════════════════════════════════════════
//  Chat Page
// ══════════════════════════════════════════════════════════════════

class _ChatPage extends StatefulWidget {
  final _BridgeState bridge;
  final _ChatState chat;
  final _TerminalState term;
  final VoidCallback onBack;

  const _ChatPage({
    required this.bridge, required this.chat,
    required this.term, required this.onBack,
  });

  @override
  State<_ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<_ChatPage> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final t = _ctrl.text.trim();
    if (t.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      widget.chat.messages.add(ChatMsg(role: 'user', text: t));
      _ctrl.clear();
    });
    _scrollDown();
    try {
      final r = await widget.bridge.chat(t);
      if (!mounted) return;
      setState(() {
        widget.chat.messages.add(ChatMsg(role: 'assistant', text: r));
        _sending = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        widget.chat.messages.add(ChatMsg(role: 'assistant', text: 'Erro: $e'));
        _sending = false;
      });
    }
    _scrollDown();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isOnline = widget.bridge.llmState == ServerState.online;
    final msgs = widget.chat.messages;

    return Column(
      children: [
        if (!isOnline)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Palette.error.withAlpha(30),
            child: Row(
              children: [
                const Icon(Icons.warning_amber, size: 16, color: Palette.error),
                const SizedBox(width: 8),
                Text('Modelo offline. Selecione um modelo na aba Modelos.',
                    style: TextStyle(fontSize: 12, color: Palette.error)),
              ],
            ),
          ),
        Expanded(
          child: msgs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_awesome, size: 48,
                          color: Palette.teal.withAlpha(80)),
                      const SizedBox(height: 16),
                      Text('Chat com IA local',
                          style: TextStyle(fontSize: 16,
                              color: cs.onSurface.withAlpha(120))),
                      const SizedBox(height: 8),
                      Text('Modelo ativo: ${widget.chat.activeModelId}',
                          style: TextStyle(fontSize: 13,
                              color: cs.onSurface.withAlpha(60))),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  itemCount: msgs.length,
                  itemBuilder: (ctx, i) => _Bubble(msg: msgs[i]),
                ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          decoration: BoxDecoration(
            color: Palette.scaffold,
            border: Border(top: BorderSide(color: Palette.divider)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  enabled: isOnline && !_sending,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: isOnline ? 'Digite um prompt...' : 'Modelo offline',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: isOnline && !_sending ? _send : null,
                icon: _sending
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.arrow_upward),
                style: IconButton.styleFrom(
                  backgroundColor: Palette.teal,
                  foregroundColor: Palette.tealDim,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Chat Bubble (Edge Gallery 24px radius) ─────────────────────────

class _Bubble extends StatelessWidget {
  final ChatMsg msg;
  const _Bubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    final isUser = msg.role == 'user';
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(top: 4, bottom: 4, left: isUser ? 48 : 0, right: isUser ? 0 : 48),
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
                                color: Palette.teal))),
                  SelectableText(msg.text,
                      style: TextStyle(fontSize: 14, height: 1.5,
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

// ══════════════════════════════════════════════════════════════════
//  Terminal Bottom Sheet
// ══════════════════════════════════════════════════════════════════

class _TerminalSheet extends StatelessWidget {
  final _TerminalState term;
  const _TerminalSheet({required this.term});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
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
                  color: Theme.of(context).colorScheme.onSurface)),
          Text('127.0.0.1:8765',
              style: TextStyle(fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurface.withAlpha(80))),
          const Divider(height: 20, color: Palette.divider),
          Expanded(
            child: ListView.builder(
              controller: term.scroll,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: term.lines.length,
              itemBuilder: (ctx, i) => _TermLine(l: term.lines[i]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: term.ctrl,
                    style: const TextStyle(fontSize: 13,
                        fontFamily: 'monospace', color: Palette.teal),
                    decoration: InputDecoration(
                      hintText: 'Comando...',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => term.submit(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: term.submit,
                  icon: const Icon(Icons.send, size: 18),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TermLine extends StatelessWidget {
  final TermLine l;
  const _TermLine({required this.l});

  Color _c() => switch (l.kind) {
    'cmd' => Palette.teal, 'sys' => Colors.white54,
    'err' => Palette.error, _ => Colors.white,
  };

  String _p() => switch (l.kind) {
    'cmd' => '\u25b6 ', 'sys' => '  ', 'err' => '\u2717 ', _ => '  ',
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Text.rich(TextSpan(
        children: [
          TextSpan(text: _p(), style: TextStyle(color: _c(), fontSize: 12)),
          TextSpan(text: l.text, style: TextStyle(
            color: _c().withAlpha(l.kind == 'out' ? 255 : 200),
            fontSize: 12, fontFamily: 'monospace')),
        ],
      )),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  Bridge State (connection lifecycle)
// ══════════════════════════════════════════════════════════════════

class _BridgeState {
  ServerState llmState = ServerState.unknown;
  ServerState bridgeState = ServerState.unknown;
  HardwareProfile? profile;
  bool _terminalReady = false;

  final _client = TermuxClient();
  Timer? _retryTimer;
  int _retries = 0;
  static const _maxR = 25;
  static const _delay = Duration(seconds: 3);
  _TerminalState? _term;

  void start(_ChatState chat, _TerminalState term) {
    _term = term;
    _retries = 0;
    _tryConnect();
    Timer.periodic(const Duration(seconds: 1), (_) {
      if (bridgeState == ServerState.online) _pollTerm();
    });
  }

  void dispose() {
    _retryTimer?.cancel();
  }

  void _tryConnect() {
    if (_retries >= _maxR) { _retryTimer?.cancel(); return; }
    _retries++;
    unawaited(_doConnect());
  }

  Future<void> _doConnect() async {
    try {
      if (await _client.health()) {
        _retryTimer?.cancel();
        bridgeState = ServerState.online;
        await _client.startSession();
        _terminalReady = true;
        _term?.add(TermLine('sys', '\u2713 Bridge conectado'));
        await _loadProfile();
        return;
      }
    } catch (_) {}
    _retryTimer?.cancel();
    _retryTimer = Timer(_delay, _tryConnect);
  }

  Future<void> _loadProfile() async {
    try {
      profile = await _client.getProfile();
      _term?.add(TermLine('sys', 'Modelo: ${profile!.modelId} (${profile!.profile})'));
    } catch (e) {
      _term?.add(TermLine('err', 'Erro hardware: $e'));
    }
  }

  Future<void> downloadModel(String id) async {
    await _client.download(id);
  }

  Future<void> startModel(String profile) async {
    if (!_terminalReady) {
      await _client.startSession();
      _terminalReady = true;
    }
    await _client.startLlm(profile);
    llmState = ServerState.online;
  }

  Future<String> chat(String prompt) async {
    return _client.chat(prompt);
  }

  Future<void> _pollTerm() async {
    try {
      final r = await _client.events();
      if (r.isEmpty) return;
      for (final e in r) {
        _term?.add(e);
      }
    } catch (_) {
      bridgeState = ServerState.offline;
    }
  }
}

// ── Shared state classes ───────────────────────────────────────────

class _ChatState {
  String activeModelId = '';
  final messages = <ChatMsg>[];
}

class _TerminalState {
  final ctrl = TextEditingController();
  final scroll = ScrollController();
  final lines = <TermLine>[];

  void add(TermLine l) => lines.add(l);

  void submit() {
    final c = ctrl.text.trim();
    if (c.isEmpty) return;
    add(TermLine('cmd', c));
    ctrl.clear();
    // Command is sent through bridge
  }
}

class ChatMsg {
  final String role, text;
  ChatMsg({required this.role, required this.text});
}

class TermLine {
  final String kind, text;
  TermLine(this.kind, this.text);
}

// ══════════════════════════════════════════════════════════════════
//  HTTP Clients
// ══════════════════════════════════════════════════════════════════

class TermuxClient {
  static final _http = HttpClient();

  Future<bool> health() async {
    try {
      final r = await _http.getUrl(Uri.parse('http://127.0.0.1:8765/health'))
          .timeout(const Duration(seconds: 2));
      return (await r.close()).statusCode == 200;
    } catch (_) { return false; }
  }

  Future<HardwareProfile> getProfile() async {
    final b = await _get('/hardware');
    return HardwareProfile.fromJson(jsonDecode(b) as Map<String, dynamic>);
  }

  Future<void> startSession() => _post('/terminal/session', {});
  Future<void> sendInput(String d) => _post('/terminal/input', {'data': d});
  Future<void> download(String m) => _post('/models/download', {'model': m});
  Future<void> startLlm(String p) => _post('/llm/start', {'profile': p});

  Future<List<TermLine>> events() async {
    final b = await _get('/terminal/events');
    final d = jsonDecode(b) as Map<String, dynamic>;
    return (d['events'] as List).map((e) {
      final m = e as Map;
      final kind = m['kind']?.toString() ?? 'out';
      return TermLine(
        kind == 'error' ? 'err' : kind == 'system' ? 'sys' : kind == 'stdout' ? 'out' : 'out',
        m['text']?.toString() ?? '',
      );
    }).toList();
  }

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
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}');
    }
    final d = jsonDecode(body) as Map<String, dynamic>;
    return (d['choices'] as List?)?.firstOrNull?['message']?['content']?.toString() ?? '';
  }

  Future<String> _get(String path) async {
    try {
      final r = await _http.getUrl(Uri.parse('http://127.0.0.1:8765$path'))
          .timeout(const Duration(seconds: 2));
      final res = await r.close().timeout(const Duration(seconds: 3));
      return await utf8.decodeStream(res);
    } on TimeoutException { throw Exception('Timeout bridge'); }
    on SocketException { throw Exception('Bridge offline'); }
  }

  Future<void> _post(String path, Map<String, Object?> body) async {
    try {
      final r = await _http.postUrl(Uri.parse('http://127.0.0.1:8765$path'))
          .timeout(const Duration(seconds: 2));
      r.headers.contentType = ContentType.json;
      r.write(jsonEncode(body));
      final res = await r.close().timeout(const Duration(seconds: 3));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('HTTP ${res.statusCode}');
      }
    } on TimeoutException { throw Exception('Timeout bridge'); }
    on SocketException { throw Exception('Bridge offline'); }
  }
}

class HardwareProfile {
  final String profile, modelId, modelPath;
  final int context, ngl;
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
