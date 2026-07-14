import assert from "node:assert/strict";
import test from "node:test";

import {
  approvalReviewerForArgs,
  endpointForPlatform,
  eventPayload,
  phaseFor,
  projectNameForPath,
  terminalProcessName,
} from "../../scripts/agent-pulse-codex-hook.mjs";

test("transport endpoint follows the host platform and allows an override", () => {
  assert.equal(endpointForPlatform("darwin", {}), "/tmp/agentpulse.sock");
  assert.equal(endpointForPlatform("win32", {}), String.raw`\\.\pipe\agentpulse`);
  assert.equal(
    endpointForPlatform("win32", { AGENTPULSE_SOCKET: "custom-pipe" }),
    "custom-pipe",
  );
});

test("Windows paths and terminals produce Windows metadata", () => {
  assert.equal(projectNameForPath(String.raw`C:\work\AgentPulse`), "AgentPulse");
  assert.equal(
    terminalProcessName({ WT_SESSION: "session" }, "win32"),
    "WindowsTerminal.exe",
  );

  const payload = eventPayload(
    {
      hook_event_name: "PreToolUse",
      session_id: "windows-session",
      cwd: String.raw`C:\work\AgentPulse`,
    },
    undefined,
    { env: { WT_SESSION: "session" }, platform: "win32" },
  );
  assert.equal(payload.title, "AgentPulse");
  assert.equal(payload.terminal_process, "WindowsTerminal.exe");
});

test("Stop marks a lifecycle-hook session done", () => {
  const payload = eventPayload({
    hook_event_name: "Stop",
    session_id: "session-1",
    cwd: "/tmp/AgentPulse",
    last_assistant_message: "Finished",
  });

  assert.equal(payload.phase, "done");
  assert.equal(payload.session_id, "session-1");
  assert.equal(payload.detail, "Finished");
  assert.match(payload.occurred_at, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/);
});

test("an interrupted tool call pauses the session instead of leaving it running", () => {
  const payload = eventPayload({
    hook_event_name: "PostToolUse",
    session_id: "session-interrupted-tool",
    cwd: "/tmp/AgentPulse",
    tool_name: "Bash",
    tool_response: { cancelled: true },
  });

  assert.equal(payload.phase, "paused");
  assert.equal(payload.session_id, "session-interrupted-tool");
});

test("an interrupted app-server turn pauses the matching session", () => {
  const payload = eventPayload({
    method: "turn/completed",
    params: {
      threadId: "thread-interrupted",
      turn: { status: "interrupted" },
    },
  }, "/tmp/AgentPulse");

  assert.equal(payload.phase, "paused");
  assert.equal(payload.session_id, "thread-interrupted");
});

test("a failed app-server turn is a failed session", () => {
  const payload = eventPayload({
    method: "turn/completed",
    params: {
      threadId: "thread-failed",
      turn: { status: "failed", error: { message: "Model failed" } },
    },
  }, "/tmp/AgentPulse");

  assert.equal(payload.phase, "failed");
  assert.equal(payload.detail, "Model failed");
});

test("Codex notify payload uses its hyphenated fields", () => {
  const payload = eventPayload({
    type: "agent-turn-complete",
    "thread-id": "thread-1",
    cwd: "/tmp/AgentPulse",
    "last-assistant-message": "Finished from notify",
  });

  assert.equal(payload.phase, "done");
  assert.equal(payload.session_id, "thread-1");
  assert.equal(payload.detail, "Finished from notify");
});

test("unsupported events cannot overwrite a session as idle", () => {
  assert.equal(phaseFor("UnknownEvent"), null);
  assert.equal(phaseFor("UnknownEvent", "user", { status: "interrupted" }), null);
  assert.equal(eventPayload({ hook_event_name: "UnknownEvent" }), null);
});

test("manual approval remains a user action by default", () => {
  const payload = eventPayload({
    hook_event_name: "PermissionRequest",
    session_id: "session-manual",
    cwd: "/tmp/AgentPulse",
    tool_name: "Bash",
  });

  assert.equal(payload.phase, "waiting_for_action");
  assert.equal(payload.detail, "Bash");
});

test("auto-review approval remains running without requesting user action", () => {
  const payload = eventPayload(
    {
      hook_event_name: "PermissionRequest",
      session_id: "session-auto-review",
      cwd: "/tmp/AgentPulse",
      tool_name: "Bash",
    },
    undefined,
    { approvalReviewer: "auto_review" },
  );

  assert.equal(payload.phase, "running");
  assert.equal(payload.detail, "Codex 正在代为审批：Bash");
});

test("approval reviewer can be configured by flag or environment", () => {
  assert.equal(
    approvalReviewerForArgs(["node", "hook", "--approval-reviewer", "auto_review"]),
    "auto_review",
  );
  assert.equal(
    approvalReviewerForArgs(["node", "hook"], {
      AGENTPULSE_APPROVAL_REVIEWER: "auto_review",
    }),
    "auto_review",
  );
  assert.equal(
    approvalReviewerForArgs(
      ["node", "hook", "--approval-reviewer=user"],
      { AGENTPULSE_APPROVAL_REVIEWER: "auto_review" },
    ),
    "user",
  );
});
