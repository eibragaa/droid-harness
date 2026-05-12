#!/data/data/com.termux/files/usr/bin/sh
# download-models.sh — Download quantized GGUF models for mobile
# Run this in Termux (NOT inside proot-distro)
#
# Usage:  bash download-models.sh [model-name]
# Models: all, qwen, llama, deepseek, smol

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

MODELS_DIR="${HOME}/models"
mkdir -p "$MODELS_DIR"

download() {
    local name="$1"
    local url="$2"
    local output="$MODELS_DIR/$name"

    if [ -f "$output" ]; then
        echo -e "${YELLOW}  ⚠ $name already exists — skipping${NC}"
        return
    fi

    echo -e "${CYAN}  ↓ Downloading $name...${NC}"
    wget -q --show-progress -O "$output" "$url"
    echo -e "${GREEN}  ✓ $name saved to $output${NC}"
}

echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║        Download GGUF Models              ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
echo ""

# HuggingFace mirror for faster downloads in some regions
HF="https://huggingface.co"

case "${1:-all}" in
    all)
        echo -e "${YELLOW}→ Downloading ALL models${NC}"
        download "smol-v2-135m-q4_k_m.gguf" \
            "${HF}/HuggingFaceTB/SmolV2-135M-Instruct-GGUF/resolve/main/smolv2-135m-instruct-q4_k_m.gguf"
        download "deepseek-coder-1.3b-q4_k_m.gguf" \
            "${HF}/deepseek-ai/deepseek-coder-1.3b-instruct-GGUF/resolve/main/deepseek-coder-1.3b-instruct-q4_k_m.gguf"
        download "qwen-coder-1.5b-q4_k_m.gguf" \
            "${HF}/Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF/resolve/main/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf"
        download "llama-3.2-3b-q4_k_m.gguf" \
            "${HF}/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf"
        ;;
    qwen)
        download "qwen-coder-1.5b-q4_k_m.gguf" \
            "${HF}/Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF/resolve/main/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf"
        ;;
    llama)
        download "llama-3.2-3b-q4_k_m.gguf" \
            "${HF}/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf"
        ;;
    deepseek)
        download "deepseek-coder-1.3b-q4_k_m.gguf" \
            "${HF}/deepseek-ai/deepseek-coder-1.3b-instruct-GGUF/resolve/main/deepseek-coder-1.3b-instruct-q4_k_m.gguf"
        ;;
    smol)
        download "smol-v2-135m-q4_k_m.gguf" \
            "${HF}/HuggingFaceTB/SmolV2-135M-Instruct-GGUF/resolve/main/smolv2-135m-instruct-q4_k_m.gguf"
        ;;
    *)
        echo "Usage: $0 [all|qwen|llama|deepseek|smol]"
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║        Downloads complete!               ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "Models stored in: ${CYAN}$MODELS_DIR${NC}"
echo -e ""
du -sh "$MODELS_DIR"/*.gguf 2>/dev/null | column -t || echo "(no models found)"
echo ""
echo -e "Run the server:"
echo -e "  ${CYAN}llama-server -m ~/models/qwen-coder-1.5b-q4_k_m.gguf --host 127.0.0.1 --port 8080 -ngl 99${NC}"
