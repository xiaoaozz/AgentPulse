#!/usr/bin/env python3
"""Translate Codex/Claude hook JSON from stdin into AgentPulse's generic event."""

import json
import ntpath
import os
import socket
import sys
from datetime import datetime, timezone


def transport_endpoint(platform=sys.platform, env=os.environ):
    if env.get("AGENTPULSE_SOCKET"):
        return env["AGENTPULSE_SOCKET"]
    return r"\\.\pipe\agentpulse" if platform == "win32" else "/tmp/agentpulse.sock"


def phase_for(event, data):
    status = (
        data.get("status")
        or (data.get("turn") or {}).get("status")
        or ((data.get("params") or {}).get("turn") or {}).get("status")
    )
    tool_response = data.get("tool_response") or {}
    interrupted = (
        status in ("interrupted", "cancelled", "canceled", "aborted")
        or any(
            value.get(key) is True
            for value in (data, tool_response)
            if isinstance(value, dict)
            for key in ("interrupted", "cancelled", "canceled", "aborted")
        )
    )
    interruptible_events = (
        "PostToolUse",
        "PostToolUseFailure",
        "Stop",
        "agent-turn-complete",
        "turn/completed",
    )
    if event in interruptible_events and interrupted:
        return "paused"
    if event == "turn/completed":
        return "failed" if status == "failed" else "done"
    if event == "SessionStart":
        return "idle"
    if event == "UserPromptSubmit":
        return "preparing"
    if event in ("PreToolUse", "PostToolUse"):
        return "running"
    if event == "PermissionRequest":
        return "waiting_for_action"
    if event in ("Stop", "SubagentStop", "agent-turn-complete"):
        return "done"
    if event == "Notification" and data.get("notification_type") in (
        "idle_prompt",
        "permission_prompt",
    ):
        return "waiting_for_action"
    if event == "PreCompact":
        return "running"
    if event == "SessionEnd":
        return "offline"
    return None


def terminal_bundle_id():
    program = os.environ.get("TERM_PROGRAM", "").lower()
    return {
        "apple_terminal": "com.apple.Terminal",
        "iterm.app": "com.googlecode.iterm2",
        "ghostty": "com.mitchellh.ghostty",
        "warpterminal": "dev.warp.Warp-Stable",
    }.get(program)


def terminal_process_name(platform=sys.platform, env=os.environ):
    if platform != "win32":
        return None
    if env.get("WT_SESSION"):
        return "WindowsTerminal.exe"
    return {
        "vscode": "Code.exe",
        "warpterminal": "Warp.exe",
    }.get(env.get("TERM_PROGRAM", "").lower())


def send_payload(encoded, platform=sys.platform, endpoint=None):
    endpoint = endpoint or transport_endpoint(platform)
    if platform == "win32":
        import ctypes

        wait_named_pipe = ctypes.windll.kernel32.WaitNamedPipeW
        wait_named_pipe.argtypes = [ctypes.c_wchar_p, ctypes.c_uint32]
        wait_named_pipe.restype = ctypes.c_int
        if not wait_named_pipe(endpoint, 250):
            return
        with open(endpoint, "wb", buffering=0) as client:
            client.write(encoded)
        return

    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(0.25)
        client.connect(endpoint)
        client.sendall(encoded)


def main():
    data = json.load(sys.stdin)
    event = (
        data.get("hook_event_name")
        or data.get("event")
        or data.get("type")
        or data.get("method", "")
    )
    phase = phase_for(event, data)
    if phase is None:
        return
    transcript = data.get("transcript_path", "") or ""
    agent = "Codex" if "/.codex/" in transcript else os.environ.get("AGENTPULSE_AGENT", "Agent")
    detail = (
        data.get("last_assistant_message")
        or data.get("assistant_message")
        or data.get("message")
        or data.get("tool_name")
        or (
            ((data.get("params") or {}).get("turn") or {}).get("error") or {}
        ).get("message")
    )
    session_id = (
        data.get("session_id")
        or (data.get("params") or {}).get("threadId")
        or "unknown"
    )
    payload = {
        "session_id": session_id,
        "agent": agent,
        "cwd": data.get("cwd", os.getcwd()),
        "title": data.get("title") or ntpath.basename(data.get("cwd", os.getcwd()).rstrip("/\\")),
        "phase": phase,
        "detail": detail,
        "pid": os.getppid(),
        "tty": os.ttyname(0) if hasattr(os, "ttyname") and os.isatty(0) else None,
        "terminal_bundle_id": terminal_bundle_id(),
        "terminal_process": terminal_process_name(),
        "occurred_at": datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
    }
    encoded = json.dumps(payload, ensure_ascii=False).encode()
    try:
        send_payload(encoded)
    except (OSError, TimeoutError):
        pass


if __name__ == "__main__":
    main()
