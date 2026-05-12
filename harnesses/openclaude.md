# OpenClaude AI Agent on Android (Termux + Ubuntu)

Setup guide for running OpenClaude on your Android phone.

## 1. Install Termux & Ubuntu

Install [Termux](https://f-droid.org/packages/com.termux/) from F-Droid, then:
```bash
pkg update && pkg upgrade -y
pkg install proot-distro -y
proot-distro install ubuntu
proot-distro login ubuntu
```
Inside Ubuntu, install Node.js:
```bash
apt update && apt upgrade -y
apt install nodejs npm -y
node -v   # confirm v18+
```

## 2. Install OpenClaude
```bash
npm install -g openclaude
openclaude --version
```

## 3. Run the Onboarding Wizard
```bash
openclaude onboard
```
Choose your LLM provider, paste your API key, set a workspace (default: `~/openclaude-workspace`), and pick capabilities. Creates `~/.openclaude/config.yaml`.

## 4. Fix Network Interface (Android)
Termux's proot uses virtual loopback — configure the gateway bind address:
```bash
nano ~/.openclaude/config.yaml
```
Set:
```yaml
gateway:
  host: "127.0.0.1"
  port: 18789
```
Use `0.0.0.0` for LAN access from other devices on the same Wi-Fi.

## 5. Launch the Gateway
```bash
openclaude gateway start
```
Expected output: `[OpenClaude] Gateway running on http://127.0.0.1:18789`

Leave this terminal running or use tmux (see step 8).

## 6. Access the Dashboard
Open your mobile browser and visit:
```
http://127.0.0.1:18789
```
Dashboard includes chat interface, agent status, tool usage logs, and session management.

## 7. Get Your Gateway Auth Token
The gateway uses a bearer token from the config file:
```bash
grep "token" ~/.openclaude/config.yaml
```
Example output: `token: "oc_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"`

Use it in API requests:
```
Authorization: Bearer oc_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

## 8. Running in Background (Optional)
Keep the gateway alive after closing Termux:
```bash
apt install tmux -y
tmux new -s openclaude -d "openclaude gateway start"
```
Reattach with `tmux attach -t openclaude`.

## Notes
- **Costs**: You pay your LLM provider directly
- **Storage**: Workspace at `~/openclaude-workspace` inside proot
- **Updates**: `npm update -g openclaude`
- **Restart/Stop**: `openclaude gateway restart` / `openclaude gateway stop`
