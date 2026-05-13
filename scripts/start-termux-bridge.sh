#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if command -v termux-wake-lock >/dev/null 2>&1; then
  termux-wake-lock || true
fi

python3 scripts/termux-bridge.py --host 127.0.0.1 --port "${DROID_HARNESS_BRIDGE_PORT:-8765}"
