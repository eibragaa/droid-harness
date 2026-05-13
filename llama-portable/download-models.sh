#!/data/data/com.termux/files/usr/bin/sh
# download-models.sh — Download quantized GGUF models for mobile
# Run this in Termux (NOT inside proot-distro)
#
# Usage:  bash download-models.sh [model-name]
# Models: recommended, all, qwen, qwen-tiny, qwen-coder, gemma, llama, deepseek, smol

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

PROJECT_DIR="${DROID_HARNESS_HOME:-$HOME/droid-harness}"
MODELS_DIR="${DROID_HARNESS_MODELS_DIR:-$PROJECT_DIR/models/offline}"
mkdir -p "$MODELS_DIR"

download() {
    local folder="$1"
    local name="$2"
    local url="$3"
    local model_dir="$MODELS_DIR/$folder"
    local output="$model_dir/$name"

    mkdir -p "$model_dir"

    if [ -f "$output" ]; then
        echo -e "${YELLOW}  ⚠ $name already exists — skipping${NC}"
        return
    fi

    echo -e "${CYAN}  ↓ Downloading $name...${NC}"
    wget -c --show-progress -O "$output" "$url"
    echo -e "${GREEN}  ✓ $name saved to $output${NC}"
}

recommended_model() {
    if [ -x "$PROJECT_DIR/scripts/model-profile.sh" ]; then
        "$PROJECT_DIR/scripts/model-profile.sh" --shell |
            awk -F= '/DROID_HARNESS_RECOMMENDED_MODEL_ID/ {gsub(/\047/, "", $2); print $2}'
    else
        echo "qwen3-0.6b-q4_k_m"
    fi
}

echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║        Download GGUF Models              ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
echo ""

# HuggingFace mirror for faster downloads in some regions
HF="https://huggingface.co"

case "${1:-recommended}" in
    recommended)
        model_id="$(recommended_model)"
        echo -e "${YELLOW}→ Hardware recommendation: $model_id${NC}"
        exec "$0" "$model_id"
        ;;
    all)
        echo -e "${YELLOW}→ Downloading ALL models${NC}"
        download "smol-v2-135m-q4_k_m" "smol-v2-135m-q4_k_m.gguf" \
            "${HF}/HuggingFaceTB/SmolV2-135M-Instruct-GGUF/resolve/main/smolv2-135m-instruct-q4_k_m.gguf"
        download "deepseek-coder-1.3b-q4_k_m" "deepseek-coder-1.3b-q4_k_m.gguf" \
            "${HF}/deepseek-ai/deepseek-coder-1.3b-instruct-GGUF/resolve/main/deepseek-coder-1.3b-instruct-q4_k_m.gguf"
        download "qwen3-0.6b-q4_k_m" "qwen3-0.6b-q4_k_m.gguf" \
            "${HF}/rippertnt/Qwen3-0.6B-Q4_K_M-GGUF/resolve/main/qwen3-0.6b-q4_k_m.gguf"
        download "qwen3-1.7b-q4_k_m" "Qwen3-1.7B-Q4_K_M.gguf" \
            "${HF}/jc-builds/Qwen3-1.7B-Q4_K_M-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf"
        download "qwen2.5-coder-1.5b-q4_k_m" "qwen2.5-coder-1.5b-instruct-q4_k_m.gguf" \
            "${HF}/Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF/resolve/main/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf"
        download "llama-3.2-3b-q4_k_m" "llama-3.2-3b-q4_k_m.gguf" \
            "${HF}/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf"
        ;;
    qwen|qwen3-1.7b-q4_k_m)
        download "qwen3-1.7b-q4_k_m" "Qwen3-1.7B-Q4_K_M.gguf" \
            "${HF}/jc-builds/Qwen3-1.7B-Q4_K_M-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf"
        ;;
    qwen-tiny|qwen3-0.6b-q4_k_m)
        download "qwen3-0.6b-q4_k_m" "qwen3-0.6b-q4_k_m.gguf" \
            "${HF}/rippertnt/Qwen3-0.6B-Q4_K_M-GGUF/resolve/main/qwen3-0.6b-q4_k_m.gguf"
        ;;
    qwen-coder|qwen2.5-coder-1.5b-q4_k_m)
        download "qwen2.5-coder-1.5b-q4_k_m" "qwen2.5-coder-1.5b-instruct-q4_k_m.gguf" \
            "${HF}/Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF/resolve/main/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf"
        ;;
    llama)
        download "llama-3.2-3b-q4_k_m" "llama-3.2-3b-q4_k_m.gguf" \
            "${HF}/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf"
        ;;
    deepseek)
        download "deepseek-coder-1.3b-q4_k_m" "deepseek-coder-1.3b-q4_k_m.gguf" \
            "${HF}/deepseek-ai/deepseek-coder-1.3b-instruct-GGUF/resolve/main/deepseek-coder-1.3b-instruct-q4_k_m.gguf"
        ;;
    smol)
        download "smol-v2-135m-q4_k_m" "smol-v2-135m-q4_k_m.gguf" \
            "${HF}/HuggingFaceTB/SmolV2-135M-Instruct-GGUF/resolve/main/smolv2-135m-instruct-q4_k_m.gguf"
        ;;
    gemma)
        echo -e "${YELLOW}Gemma 4 E2B/E4B e indicado para edge/mobile, mas os pesos oficiais podem exigir login/aceite no Hugging Face.${NC}"
        echo -e "${CYAN}Abra: https://huggingface.co/google${NC}"
        echo -e "${CYAN}Depois baixe o GGUF aceito para: $MODELS_DIR/gemma4/<arquivo>.gguf${NC}"
        ;;
    *)
        echo "Usage: $0 [recommended|all|qwen|qwen-tiny|qwen-coder|gemma|llama|deepseek|smol]"
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
find "$MODELS_DIR" -maxdepth 3 -name '*.gguf' -print 2>/dev/null | while read -r model; do
    du -sh "$model"
done | column -t || echo "(no models found)"
echo ""
echo -e "Run the server:"
echo -e "  ${CYAN}bash ~/droid-harness/scripts/start-termux-bridge.sh${NC}"
echo -e "  ${CYAN}Use o app Droid Harness Mobile: Baixar recomendado / Iniciar auto${NC}"
