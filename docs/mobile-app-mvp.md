# Droid Harness Mobile MVP

## Goal

Build an Android app that turns Droid Harness into a phone-native workstation:
one screen for terminal control, one screen for local AI, and one stable bridge
to the existing Termux + proot + llama.cpp stack.

## Architecture

```
Flutter app
  |-- LocalLlmClient -> http://127.0.0.1:8080/v1/chat/completions
  |-- Terminal UI    -> native bridge, next milestone
  |-- Quick commands -> Termux/proot/llama.cpp command presets

Termux
  |-- llama-server on 127.0.0.1:8080
  |-- proot-distro Ubuntu
  |-- Codex, Aider, OpenCode, OpenClaude, Claude Code
```

## MVP included now

- Flutter app scaffold in `mobile/`
- dark phone-first UI with responsive desktop/tablet split view
- local model health check against `/v1/models`
- prompt submission to `/v1/chat/completions`
- command staging panel for common Droid Harness commands
- Android `INTERNET` permission for localhost HTTP access
- Termux HTTP bridge in `scripts/termux-bridge.py`
- PTY-backed terminal session controlled from the Flutter app

## Terminal execution path

Android apps cannot freely control another app's shell process. Droid Harness
uses a Termux-side bridge service because the project already depends on Termux,
proot-distro, and llama.cpp.

Start it inside Termux:

```bash
scripts/start-termux-bridge.sh
```

The bridge exposes:

- `GET /health`
- `POST /terminal/session`
- `POST /terminal/input`
- `GET /terminal/events?after=<id>`
- `POST /terminal/stop`
- `POST /llm/start`

## Next implementation milestone

Hardening items before publishing:

- add bridge token authentication
- add autostart instructions for Termux:Boot
- add model profile picker in the app
- add ANSI escape rendering instead of plain text output
- add a foreground notification/status channel for long sessions
