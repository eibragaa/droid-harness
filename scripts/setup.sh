#!/data/data/com.termux/files/usr/bin/sh
# setup.sh — Full automated environment setup for droid-harness
# Run this in Termux (NOT inside proot-distro)
#
# Usage:  bash setup.sh [--minimal]
#         --minimal: skip model downloads, just install the base

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║       Droid Harness — Auto Setup          ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
echo ""

# ── Step 1: System packages ──────────────────────────────────────
echo -e "${YELLOW}[1/6] Updating Termux packages...${NC}"
pkg update -y && pkg upgrade -y

echo -e "${YELLOW}[2/6] Installing base dependencies...${NC}"
pkg install -y proot-distro git curl wget python nodejs-lts \
               build-essential cmake ninja vulkan-tools \
               openssh termux-api

# ── Step 2: Wake lock ────────────────────────────────────────────
echo -e "${YELLOW}[3/6] Acquiring wake lock...${NC}"
termux-wake-lock 2>/dev/null || true
mkdir -p "${DROID_HARNESS_MODELS_DIR:-$HOME/droid-harness/models/offline}"

# ── Step 3: Install Ubuntu ───────────────────────────────────────
echo -e "${YELLOW}[4/6] Installing Ubuntu (proot-distro)...${NC}"
if proot-distro list | grep -q "ubuntu"; then
    echo -e "${GREEN}  ✓ Ubuntu already installed${NC}"
else
    proot-distro install ubuntu
fi

# ── Step 4: Bootstrap Ubuntu ─────────────────────────────────────
echo -e "${YELLOW}[5/6] Setting up Ubuntu environment...${NC}"
proot-distro login ubuntu -- bash << 'UBUNTU_SETUP'
    set -e
    apt update && apt upgrade -y
    apt install -y curl wget git python3 python3-pip python3-venv \
                   build-essential cmake pkg-config libssl-dev \
                   nodejs npm

    # Network interface hijack for Node.js harnesses
    if [ ! -f /root/hijack.js ]; then
        cat <<'EOF' > /root/hijack.js
const os = require('os');
os.networkInterfaces = () => ({});
EOF
    fi

    if ! grep -q "NODE_OPTIONS.*hijack" ~/.bashrc 2>/dev/null; then
        echo 'export NODE_OPTIONS="-r /root/hijack.js"' >> ~/.bashrc
    fi

    echo "Ubuntu ready."
UBUNTU_SETUP

# ── Step 5: Recommended harnesses ────────────────────────────────
echo -e "${YELLOW}[6/6] Installing recommended harnesses...${NC}"

echo -e "${CYAN}  Which harnesses do you want? You can install more later.${NC}"
echo -e "  ${GREEN}1${NC}) OpenClaude   — Multi-provider agent + dashboard"
echo -e "  ${GREEN}2${NC}) Claude Code  — Anthropic CLI agent"
echo -e "  ${GREEN}3${NC}) Codex CLI    — OpenAI coding agent"
echo -e "  ${GREEN}4${NC}) Aider        — Git-aware pair programmer"
echo -e "  ${GREEN}5${NC}) All of the above"
echo -e "  ${GREEN}s${NC}) Skip — I'll install later"
echo ""
read -p "Pick a number [5]: " choice
choice="${choice:-5}"

case "$choice" in
    1)
        proot-distro login ubuntu -- bash -c "npm install -g openclaude@latest"
        echo -e "${GREEN}  ✓ OpenClaude installed${NC}"
        ;;
    2)
        proot-distro login ubuntu -- bash -c "npm install -g @anthropic-ai/claude-code"
        echo -e "${GREEN}  ✓ Claude Code installed${NC}"
        ;;
    3)
        proot-distro login ubuntu -- bash -c "pip3 install codex-cli"
        echo -e "${GREEN}  ✓ Codex CLI installed${NC}"
        ;;
    4)
        proot-distro login ubuntu -- bash -c "pip3 install aider-chat"
        echo -e "${GREEN}  ✓ Aider installed${NC}"
        ;;
    5|"")
        proot-distro login ubuntu -- bash -c "
            npm install -g openclaude@latest 2>/dev/null || true
            npm install -g @anthropic-ai/claude-code 2>/dev/null || true
            pip3 install codex-cli 2>/dev/null || true
            pip3 install aider-chat 2>/dev/null || true
        "
        echo -e "${GREEN}  ✓ All harnesses installed${NC}"
        ;;
    s|S)
        echo -e "${YELLOW}  Skipping harness installation${NC}"
        ;;
esac

# ── Done ──────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     Droid Harness is ready!              ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${CYAN}→${NC} Enter Ubuntu:     ${GREEN}proot-distro login ubuntu${NC}"
echo -e "  ${CYAN}→${NC} Read the docs:    ${GREEN}cat ~/droid-harness/README.md${NC}"
echo -e "  ${CYAN}→${NC} Go to harnesses:  ${GREEN}cd ~/droid-harness/harnesses/${NC}"
echo -e "  ${CYAN}→${NC} Build llama.cpp:  ${GREEN}bash ~/droid-harness/llama-portable/build-termux.sh${NC}"
echo -e "  ${CYAN}→${NC} Offline models:   ${GREEN}~/droid-harness/models/offline${NC}"
echo -e "  ${CYAN}→${NC} Detect model:      ${GREEN}bash ~/droid-harness/scripts/model-profile.sh${NC}"
echo -e "  ${CYAN}→${NC} Auto boot:         ${GREEN}bash ~/droid-harness/scripts/install-termux-boot.sh${NC}"
echo -e ""
echo -e "${YELLOW}  📱 Your phone is now an AI coding workstation.${NC}"
