# 🦙 Portable llama.cpp for Snapdragon Android

Build and run llama.cpp as a **fully self-contained, statically-linked binary** for ARM64 Android devices — no root, no external dependencies, no cloud.

---

## Architecture

```
┌─────────────────────────────────────────┐
│           Your Harness (Aider/Codex)    │
│         OpenAI-compatible HTTP client    │
└────────────────┬────────────────────────┘
                 │  POST /v1/chat/completions
                 ▼
┌─────────────────────────────────────────┐
│         llama-server (port 8080)         │
│  ┌──────────────────────────────────┐   │
│  │  GGUF Model (Q4_K_M quantization)│   │
│  └──────────┬───────────────────────┘   │
│             │ GPU offload               │
│  ┌──────────▼───────────────────────┐   │
│  │  Vulkan / CLBlast / CPU fallback │   │
│  └──────────────────────────────────┘   │
└─────────────────────────────────────────┘
```

---

## Pre-built Binary (Fastest)

```bash
# In Termux (NOT in proot-distro Ubuntu)
pkg install -y llama.cpp
```

This installs a pre-compiled ARM64 binary from the Termux community repo with Vulkan support enabled.

**Verify:**
```bash
llama-server --version
llama-perplexity --help
```

---

## Build from Source (Optimized for Snapdragon)

For maximum performance, build with Snapdragon-specific optimizations:

### Prerequisites

```bash
# In Termux (NOT in proot-distro)
pkg install -y build-essential cmake ninja vulkan-tools \
               vulkan-headers libvulkan libvulkan-dev \
               clblast opencl-headers opencl-clhpp
```

### Clone & Build

```bash
git clone --depth 1 https://github.com/ggml-org/llama.cpp.git
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
  -DLLAMA_SSE=OFF \
  -DLLAMA_ARMBRNG=ON \
  -GNinja

ninja -j$(nproc)
```

### Build for Portability (Static Binary)

To produce a single binary with no shared library dependencies:

```bash
cmake .. \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLAMA_VULKAN=ON \
  -DLLAMA_STATIC=ON \
  -DLLAMA_NATIVE=OFF \
  -DLLAMA_AVX2=OFF \
  -DLLAMA_AVX=OFF \
  -DLLAMA_FMA=OFF \
  -DLLAMA_SSE=OFF \
  -GNinja

ninja -j$(nproc) llama-server llama-cli llama-perplexity

# Check it's truly static
file bin/llama-server
# Should say: ELF ... statically linked
```

---

## Download Quantized Models

```bash
mkdir -p ~/models

# ~1.1 GB — Best code model for mobile
wget -O ~/models/qwen-coder-1.5b-q4_k_m.gguf \
  https://huggingface.co/Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF/resolve/main/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf

# ~2.2 GB — Good all-rounder
wget -O ~/models/llama-3.2-3b-q4_k_m.gguf \
  https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf

# ~800 MB — Tiny but capable
wget -O ~/models/deepseek-coder-1.3b-q4_k_m.gguf \
  https://huggingface.co/deepseek-ai/deepseek-coder-1.3b-instruct-GGUF/resolve/main/deepseek-coder-1.3b-instruct-q4_k_m.gguf

# ~500 MB — Minimal model for testing
wget -O ~/models/smol-v2-135m-q4_k_m.gguf \
  https://huggingface.co/HuggingFaceTB/SmolV2-135M-Instruct-GGUF/resolve/main/smolv2-135m-instruct-q4_k_m.gguf
```

---

## Run the Server

### Basic (CPU only)

```bash
cd ~/llama.cpp/build
./bin/llama-server \
  -m ~/models/qwen-coder-1.5b-q4_k_m.gguf \
  --host 127.0.0.1 \
  --port 8080 \
  -c 4096 \
  --mlock
```

### GPU Accelerated (Snapdragon Recommended)

```bash
cd ~/llama.cpp/build
./bin/llama-server \
  -m ~/models/qwen-coder-1.5b-q4_k_m.gguf \
  --host 127.0.0.1 \
  --port 8080 \
  -ngl 99 \
  -c 4096 \
  --mlock \
  --no-mmap
```

| Flag | Purpose |
|---|---|
| `-ngl 99` | Offload ALL layers to GPU. 99 = offload everything available |
| `--mlock` | Lock model in RAM (prevents Android from swapping it) |
| `--no-mmap` | Load model into memory instead of mmap (better on mobile) |
| `-c 4096` | Context window. Reduce to 2048 on 6 GB devices |

### Low-RAM Mode (6 GB devices)

```bash
./bin/llama-server \
  -m ~/models/qwen-coder-1.5b-q4_k_m.gguf \
  --host 127.0.0.1 \
  --port 8080 \
  -ngl 99 \
  -c 2048 \
  -b 64 \
  -ub 64 \
  --mlock \
  --no-mmap
```

---

## Connect Harnesses

### Aider
```bash
aider --model ollama/qwen2.5-coder:1.5b \
      --ollama-server http://127.0.0.1:8080
```

### OpenCode
```bash
opencode --provider ollama --model qwen2.5-coder:1.5b
```

### Any OpenAI-compatible client
```bash
export OPENAI_BASE_URL="http://127.0.0.1:8080/v1"
export OPENAI_API_KEY="not-needed"
```

---

## Performance Tuning

### Find Your GPU

```bash
vulkaninfo --summary | grep -i "deviceName\|adreno\|snapdragon"
```

### Benchmark Tokens per Second

```bash
cd ~/llama.cpp/build

# GPU benchmark
./bin/llama-bench \
  -m ~/models/qwen-coder-1.5b-q4_k_m.gguf \
  -ngl 99

# CPU-only comparison
./bin/llama-bench \
  -m ~/models/qwen-coder-1.5b-q4_k_m.gguf \
  -ngl 0
```

### Adjust for Thermal Throttling

On Snapdragon 8 Gen 1+ devices, sustained inference heats up quickly:

```bash
# Lower GPU offload to reduce heat
-ngl 20   # 20 layers on GPU, rest on CPU

# Or reduce batch size
-b 32
-ub 32

# Or use a smaller model
-m ~/models/deepseek-coder-1.3b-q4_k_m.gguf
```

---

## Advanced: Use as a System Service

### With tmux (Background Server)

```bash
tmux new-session -d -s llamaserver './bin/llama-server \
  -m ~/models/qwen-coder-1.5b-q4_k_m.gguf \
  --host 127.0.0.1 --port 8080 -ngl 99 -c 4096 --mlock --no-mmap'

# Reattach
tmux attach -t llamaserver

# Stop
tmux kill-session -t llamaserver
```

### With termux-services (Auto-restart)

```bash
pkg install termux-services
```

Then create `/data/data/com.termux/files/home/.termux/llamaserver.sh`

---

## Model Compatibility Matrix

| Model | Size | RAM Needed | Tok/s (GPU) | Best For |
|---|---|---|---|---|
| SmolV2 135M | 500 MB | 2 GB | 60+ | Chat, quick tests |
| DeepSeek Coder 1.3B | 800 MB | 3 GB | 25-35 | Code completions |
| Qwen 2.5 Coder 1.5B | 1.1 GB | 4 GB | 15-25 | Full harness usage |
| Llama 3.2 3B | 2.2 GB | 6 GB | 8-12 | Complex reasoning |
| Qwen 2.5 7B | 4.5 GB | 8 GB | 4-6 | High quality (8+ GB only) |

> All measurements with Q4_K_M quantization and Vulkan GPU offload on Snapdragon 8 Gen 1.
