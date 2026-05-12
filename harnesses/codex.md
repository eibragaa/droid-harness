# Codex CLI — Android Setup Guide (Termux + proot-distro)

Install and run OpenAI Codex CLI on Android via Termux with a proot-distro
Ubuntu chroot.

## Prerequisites

- **Termux** (F-Droid version; Play Store builds outdated)
- At least 4 GB free storage (1 GB for Ubuntu + deps)
- An **OpenAI API key** with Codex model access

## Step 1 — Install proot-distro Ubuntu

```bash
pkg update && pkg upgrade -y
pkg install proot-distro -y
proot-distro install ubuntu
proot-distro login ubuntu
```

## Step 2 — Install Python + pip

```bash
apt update && apt upgrade -y
apt install python3 python3-pip python3-venv git -y
python3 --version   # should be 3.10+
```

## Step 3 — Install Codex CLI

```bash
pip3 install codex-cli
codex --help
```

If `codex` isn't found, use `~/.local/bin/codex` or add `~/.local/bin` to `PATH`.

## Step 4 — Set your OpenAI API key

```bash
export OPENAI_API_KEY="sk-your-key-here"
echo 'export OPENAI_API_KEY="sk-your-key-here"' >> ~/.bashrc
```

Or create a `.env` file with `OPENAI_API_KEY=sk-your-key-here`.

## Step 5 — Authenticate (optional)

```bash
codex auth login
```

Follow the URL that opens in Termux's browser or CLI.

## Step 6 — Basic usage

| What | Command |
|---|---|
| Interactive session | `codex` |
| One-shot prompt | `codex "write a Python function to fetch JSON"` |
| With file context | `codex --file script.py "add error handling"` |
| Git repo context | `codex --repo /path "summarize changes"` |

## Troubleshooting

- **`pip` not found** → re-run `apt install python3-pip`
- **`codex` not found** → use `~/.local/bin/codex` or fix `PATH`
- **Network errors** → proot uses host networking; check wifi/data
- **Exit proot** → type `exit` or press Ctrl+D

## Links

- [Codex CLI GitHub](https://github.com/openai/codex)
- `codex --help` for all flags (`--model`, `--temperature`, `--max-tokens`)