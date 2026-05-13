#!/usr/bin/env python3
"""Local Droid Harness bridge for Termux.

This service runs inside Termux and exposes a localhost HTTP API for the Flutter
app. It owns one PTY-backed shell session and streams output through a small
polling endpoint.
"""

from __future__ import annotations

import argparse
import json
import os
import pty
import shlex
import select
import signal
import subprocess
import threading
import time
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any
from urllib.parse import parse_qs, urlparse


class TerminalSession:
    def __init__(self) -> None:
        self._lock = threading.RLock()
        self._events: list[dict[str, Any]] = []
        self._next_id = 1
        self._master_fd: int | None = None
        self._process: subprocess.Popen[bytes] | None = None
        self._reader: threading.Thread | None = None

    def status(self) -> dict[str, Any]:
        with self._lock:
            running = self._process is not None and self._process.poll() is None
            return {
                "running": running,
                "pid": self._process.pid if self._process else None,
                "events": len(self._events),
            }

    def start(self, command: str | None = None) -> dict[str, Any]:
        with self._lock:
            if self._process is not None and self._process.poll() is None:
                return self.status()

            master_fd, slave_fd = pty.openpty()
            shell = command or os.environ.get("SHELL") or "/data/data/com.termux/files/usr/bin/bash"
            if not os.path.exists(shell):
                shell = "/bin/sh"

            self._master_fd = master_fd
            self._process = subprocess.Popen(
                [shell, "-l"] if shell.endswith("bash") else [shell],
                stdin=slave_fd,
                stdout=slave_fd,
                stderr=slave_fd,
                close_fds=True,
                preexec_fn=os.setsid,
            )
            os.close(slave_fd)
            self._append("system", f"session started pid={self._process.pid}")
            self._reader = threading.Thread(target=self._read_loop, daemon=True)
            self._reader.start()
            return self.status()

    def stop(self) -> dict[str, Any]:
        with self._lock:
            process = self._process
            master_fd = self._master_fd
            self._process = None
            self._master_fd = None

        if process and process.poll() is None:
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass

        if master_fd is not None:
            try:
                os.close(master_fd)
            except OSError:
                pass

        self._append("system", "session stopped")
        return self.status()

    def write(self, data: str) -> dict[str, Any]:
        self.start()
        with self._lock:
            if self._master_fd is None:
                raise RuntimeError("terminal session is not available")
            os.write(self._master_fd, data.encode())
        return self.status()

    def events_after(self, after: int) -> dict[str, Any]:
        with self._lock:
            events = [event for event in self._events if event["id"] > after]
            next_id = self._next_id - 1
        return {"events": events, "next": next_id}

    def _read_loop(self) -> None:
        while True:
            with self._lock:
                process = self._process
                master_fd = self._master_fd

            if process is None or master_fd is None:
                return

            if process.poll() is not None:
                self._append("system", f"session exited code={process.returncode}")
                return

            try:
                ready, _, _ = select.select([master_fd], [], [], 0.2)
                if not ready:
                    continue
                chunk = os.read(master_fd, 4096)
                if not chunk:
                    continue
                self._append("stdout", chunk.decode(errors="replace"))
            except OSError as error:
                self._append("error", str(error))
                return

    def _append(self, kind: str, text: str) -> None:
        with self._lock:
            self._events.append(
                {
                    "id": self._next_id,
                    "kind": kind,
                    "text": text,
                    "time": time.time(),
                }
            )
            self._next_id += 1
            if len(self._events) > 2000:
                self._events = self._events[-1000:]


SESSION = TerminalSession()
PROJECT_DIR = os.environ.get(
    "DROID_HARNESS_HOME",
    os.path.abspath(os.path.join(os.path.dirname(__file__), "..")),
)


