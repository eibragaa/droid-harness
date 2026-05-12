#!/data/data/com.termux/files/usr/bin/sh
# build-llama-termux.sh — Build llama.cpp for Snapdragon Android from Termux
# Run this in Termux (NOT inside proot-distro)
#
# Usage:  bash build-llama-termux.sh [--static] [--clean]

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   llama.cpp Builder for Snapdragon      ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"

# Detect Vulkan support
if vulkaninfo --summary >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Vulkan detected${NC}"
    VULKAN_FLAG="-DLLAMA_VULKAN=ON"
else
    echo -e "${YELLOW}⚠ Vulkan not detected — building CPU only${NC}"
    VULKAN_FLAG="-DLLAMA_VULKAN=OFF"
fi

# Detect OpenCL
if command -v clinfo >/dev/null 2>&1; then
    echo -e "${GREEN}✓ OpenCL detected${NC}"
    CLBLAST_FLAG="-DLLAMA_CLBLAST=ON"
else
    CLBLAST_FLAG="-DLLAMA_CLBLAST=OFF"
fi

# Parse args
STATIC="OFF"
if [ "$1" = "--static" ]; then
    STATIC="ON"
    echo -e "${YELLOW}■ Building static binary${NC}"
elif [ "$1" = "--clean" ] || [ "$2" = "--clean" ]; then
    echo -e "${YELLOW}■ Clean build${NC}"
fi

INSTALL_DIR="$HOME/llama.cpp"
BUILD_DIR="$INSTALL_DIR/build"

# Install dependencies
echo -e "\n${YELLOW}→ Installing build dependencies...${NC}"
pkg install -y build-essential cmake ninja vulkan-headers \
               libvulkan libvulkan-dev clblast opencl-headers 2>/dev/null || true

# Clone if needed
if [ ! -d "$INSTALL_DIR" ]; then
    echo -e "${YELLOW}→ Cloning llama.cpp...${NC}"
    git clone --depth 1 https://github.com/ggml-org/llama.cpp.git "$INSTALL_DIR"
fi

# Clean if requested
if [ "$1" = "--clean" ] || [ "$2" = "--clean" ]; then
    echo -e "${YELLOW}→ Cleaning build directory...${NC}"
    rm -rf "$BUILD_DIR"
fi

# Configure
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

echo -e "${YELLOW}→ Configuring CMake...${NC}"
cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    "$VULKAN_FLAG" \
    "$CLBLAST_FLAG" \
    -DLLAMA_STATIC="$STATIC" \
    -DLLAMA_NATIVE=OFF \
    -DLLAMA_AVX2=OFF \
    -DLLAMA_AVX=OFF \
    -DLLAMA_FMA=OFF \
    -DLLAMA_SSE=OFF \
    -DLLAMA_ARMBRNG=ON \
    -GNinja

# Build
echo -e "${YELLOW}→ Building (this may take 10-30 minutes)...${NC}"
ninja -j$(nproc) llama-server llama-cli llama-perplexity llama-bench 2>&1

echo -e "\n${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Build complete!                        ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "Binaries: ${CYAN}$BUILD_DIR/bin/${NC}"
echo -e ""
echo -e "  ${GREEN}llama-server${NC}  — HTTP server (connect harnesses here)"
echo -e "  ${GREEN}llama-cli${NC}     — Chat CLI"
echo -e "  ${GREEN}llama-bench${NC}   — Benchmark tool"
echo -e "  ${GREEN}llama-perplexity${NC} — Evaluation"
echo ""
echo -e "Quick start:"
echo -e "  ${CYAN}./bin/llama-server -m ~/models/qwen-coder-1.5b-q4_k_m.gguf --host 127.0.0.1 --port 8080 -ngl 99${NC}"
echo ""
