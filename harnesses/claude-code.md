# Claude Code on Android (Termux + proot-distro)

Setup guide for running [Claude Code](https://github.com/anthropics/claude-code) (`@anthropic-ai/claude-code`) on Android.

---

**Prerequisites:** Termux from F-Droid (not Play Store). Termux:API optional.

## 1. Bootstrap the Environment

```bash
pkg update && pkg upgrade -y
pkg install proot-distro -y
proot-distro install ubuntu
proot-distro login ubuntu
```

Inside Ubuntu proot:

```bash
apt update && apt upgrade -y
apt install curl git build-essential python3 -y
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install nodejs -y
```

## 2. Install Claude Code

```bash
npm install -g @anthropic-ai/claude-code
claude --version
```

## 3. Set Your API Key

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
echo 'export ANTHROPIC_API_KEY="sk-ant-..."' >> ~/.bashrc && source ~/.bashrc
```

Get your key at https://console.anthropic.com/settings/keys

## 4. Basic Usage

```bash
claude                           # Interactive REPL
claude -p "You are an expert."    # With system prompt
echo "Explain pointers" | claude  # Pipe input
cd ~/project && claude            # In a project dir
```

Useful flags: `-p` (system prompt), `--model` (override model), `--print` (non-interactive), `--resume` (resume session).

## 5. Tip: Pair with Local llama.cpp

Run a local LLM alongside Claude Code for sensitive/offline work. In a separate Termux session (also inside proot-distro ubuntu):

```bash
git clone https://github.com/ggerganov/llama.cpp && cd llama.cpp
make -j$(nproc)
./llama-server -m models/llama-3.2-3b-instruct-q4_k_m.gguf --host 127.0.0.1 --port 8080
```

## Notes

- **RAM**: 6 GB+ free recommended. Close other apps.
- **Storage**: Ubuntu root + Node modules ~1–2 GB.
- **Internet**: API calls need active connection (unless using local llama.cpp).
- **proot**: Slightly slower than native, acceptable for CLI.
- **Exit proot**: `exit` or Ctrl+D to return to Termux.
