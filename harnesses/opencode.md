# OpenCode on Android (Termux)

Setup guide for [OpenCode](https://github.com/sst/opencode) — open-source Go coding agent by SST — via Termux + proot-distro Ubuntu.

## Prerequisites

- **Termux** (F-Droid recommended)
- `pkg install proot-distro`
- `proot-distro install ubuntu`

## Step 1 — Enter Ubuntu

```bash
proot-distro login ubuntu
```

All commands below run **inside** the Ubuntu proot.

## Step 2 — Install Go & OpenCode

```bash
apt update && apt install -y golang-go
go install github.com/sst/opencode@latest
```

Add to PATH:
```bash
echo 'export PATH=$HOME/go/bin:$PATH' >> ~/.bashrc && source ~/.bashrc
```

Verify: `opencode --help`

## Step 3 — Provider config

Set one of these (persist in `~/.bashrc`):

**Anthropic (Claude)** — recommended:
```bash
export ANTHROPIC_API_KEY="sk-ant-..."
```

**OpenAI**:
```bash
export OPENAI_API_KEY="sk-proj-..."
```

**Ollama** (local):
```bash
export OPENAI_API_KEY="ollama"
export OPENAI_BASE_URL="http://<device-lan-ip>:11434/v1"
```

## Step 4 — Usage

Inside any Git repo:
```bash
cd ~/my-project
opencode
```

Describe a task:
```
> Add a REST endpoint to list all users
```

OpenCode reads your codebase, plans, writes code. Review and confirm each step.

### Flags

- `--model` — override (e.g. `--model claude-sonnet-4-20250514`)
- `--provider` — force a specific provider

## Tips

- Use **termux-wake-lock** to prevent the process from being killed
- `termux-setup-storage` for /sdcard access
- Anthropic/OpenAI keys unlock Pro features; Ollama covers basic edits