class BridgeHandler(BaseHTTPRequestHandler):
    server_version = "DroidHarnessBridge/0.1"

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path == "/health":
            self._json(
                {
                    "ok": True,
                    "termux": os.path.exists("/data/data/com.termux/files/usr"),
                    "cwd": os.getcwd(),
                    "terminal": SESSION.status(),
                    "hardware": hardware_profile(),
                }
            )
            return

        if parsed.path == "/hardware":
            self._json(hardware_profile())
            return

        if parsed.path == "/terminal/events":
            params = parse_qs(parsed.query)
            after = int(params.get("after", ["0"])[0] or "0")
            self._json(SESSION.events_after(after))
            return

        self._json({"error": "not found"}, HTTPStatus.NOT_FOUND)

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        body = self._read_json()

        try:
            if parsed.path == "/terminal/session":
                self._json(SESSION.start(body.get("shell")))
                return

            if parsed.path == "/terminal/stop":
                self._json(SESSION.stop())
                return

            if parsed.path == "/terminal/input":
                data = str(body.get("data", ""))
                self._json(SESSION.write(data))
                return

            if parsed.path == "/llm/start":
                profile = str(body.get("profile", "auto"))
                command = llm_command(profile)
                self._json(SESSION.write(command + "\n"))
                return

            if parsed.path == "/models/download":
                model = str(body.get("model", "recommended"))
                command = download_command(model)
                self._json(SESSION.write(command + "\n"))
                return
        except Exception as error:  # noqa: BLE001 - HTTP boundary reports errors.
            self._json({"error": str(error)}, HTTPStatus.INTERNAL_SERVER_ERROR)
            return

        self._json({"error": "not found"}, HTTPStatus.NOT_FOUND)

    def log_message(self, fmt: str, *args: Any) -> None:
        print(f"{self.address_string()} - {fmt % args}")

    def _read_json(self) -> dict[str, Any]:
        length = int(self.headers.get("content-length", "0") or "0")
        if length == 0:
            return {}
        data = self.rfile.read(length)
        return json.loads(data.decode())

    def _json(self, payload: dict[str, Any], status: HTTPStatus = HTTPStatus.OK) -> None:
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(body)))
        self.send_header("access-control-allow-origin", "*")
        self.end_headers()
        self.wfile.write(body)


def llm_command(profile: str) -> str:
    detected = hardware_profile()
    model = os.environ.get("DROID_HARNESS_MODEL") or str(detected["model_path"])
    ngl = str(detected["ngl"])
    context = str(detected["context"])
    batch = str(detected["batch"])
    ubatch = str(detected["ubatch"])

    if profile == "weak":
        ngl, context, batch, ubatch = "0", "1536", "32", "32"
    elif profile == "lowram":
        context, batch, ubatch = "2048", "64", "64"

    quoted_model = shlex.quote(model)
    return (
        f"llama-server -m {quoted_model} --host 127.0.0.1 --port 8080 "
        f"-ngl {ngl} -c {context} -b {batch} -ub {ubatch} --no-mmap"
    )


def download_command(model: str) -> str:
    allowed = {
        "recommended",
        "all",
        "qwen",
        "qwen-tiny",
        "qwen-coder",
        "gemma",
        "llama",
        "deepseek",
        "smol",
    }
    selected = model if model in allowed else "recommended"
    script = os.path.join(PROJECT_DIR, "llama-portable", "download-models.sh")
    return f"bash {shlex.quote(script)} {shlex.quote(selected)}"


def hardware_profile() -> dict[str, Any]:
    script = os.path.join(PROJECT_DIR, "scripts", "model-profile.sh")
    fallback = {
        "profile": "weak",
        "models_dir": os.path.join(PROJECT_DIR, "models", "offline"),
        "model_id": "qwen3-0.6b-q4_k_m",
        "model_path": os.path.join(
            PROJECT_DIR,
            "models",
            "offline",
            "qwen3-0.6b-q4_k_m",
            "qwen3-0.6b-q4_k_m.gguf",
        ),
        "context": 1536,
        "batch": 32,
        "ubatch": 32,
        "ngl": 0,
    }
    if not os.path.exists(script):
        return fallback

    try:
        output = subprocess.check_output(
            ["sh", script, "--shell"],
            text=True,
            stderr=subprocess.DEVNULL,
            timeout=4,
        )
    except (subprocess.SubprocessError, OSError):
        return fallback

    values: dict[str, str] = {}
    for line in output.splitlines():
        if "=" not in line:
            continue
        key, raw_value = line.split("=", 1)
        values[key] = raw_value.strip().strip("'")

    return {
        "profile": values.get("DROID_HARNESS_PROFILE", fallback["profile"]),
        "models_dir": values.get("DROID_HARNESS_MODELS_DIR", fallback["models_dir"]),
        "model_id": values.get(
            "DROID_HARNESS_RECOMMENDED_MODEL_ID",
            fallback["model_id"],
        ),
        "model_path": values.get(
            "DROID_HARNESS_RECOMMENDED_MODEL",
            fallback["model_path"],
        ),
        "context": int(values.get("DROID_HARNESS_CONTEXT", fallback["context"])),
        "batch": int(values.get("DROID_HARNESS_BATCH", fallback["batch"])),
        "ubatch": int(values.get("DROID_HARNESS_UBATCH", fallback["ubatch"])),
        "ngl": int(values.get("DROID_HARNESS_NGL", fallback["ngl"])),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", default=8765, type=int)
    args = parser.parse_args()

    server = ThreadingHTTPServer((args.host, args.port), BridgeHandler)
    print(f"Droid Harness bridge listening on http://{args.host}:{args.port}")
    server.serve_forever()


if __name__ == "__main__":
    main()
