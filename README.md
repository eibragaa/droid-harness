# 📱 Droid Harness

<p align="center">
  <img src="screenshots/dashboard-preview.jpeg" width="45%" />
  <img src="screenshots/termux-setup.jpeg" width="45%" />
</p>

<p align="center">
  <strong>Turn your Android smartphone into a portable AI coding workstation.</strong>
</p>

<p align="center">
  Run Claude Code, Codex, OpenCode, Aider, OpenClaude, Pi-agent-code,<br>
  and local LLMs via llama.cpp — <em>all on-device, zero cloud dependency.</em>
</p>

---

## What You're Building

By the end of this guide, your Android phone will:

- Run **any AI coding harness** directly on the device
- Serve as a **24/7 portable AI agent** — no PC, no cloud VM
- Support **local LLM inference** via llama.cpp (Snapdragon GPU-accelerated)
- Be controllable via **web dashboards** and **CLI**
- Operate completely offline (local models) or hybrid (API + local)

### Mobile Companion App

This repo now includes a Flutter companion app in [`mobile/`](mobile/). It
gives the Droid Harness stack a phone-native control surface for local AI
prompts, `llama-server` health checks, and terminal command presets. The app
talks to the Termux bridge on `127.0.0.1:8765` and the local model server on
`127.0.0.1:8080`. See [`docs/mobile-app-mvp.md`](docs/mobile-app-mvp.md) for
the app architecture and the bridge contract. The current implementation/status
log is in [`docs/status-2026-05-12.md`](docs/status-2026-05-12.md).

---

## Device Requirements

| Component | Minimum | Recommended |
|---|---|---|
| Android | 10+ | 12+ |
| RAM | 6 GB | 8+ GB |
| SoC | Snapdragon 865 | Snapdragon 8 Gen 1+ |
| Storage | 8 GB free | 32+ GB free |
| Termux | F-Droid only | F-Droid latest |

> **Snapdragon optimization**: Qualcomm's Adreno GPU and Hexagon DSP provide significant acceleration for llama.cpp inference via Vulkan and QNN backends. Devices with Snapdragon 8 series are ideal.

---

## Phase 1: Base Environment

### 1. Install Termux

> ⚠️ **IMPORTANT**: Install Termux ONLY from F-Droid. The Play Store version is outdated and won't work.

