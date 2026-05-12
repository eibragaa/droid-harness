# Aider on Android (Termux + proot-distro)

Setup guide for [Aider](https://aider.chat/) (`pip install aider-chat`), git-aware AI pair programmer.

---

**Prerequisites:** Termux from F-Droid.

## 1. Bootstrap

```bash
pkg update && pkg upgrade -y
pkg install proot-distro -y
proot-distro install ubuntu
proot-distro login ubuntu
```

Inside Ubuntu:

```bash
apt update && apt upgrade -y
apt install python3 python3-pip git -y
```

## 2. Install & Authenticate

```bash
pip install aider-chat
aider --version

# Anthropic (recommended) or OpenAI
export ANTHROPIC_API_KEY="sk-ant-..."
echo 'export ANTHROPIC_API_KEY="sk-ant-..."' >> ~/.bashrc
# export OPENAI_API_KEY="sk-proj-..."
source ~/.bashrc
```

Get key at https://console.anthropic.com or https://platform.openai.com

## 3. Basic Usage

```bash
aider                                    # Interactive mode
aider --model claude-3-5-haiku-latest   # Fast/cheap
aider --model gpt-4o                    # OpenAI
aider --model claude-3-opus-latest      # Most capable
mkdir project && cd project && git init && aider  # Fresh project
```

## 4. Local llama.cpp (Fully Offline)

**Session 1** — start the llama.cpp server:

```bash
git clone https://github.com/ggerganov/llama.cpp && cd llama.cpp
make -j$(nproc) llama-server
wget -O models/qwen2.5-coder-1.5b-q4_k_m.gguf \
  https://huggingface.co/Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF/resolve/main/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf
./llama-server -m models/qwen2.5-coder-1.5b-q4_k_m.gguf \
  --host 127.0.0.1 --port 8080 -ngl 99
```

**Session 2** — use Aider with the local model:

```bash
aider --model ollama/qwen2.5-coder:1.5b \
  --ollama-server http://127.0.0.1:8080
```

Larger: `Qwen2.5-Coder-7B-Q4_K_M` (~4.5 GB) on 8 GB+ devices.

## Notes

- **RAM**: 4 GB+ minimum (8 GB+ for local models > 3B).
- **Storage**: ~1 GB base; + ~2 GB per GGUF model.
- **Auto-commits**: `--no-git` to disable.
- **Exit**: `exit` or Ctrl+D.
