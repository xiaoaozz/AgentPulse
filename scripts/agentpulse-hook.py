#!/usr/bin/env python3
"""Translate Codex/Claude hook JSON from stdin into AgentPulse's generic event."""

import json
import os
import socket
import sys
from datetime import datetime, timezone

SOCKET_PATH = os.environ.get("AGENTPULSE_SOCKET", "/tmp/agentpulse.sock")


def phase_for(event, data):
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
    if event == "Notification" and data.get("notification_type") in ("idle_prompt", "permission_prompt"):
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


def main():
    data = json.load(sys.stdin)
    event = data.get("hook_event_name", "")
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
    )
    payload = {
        "session_id": data.get("session_id", "unknown"),
        "agent": agent,
        "cwd": data.get("cwd", os.getcwd()),
        "title": data.get("title"),
        "phase": phase,
        "detail": detail,
        "pid": os.getppid(),
        "tty": os.ttyname(0) if os.isatty(0) else None,
        "terminal_bundle_id": terminal_bundle_id(),
        "occurred_at": datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
    }
    encoded = json.dumps(payload, ensure_ascii=False).encode()
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
            client.settimeout(0.25)
            client.connect(SOCKET_PATH)
            client.sendall(encoded)
    except (FileNotFoundError, ConnectionRefusedError, TimeoutError):
        pass


if __name__ == "__main__":
    main()
