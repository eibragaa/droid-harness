# Pi-agent-code on Android (Termux + proot-distro)

Setup guide for running [Pi-agent-code](https://github.com/mariozechner/pi-coding-agent) (`@mariozechner/pi-coding-agent`) on Android.

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

## 2. Install Pi-agent-code

```bash
npm install -g @mariozechner/pi-coding-agent
pi --version
```

## 3. Set Your API Key

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
echo 'export ANTHROPIC_API_KEY="sk-ant-..."' >> ~/.bashrc && source ~/.bashrc
```

Get your key at https://console.anthropic.com/settings/keys

## 4. Network Hijack Fix (proot DNS issue)

proot-distro's virtual network stack can cause DNS/hijack errors with Node.js HTTP agents. Fix by disabling the Node.js agent reuse:

```bash
export NODE_OPTIONS="--dns-result-order=verbatim"
echo 'export NODE_OPTIONS="--dns-result-order=verbatim"' >> ~/.bashrc && source ~/.bashrc
```

If you still see `ERR_NETWORK` or `fetch failed` errors, also set:

```bash
export NODE_OPTIONS="$NODE_OPTIONS --use-openssl-ca"
```

## 5. Basic Usage

```bash
pi                              # Interactive REPL session
pi -p "You are a Linux expert"  # With system prompt
cat main.go | pi                # Pipe code for review
pi "Refactor this Python script"  # Direct query
cd ~/project && pi              # Project-aware session
```

Useful flags: `-p` (system prompt), `-m` (model override), `--no-stream` (non-streaming), `--resume` (resume session).

## 6. Tips

- **RAM**: 4 GB+ free recommended. Close other apps.
- **Storage**: Ubuntu root + Node modules ~1–2 GB.
- **Internet**: API calls need active connection.
- **proot**: Slightly slower than native, acceptable for CLI use.
- **Exit proot**: `exit` or Ctrl+D to return to Termux.
- **Update**: `npm update -g @mariozechner/pi-coding-agent`
