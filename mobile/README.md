# Droid Harness Mobile

Flutter companion app for Droid Harness.

The app is the phone UI for a local Android AI workstation:

- checks `llama-server` on `http://127.0.0.1:8080/v1/models`
- sends prompts to the OpenAI-compatible local endpoint
- connects to the Termux bridge on `http://127.0.0.1:8765`
- sends terminal input to a real PTY session
- polls terminal stdout/stderr and renders it in the app

## Run

```bash
flutter run
```

## Start the Termux bridge

Inside Termux, from the Droid Harness repo:

```bash
scripts/start-termux-bridge.sh
```

The app will then be able to open a shell session and execute commands without
asking for manual confirmation on each command.

## Local model contract

Start the model from Termux:

```bash
llama-server \
  -m ~/models/qwen-coder-1.5b-q4_k_m.gguf \
  --host 127.0.0.1 \
  --port 8080 \
  -ngl 99 \
  -c 4096 \
  --mlock \
  --no-mmap
```

The first MVP talks to that server directly. The next step is a native Android
bridge that opens a PTY and forwards real command input/output into the terminal
panel.
