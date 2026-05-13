# Droid Harness Mobile — Arquitetura

## Visão Geral

App Android nativo (Flutter) que transforma o Droid Harness em uma
workstation de IA local portátil. Design inspirado no Google AI Edge Gallery.

## Arquitetura

```
┌─────────────────────────────────────────────────┐
│              Droid Harness App                    │
├─────────────────────────────────────────────────┤
│  Flutter (Material 3 Dark)                       │
│  └── _HarnessHomePageState (state principal)      │
│      ├── _ChatTab      → chat com modelo local    │
│      ├── _ModelTab     → gerenciamento de modelo  │
│      └── Terminal      → bottom sheet modal       │
│  └── TermuxBridgeClient → HTTP bridge client      │
│  └── LocalLlmClient    → HTTP llama-server client │
│  └── MethodChannel     → comunicação Kotlin       │
├─────────────────────────────────────────────────┤
│  Android Native (Kotlin)                         │
│  └── MainActivity                                │
│      ├── MethodChannel (dev.droidharness/bridge) │
│      ├── FileProvider (content:// URIs)          │
│      └── Intent handling (SEND, VIEW)            │
│  └── BridgeForegroundService (notificação bg)    │
│  └── BootReceiver (auto-start no reboot)         │
├─────────────────────────────────────────────────┤
│  Termux (app Android externo)                    │
│  └── termux-bridge.py → HTTP server :8765        │
│      ├── PTY-backed terminal session             │
│      ├── llama-server control (start/stop)       │
│      └── Hardware detection + model download     │
│  └── llama.cpp → HTTP server :8080               │
│      └── OpenAI-compatible /v1/chat/completions  │
│  └── proot-distro Ubuntu + coding harnesses      │
└─────────────────────────────────────────────────┘
```

## Fluxo de inicialização

```
App inicia
  │
  ├─ initState()
  │   ├─ MethodChannel.setMethodCallHandler
  │   ├─ _checkInitialIntent()         ← verifica deep link/share inicial
  │   ├─ _checkLlm()                   ← testa :8080/v1/models
  │   └─ _startRetry()                 ← tenta conectar bridge :8765
  │       └─ healthCheck() → falha? → Timer 3s → retry (max 25x)
  │
  ├─ Bridge conecta
  │   ├─ POST /terminal/session        ← cria PTY session
  │   ├─ GET /hardware                 ← detecta CPU/RAM/GPU
  │   └─ UI mostra "Baixar + Iniciar"
  │
  └─ Usuário toca "Baixar + Iniciar"
      ├─ POST /models/download recommended  ← wget do GGUF (timeout 10min)
      ├─ POST /llm/start auto               ← inicia llama-server
      └─ LLM online → chat habilitado
```

## Bridge API

Implementado em `scripts/termux-bridge.py`.

| Método | Rota | Descrição |
|--------|------|-----------|
| GET | `/health` | Status + hardware |
| GET | `/hardware` | Perfil detalhado |
| POST | `/terminal/session` | Cria PTY session |
| POST | `/terminal/input` | Envia comando |
| GET | `/terminal/events?after=N` | Poll de stdout/stderr |
| POST | `/terminal/stop` | Para sessão |
| POST | `/llm/start` | Inicia llama-server |
| POST | `/models/download` | Baixa modelo GGUF |

## Design System

Paleta extraída do Google AI Edge Gallery (`res/values/colors.xml`):

```dart
class AppColors {
  static const scaffold  = Color(0xff0f1114);
  static const surface   = Color(0xff1a1c1e);
  static const card      = Color(0xff1e2024);
  static const teal      = Color(0xff80cbc4);   // seed
  static const tealDark  = Color(0xff008577);   // button
  static const tealText  = Color(0xff00332e);
  static const redAccent = Color(0xffff7043);
  static const divider   = Color(0xff2c2e30);
}
```

- Material 3 Dark
- NavigationBar inferior (Chat + Modelo)
- Chat bubbles com 24px radius (assimétricos)
- Status dots com glow (online/offline)
- Bottom sheet para terminal

## Integrações Android

### FileProvider (`res/xml/file_paths.xml`)
```xml
<cache-path name="cache" path="." />
<files-path name="internal" path="." />
<external-path name="downloads" path="Download/" />
```

### Intent Filters (AndroidManifest.xml)
- `ACTION_SEND image/*` — receber imagens da Gallery
- `ACTION_SEND text/plain` — receber texto
- `ACTION_VIEW droid-harness://` — deep links

### MethodChannel (`dev.droidharness/bridge`)
- `startBridgeService` / `stopBridgeService`
- `getInitialIntent` — intent que abriu o app

### Permissões
- `INTERNET`, `ACCESS_NETWORK_STATE`
- `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_DATA_SYNC`
- `POST_NOTIFICATIONS` (Android 13+)
- `RECEIVE_BOOT_COMPLETED`
- `WAKE_LOCK`

## Estado atual

v1.3.0 — 2026-05-12

- ✅ Design Google AI Edge Gallery
- ✅ Bridge automático com retry (25x)
- ✅ Foreground service + Boot receiver
- ✅ FileProvider + Share Intents
- ✅ Deep links
- ✅ Model Manager (download + start)
- ✅ Chat com modelo local
- ✅ Terminal bottom sheet

## Próximos passos

- [ ] ANSI escape rendering no terminal
- [ ] Settings screen (bridge config, modelo padrão)
- [ ] Bridge token auth
- [ ] Keystore release (assinatura)
- [ ] Split APKs por ABI
- [ ] CI/CD com GitHub Actions
- [ ] Publicação F-Droid / GitHub Releases
