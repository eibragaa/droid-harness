#!/data/data/com.termux/files/usr/bin/sh
# health-check.sh — Check status of all installed harnesses + llama.cpp
#
# Usage:  bash health-check.sh

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║      Droid Harness — Health Check         ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
echo ""

# ── System ───────────────────────────────────────────────────────
echo -e "${YELLOW}System${NC}"
echo -e "  RAM:       $(free -h | awk '/^Mem:/ {print $3 "/" $2}')"
echo -e "  Load:      $(uptime | awk -F'load average:' '{print $2}' | xargs)"
echo -e "  Storage:   $(df -h /data 2>/dev/null | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')"
echo ""

# ── Network fix ──────────────────────────────────────────────────
echo -e "${YELLOW}Network Fix${NC}"
if [ -n "$NODE_OPTIONS" ]; then
    echo -e "  ${GREEN}✓ NODE_OPTIONS=$NODE_OPTIONS${NC}"
else
    echo -e "  ${RED}✗ NODE_OPTIONS not set — harnesses may crash${NC}"
fi
echo ""

# ── Termux Wake Lock ─────────────────────────────────────────────
if command -v termux-wake-lock >/dev/null 2>&1; then
    echo -e "  ${GREEN}✓ termux-wake-lock available${NC}"
else
    echo -e "  ${YELLOW}⚠ termux-api not installed${NC}"
fi
echo ""

# ── Harnesses ────────────────────────────────────────────────────
echo -e "${YELLOW}Harnesses${NC}"

check_npm() {
    local name="$1"
    local pkg="$2"
    if proot-distro login ubuntu -- bash -c "npm list -g --depth=0 2>/dev/null | grep -qi '$pkg'" 2>/dev/null; then
        echo -e "  ${GREEN}✓ $name${NC}"
    else
        echo -e "  ${RED}✗ $name (npm -g $pkg)${NC}"
    fi
}

check_pip() {
    local name="$1"
    local pkg="$2"
    if proot-distro login ubuntu -- bash -c "pip3 show '$pkg' 2>/dev/null | grep -qi 'Name'" 2>/dev/null; then
        echo -e "  ${GREEN}✓ $name${NC}"
    else
        echo -e "  ${RED}✗ $name (pip3 install $pkg)${NC}"
    fi
}

check_npm "OpenClaude"   "openclaude"
check_npm "Claude Code"  "@anthropic-ai/claude-code"
check_pip "Codex CLI"    "codex-cli"
check_pip "Aider"        "aider-chat"

# OpenCode (Go binary)
if proot-distro login ubuntu -- bash -c "command -v opencode" 2>/dev/null; then
    echo -e "  ${GREEN}✓ OpenCode${NC}"
else
    echo -e "  ${RED}✗ OpenCode (go install github.com/sst/opencode@latest)${NC}"
fi

echo ""

# ── llama.cpp ────────────────────────────────────────────────────
echo -e "${YELLOW}llama.cpp${NC}"

if command -v llama-server >/dev/null 2>&1; then
    echo -e "  ${GREEN}✓ llama-server (system)${NC}"
elif [ -f "$HOME/llama.cpp/build/bin/llama-server" ]; then
    echo -e "  ${GREEN}✓ llama-server (local build)${NC}"
else
    echo -e "  ${RED}✗ llama-server not installed${NC}"
fi

# Check for models
MODEL_COUNT=$(find "$HOME/models" -name "*.gguf" 2>/dev/null | wc -l)
if [ "$MODEL_COUNT" -gt 0 ]; then
    echo -e "  ${GREEN}✓ $MODEL_COUNT model(s) found in ~/models/${NC}"
    find "$HOME/models" -name "*.gguf" -exec du -h {} \; 2>/dev/null | while read line; do
        echo -e "     $line"
    done
else
    echo -e "  ${YELLOW}⚠ No GGUF models found — run download-models.sh${NC}"
fi

echo ""

# ── Dashboard URLs ───────────────────────────────────────────────
echo -e "${YELLOW}Access Points${NC}"
echo -e "  OpenClaude:   ${CYAN}http://127.0.0.1:18789${NC}"
echo -e "  llama.cpp:    ${CYAN}http://127.0.0.1:8080/v1${NC}"

echo ""
echo -e "${GREEN}✓ Health check complete${NC}"
