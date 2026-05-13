#!/data/data/com.termux/files/usr/bin/sh
# Creates Termux:Boot startup entries for Droid Harness services.

set -e

PROJECT_DIR="${DROID_HARNESS_HOME:-$HOME/droid-harness}"
BOOT_DIR="$HOME/.termux/boot"
BOOT_FILE="$BOOT_DIR/droid-harness"

mkdir -p "$BOOT_DIR"

cat > "$BOOT_FILE" <<EOF
#!/data/data/com.termux/files/usr/bin/sh
termux-wake-lock 2>/dev/null || true
cd "$PROJECT_DIR"
export DROID_HARNESS_HOME="$PROJECT_DIR"
nohup "$PROJECT_DIR/scripts/start-termux-bridge.sh" > "$PROJECT_DIR/termux-bridge.log" 2>&1 &
EOF

chmod +x "$BOOT_FILE"

echo "Termux:Boot entry created: $BOOT_FILE"
echo "Install and enable the Termux:Boot app from F-Droid, then reboot Android."
