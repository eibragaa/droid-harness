# Droid Harness Mobile

<p align="center">
  <em>Companion app para o Droid Harness — estilo Google AI Edge Gallery.</em>
</p>

<p align="center">
  <strong>Material 3 dark · IA local on-device · Bridge Termux</strong>
</p>

---

## Visão geral

O app Droid Harness Mobile é a interface nativa Android para a stack
Droid Harness de IA local. Inspirado no design do **Google AI Edge Gallery**,
ele oferece:

- **Chat com IA local** via llama-server em `127.0.0.1:8080`
- **Model Manager** para baixar e gerenciar modelos GGUF
- **Terminal remoto** via bridge Termux em `127.0.0.1:8765`
- **Detecção de hardware** com perfil automático (weak/balanced/strong)
- **Integração com Android**: FileProvider, share intents, deep links, foreground service

## Arquitetura

```
┌─────────────────────────────────────────────┐
│           Droid Harness App                  │
├─────────────────────────────────────────────┤
│  Flutter UI (Material 3 Dark, teal accent)   │
│  └── _ChatTab     — chat com modelo local    │
│  └── _ModelTab    — gerenciamento de modelo  │
│  └── Terminal     — bottom sheet modal       │
├─────────────────────────────────────────────┤
│  TermuxBridgeClient (HTTP REST)              │
│  └── GET  /health                            │
│  └── GET  /hardware                          │
│  └── POST /terminal/session                  │
│  └── POST /terminal/input                    │
│  └── GET  /terminal/events                   │
│  └── POST /models/download                   │
│  └── POST /llm/start                         │
├─────────────────────────────────────────────┤
│  Android Native (Kotlin)                     │
│  └── MainActivity — MethodChannel + intents  │
│  └── BridgeForegroundService — notificação   │
│  └── BootReceiver — auto-start no reboot     │
│  └── FileProvider — compartilhar arquivos    │
├─────────────────────────────────────────────┤
│  Termux (externo)                            │
│  └── termux-bridge.py (HTTP server)          │
│  └── llama.cpp (shell command)               │
│  └── Modelos GGUF via download-models.sh     │
└─────────────────────────────────────────────┘
```

## Design System (Google AI Edge Gallery)

| Token | Valor | Uso |
|---|---|---|
| `seed` | `#80cbc4` | Cor primária teal/cyan |
| `primary` | `#80cbc4` | Botões, links, ícones ativos |
| `tealDark` | `#008577` | Botão "Baixar + Iniciar" |
| `surface` | `#1a1c1e` | NavigationBar, bottom sheet |
| `card` | `#1e2024` | Cards, input background |
| `scaffold` | `#0f1114` | Fundo principal |
| `redAccent` | `#ff7043` | Erros, offline |
| `chatRadius` | `24px` | Bolhas de chat (Edge Gallery style) |

## Funcionalidades Android implementadas

### FileProvider
Compartilha arquivos via `content://` URIs com outros apps.
Caminhos mapeados em `res/xml/file_paths.xml`:
- `cache/` — arquivos temporários
- `files/` — arquivos internos
- `Download/` — downloads externos

### Share Intents
- `ACTION_SEND` com `image/*` — receber fotos da Gallery
- `ACTION_SEND` com `text/plain` — receber texto do navegador
- `ACTION_VIEW` com `droid-harness://` — deep links

### Foreground Service
`BridgeForegroundService` mantém o processo vivo em background
com notificação persistente "Droid Harness — Bridge AI ativo".

### Boot Receiver
`BootReceiver` inicia o foreground service automaticamente
quando o dispositivo é ligado (BOOT_COMPLETED).

### Deep Links
- `droid-harness://` — URI scheme customizado
- `https://droidharness.dev` — web link

## Como executar

### 1. Iniciar o bridge no Termux

```bash
cd ~/droid-harness
bash scripts/start-termux-bridge.sh
```

### 2. Build do app

```bash
cd mobile
flutter build apk --release
```

O APK será gerado em `build/app/outputs/flutter-apk/app-release.apk`.

### 3. Instalar no dispositivo

Via Taildrop:
```bash
tailscale file cp build/app/outputs/flutter-apk/app-release.apk s25-ultra-braga:
```

Ou por ADB:
```bash
adb install build/app/outputs/flutter-apk/app-release.apk
```

## Telas

### Chat (Tab 1)
- Barra de status com dots (LLM + Bridge)
- Model chip no AppBar
- Lista de mensagens com bolhas 24px radius
- Input arredondado com teal send button
- Botão "Baixar + Iniciar" quando hardware detectado
- Terminal acessível pelo ícone `>_`

### Modelo (Tab 2)
- Card "Modelo Local" com nome, perfil, contexto, ngl
- Card "Bridge Termux" com status e instruções
- Botão de ação principal

## Bridge API

Documentação completa em `scripts/termux-bridge.py`.

| Método | Endpoint | Descrição |
|---|---|---|
| `GET` | `/health` | Status do bridge + hardware |
| `GET` | `/hardware` | Perfil de hardware detalhado |
| `POST` | `/terminal/session` | Iniciar sessão PTY |
| `POST` | `/terminal/input` | Enviar comando |
| `GET` | `/terminal/events?after=N` | Poll de eventos |
| `POST` | `/terminal/stop` | Parar sessão |
| `POST` | `/llm/start` | Iniciar llama-server |
| `POST` | `/models/download` | Baixar modelo GGUF |

## Version History

| Versão | Data | Mudanças |
|---|---|---|
| 1.3.0 | 2026-05-12 | Design Edge Gallery, fix terminal session, MethodChannel, FileProvider |
| 1.0.0 | 2026-05-12 | MVP: chat, terminal bridge, hardware detection, model download/start |
