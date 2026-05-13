#!/data/data/com.termux/files/usr/bin/sh
# Detects the local device profile and prints a safe offline model choice.

set -e

PROJECT_DIR="${DROID_HARNESS_HOME:-$HOME/droid-harness}"
MODELS_DIR="${DROID_HARNESS_MODELS_DIR:-$PROJECT_DIR/models/offline}"

mem_kb="$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
mem_mb=$((mem_kb / 1024))
cores="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
cpu_name="$(awk -F: '/Hardware|model name|Processor/ {gsub(/^[ \t]+/, "", $2); print $2; exit}' /proc/cpuinfo 2>/dev/null || true)"

gpu="cpu"
if command -v vulkaninfo >/dev/null 2>&1 && vulkaninfo --summary >/dev/null 2>&1; then
    gpu="vulkan"
fi

if [ "$mem_mb" -lt 7000 ] || [ "$cores" -le 4 ]; then
    profile="weak"
    model_id="qwen3-0.6b-q4_k_m"
    model_file="$MODELS_DIR/qwen3-0.6b-q4_k_m/qwen3-0.6b-q4_k_m.gguf"
    context="1536"
    batch="32"
    ubatch="32"
    ngl="0"
elif [ "$mem_mb" -lt 11000 ]; then
    profile="balanced"
    model_id="qwen3-1.7b-q4_k_m"
    model_file="$MODELS_DIR/qwen3-1.7b-q4_k_m/Qwen3-1.7B-Q4_K_M.gguf"
    context="2048"
    batch="64"
    ubatch="64"
    ngl=0
    [ "$gpu" = "vulkan" ] && ngl="99"
else
    profile="strong"
    model_id="qwen2.5-coder-1.5b-q4_k_m"
    model_file="$MODELS_DIR/qwen2.5-coder-1.5b-q4_k_m/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf"
    context="4096"
    batch="128"
    ubatch="128"
    ngl=0
    [ "$gpu" = "vulkan" ] && ngl="99"
fi

case "${1:-summary}" in
    --shell)
        cat <<EOF
DROID_HARNESS_PROFILE='$profile'
DROID_HARNESS_MODELS_DIR='$MODELS_DIR'
DROID_HARNESS_RECOMMENDED_MODEL_ID='$model_id'
DROID_HARNESS_RECOMMENDED_MODEL='$model_file'
DROID_HARNESS_CONTEXT='$context'
DROID_HARNESS_BATCH='$batch'
DROID_HARNESS_UBATCH='$ubatch'
DROID_HARNESS_NGL='$ngl'
EOF
        ;;
    *)
        cat <<EOF
Hardware profile: $profile
RAM: ${mem_mb} MB
CPU cores: $cores
CPU: ${cpu_name:-unknown}
GPU backend: $gpu
Models directory: $MODELS_DIR
Recommended model: $model_id
Model path: $model_file
llama-server flags: -ngl $ngl -c $context -b $batch -ub $ubatch
EOF
        ;;
esac