1. Go to **[F-Droid.org](https://f-droid.org)** and install F-Droid
2. Search for **Termux** inside F-Droid
3. Install the latest version
4. Open the Termux app

### 2. Update & Install Dependencies

```bash
pkg update && pkg upgrade -y
pkg install -y proot-distro git curl wget python nodejs-lts \
               build-essential cmake ninja vulkan-tools \
               openssh termux-api
```

> `termux-api` enables battery optimization bypass, wake locks, and camera/sensor access from scripts.

### 3. Install Ubuntu via proot-distro

```bash
proot-distro install ubuntu
```

### 4. Login to Ubuntu

```bash
proot-distro login ubuntu
```

### 5. Update Ubuntu & Install Core Tools

```bash
apt update && apt upgrade -y
apt install -y curl wget git python3 python3-pip python3-venv \
               build-essential cmake pkg-config libssl-dev \
               nodejs npm
```

> You're now inside a full Ubuntu environment on your phone. This is where all harnesses will run.

---

## Phase 2: Fix Android Network Interface

Some Node.js-based harnesses (OpenClaude, Pi-agent-code) scan network interfaces and crash on Android because Termux's virtual network layer doesn't expose standard interfaces.

Create the fix:

```bash
cat <<'EOF' > /root/hijack.js
const os = require('os');
os.networkInterfaces = () => ({});

// Also mock the DNS resolution to avoid EAI_AGAIN errors
const dns = require('dns');
const origLookup = dns.lookup;
dns.lookup = (hostname, options, callback) => {
  if (typeof options === 'function') {
    callback = options;
    options = {};
  }
  // Force IPv4 loopback for local services
  if (hostname === 'localhost' || hostname === '127.0.0.1') {
    return callback(null, '127.0.0.1', 4);
  }
  return origLookup(hostname, options, callback);
};
EOF

echo 'export NODE_OPTIONS="-r /root/hijack.js"' >> ~/.bashrc
source ~/.bashrc
```

---

## Phase 3: Choose Your Harness

Each harness is a different AI coding agent. Pick the one that fits your workflow:

| Harness | Language | Approach | Best For |
|---|---|---|---|
| [OpenClaude](#openclaude) | Node.js | Multi-provider agent | Research, general tasks |
| [Claude Code](#claude-code) | npm | Anthropic CLI agent | Full-stack development |
| [Codex CLI](#codex-cli) | Python | OpenAI coding agent | OpenAI ecosystem |
| [OpenCode](#opencode) | Go | Open-source CLI | Lightweight, fast |
| [Aider](#aider) | Python | Git-aware pair programmer | Refactoring, repos |
| [Pi-agent-code](#pi-agent-code) | Node.js | Task-driven agent | Automation |

You can install **multiple** harnesses — they don't conflict.

---

### OpenClaude

Multi-provider AI agent with web dashboard and gateway.

```bash
npm install -g openclaude@latest
openclaude --version
```

**Setup wizard:**
```bash
openclaude onboard
```
When prompted for **Gateway Bind**, select: `127.0.0.1 (Loopback)`

**Launch:**
```bash
openclaude gateway --verbose
```

**Dashboard:** Open `http://127.0.0.1:18789` in your mobile browser.

**Get gateway token:**
```bash
cat ~/.openclaude/openclaude.json
openclaude config get gateway.auth.token
```

---

### Claude Code

Anthropic's official CLI coding agent.

```bash
npm install -g @anthropic-ai/claude-code
```

**Verify:**
```bash
claude --version
```

**Usage:**
```bash
claude
```

Claude Code requires an Anthropic API key. Set it:
```bash
export ANTHROPIC_API_KEY="sk-ant-..."
```
Or add to `~/.bashrc` for persistence.

**Snapdragon tip:** Claude Code itself runs via API, but you can pair it with llama.cpp (see [Phase 5](#phase-5-portable-llamacpp-for-snapdragon)) for smaller offline tasks via a local proxy.

---

### Codex CLI

OpenAI's agentic CLI for code generation and task execution.

```bash
pip install codex-cli
```

**Verify:**
```bash
codex --version
```

**Authenticate:**
```bash
export OPENAI_API_KEY="sk-..."
codex auth
```

**Usage:**
```bash
codex "build a fastapi endpoint for user auth"
```

> Codex runs tasks in an isolated sandbox — ideal for safe experimentation on mobile.

---

### OpenCode

Fast, open-source coding agent written in Go.

```bash
# Install Go first
pkg install golang

# Install OpenCode
go install github.com/sst/opencode@latest
```

**Verify:**
```bash
opencode --version
```

**Providers:**
OpenCode supports Anthropic, OpenAI, and Ollama:
```bash
export ANTHROPIC_API_KEY="sk-ant-..."
# or
export OPENAI_API_KEY="sk-..."
```

**Usage:**
```bash
opencode
```

> OpenCode is extremely lightweight — perfect for lower-spec devices.

---

### Aider

Git-aware AI pair programming in the terminal. Works with any LLM.

```bash
pip install aider-chat
```

**Verify:**
```bash
aider --version
```

**Quick start:**
```bash
# With OpenAI
export OPENAI_API_KEY="sk-..."
aider

# With local llama.cpp
aider --model ollama/qwen2.5-coder:7b

# With Claude
export ANTHROPIC_API_KEY="sk-ant-..."
aider --model claude-sonnet-4-20250514
```

**Why Aider on mobile:** Aider automatically commits every change, so you can experiment freely. It also has the best local model integration of any harness.

**Pro tip:** Run `aider --lint` for real-time syntax checking during edits.

---

### Pi-agent-code

Lightweight task-driven coding agent.

```bash
npm install -g @mariozechner/pi-coding-agent
```

**Verify:**
```bash
pi-agent --version
```

**Usage:**
```bash
pi-agent "create a react component for a file uploader"
```

Requires an API key (Anthropic or OpenAI):
```bash
export ANTHROPIC_API_KEY="sk-ant-..."
```

---

## Phase 4: Persistent Operation

### Prevent Termux from Sleeping

```bash
termux-wake-lock
```

### Disable Battery Optimization

1. Android **Settings → Apps → Termux**
2. Tap **Battery**
3. Select **Unrestricted** (or disable optimization)

### Keep Device Plugged In

For true 24/7 operation, keep the phone connected to power. Consider:
- A dedicated charging dock
- USB-C to Ethernet adapter for stable networking
- External SSD for model storage (Snapdragon USB 3.x supports it)

### Auto-Start Termux on Boot

Install **Termux:Boot** from F-Droid, then:

```bash
mkdir -p ~/.termux/boot/
cat <<'EOF' > ~/.termux/boot/start-harness.sh
#!/data/data/com.termux/files/usr/bin/sh
termux-wake-lock
proot-distro login ubuntu -- bash -c "
  source ~/.bashrc
  cd ~
  # Start your harness here
  echo 'Droid Harness ready'
"
EOF
chmod +x ~/.termux/boot/start-harness.sh
```

---

## Phase 5: Portable llama.cpp for Snapdragon

Run local LLMs directly on your phone's Snapdragon processor — no internet required.

### Option A: Pre-built (Recommended)

```bash
# In Termux (not Ubuntu)
pkg install -y llama.cpp
```

This installs a pre-compiled ARM64 binary with Vulkan support.

### Option B: Build from Source (Optimized)

For maximum Snapdragon optimization, build with Vulkan:

```bash
# In Termux
pkg install -y build-essential cmake ninja vulkan-tools vulkan-headers \
               libvulkan libvulkan-dev clblast opencl-headers

git clone https://github.com/ggml-org/llama.cpp.git
cd llama.cpp

mkdir build && cd build

cmake .. \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLAMA_VULKAN=ON \
  -DLLAMA_CLBLAST=ON \
  -DLLAMA_NATIVE=OFF \
  -DLLAMA_AVX2=OFF \
  -DLLAMA_AVX=OFF \
  -DLLAMA_FMA=OFF \
  -DLLAMA_ARMBRNG=ON \
  -DLLAMA_ARM64_SVE=ON \
  -GNinja

ninja -j$(nproc)
```

**Flags explained for Snapdragon:**
| Flag | Why |
|---|---|
| `LLAMA_VULKAN=ON` | Adreno GPU acceleration (biggest speedup) |
| `LLAMA_CLBLAST=ON` | OpenCL fallback for older Adreno GPUs |
| `LLAMA_AVX*=OFF` | x86 features — not available on ARM |
| `LLAMA_ARM64_SVE=ON` | Scalable Vector Extensions on Snapdragon X-series |
| `LLAMA_ARMBRNG=ON` | ARM hardware random number generator |

### Download Models

Small models that run well on phones:

```bash
mkdir -p ~/models

# Qwen2.5-Coder 1.5B (best code model for phones)
wget -O ~/models/qwen-coder-1.5b-q4_k_m.gguf \
  https://huggingface.co/Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF/resolve/main/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf

# Llama 3.2 3B (good all-rounder)
wget -O ~/models/llama-3.2-3b-q4_k_m.gguf \
  https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf

# DeepSeek Coder 1.3B (tiny but capable)
wget -O ~/models/deepseek-coder-1.3b-q4_k_m.gguf \
  https://huggingface.co/deepseek-ai/deepseek-coder-1.3b-instruct-GGUF/resolve/main/deepseek-coder-1.3b-instruct-q4_k_m.gguf
```

### Start llama.cpp Server

```bash
cd ~/llama.cpp/build

# Run the inference server
./bin/llama-server \
  -m ~/models/qwen-coder-1.5b-q4_k_m.gguf \
  --host 127.0.0.1 \
  --port 8080 \
  -ngl 99 \
  -c 4096 \
  --mlock
```

> `-ngl 99` offloads all layers to the GPU. On Snapdragon 8 Gen 1+, you'll get **15-25 tok/s** on 1.5B models.

### Connect Harnesses to Local llama.cpp

**Aider:**
```bash
aider --model ollama/qwen2.5-coder:1.5b \
      --ollama-server http://127.0.0.1:8080
```

**OpenCode:**
```bash
opencode --provider ollama --model qwen2.5-coder:1.5b
```

**Any OpenAI-compatible harness:**
Just point it to the local server:
```bash
export OPENAI_BASE_URL="http://127.0.0.1:8080/v1"
```

---

## Phase 6: Remote Access

Access your phone's harnesses from your desktop:

### SSH into Your Phone

```bash
# On phone (Termux)
pkg install openssh
sshd -p 8022

# Get your phone's IP
ip addr show | grep inet

# On desktop
ssh -p 8022 u0_aXXX@<phone-ip>
```

### Expose Web Dashboard

For harnesses with web UIs (OpenClaude), use a tunnel:

```bash
# Via Cloudflare Tunnel (recommended)
pkg install cloudflared
cloudflared tunnel --url http://127.0.0.1:18789
```

Or use Tailscale for a private mesh network:
```bash
pkg install tailscale
tailscale up
# Now access your phone by its Tailscale IP from any device
```

---

## Snapdragon Performance Benchmarks

| Model | Snapdragon | RAM | Tok/s (Vulkan) | Tok/s (CPU) |
|---|---|---|---|---|
| Qwen 1.5B Q4 | 8 Gen 1 | 8 GB | ~22 | ~8 |
| Qwen 1.5B Q4 | 865 | 6 GB | ~14 | ~6 |
| Llama 3.2 3B Q4 | 8 Gen 1 | 8 GB | ~10 | ~3 |
| Llama 3.2 3B Q4 | 8 Gen 3 | 12 GB | ~18 | ~4 |
| DeepSeek 1.3B Q4 | 865 | 6 GB | ~18 | ~7 |

> Results vary by device cooling, battery level, and background processes.

---

## Stability Tips

- **Charge while running** — LLM inference is GPU-intensive
- **Close background apps** — free up RAM for larger context windows
- **Use a cooling pad** for sustained performance on Snapdragon 8 series
- **Monitor thermals:** `cat /sys/class/thermal/thermal_zone*/temp`
- **Set CPU governor to performance:** Only if rooted; not recommended for daily use

---

## Security

- Never share your API keys (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`)
- Never share your gateway auth tokens
- Use a separate API key for mobile (set spending limits)
- For local models, no API key needed — fully air-gapped operation
- Consider a firewall: `pkg install iptables` to restrict inbound connections

---

## Troubleshooting

### "Cannot find package" / npm errors
```bash
npm cache clean --force
npm install -g <package>@latest
```

### Vulkan not detected
```bash
# Check if Vulkan is available
vulkaninfo --summary

# Some Snapdragon devices need:
pkg install vulkan-loader-android
```

### Out of memory during inference
- Use smaller models (1.5B instead of 3B)
- Reduce context: `-c 2048` instead of `-c 4096`
- Close other Termux sessions

### Termux keeps crashing
```bash
pkg upgrade -y
termux-wake-lock
# If still crashing, restart the app
```

### Network errors in harnesses
```bash
# Make sure the network fix is loaded
echo $NODE_OPTIONS
# Should show: -r /root/hijack.js
```

---

## What You Can Build

- **Personal AI coding assistant** — always on, always in your pocket
- **Mobile dev environment** — write, test, and deploy from your phone
- **Offline code companion** — local models for flights, remote areas
- **Automation node** — cron jobs, scheduled tasks, webhook responder
- **Multi-agent orchestrator** — different harnesses for different tasks
- **Portable GPU workstation** — Snapdragon's Adreno GPU handles inference

---

<p align="center">
  <strong>Your phone is already a supercomputer.<br>You just weren't using it like one.</strong>
</p>

<p align="center">
  <sub>MIT License — use freely, build openly.</sub>
</p>
