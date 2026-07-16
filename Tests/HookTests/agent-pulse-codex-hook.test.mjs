import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import {
  approvalReviewerForArgs,
  conciseContent,
  endpointForPlatform,
  eventPayload,
  latestAssistantMessageFromTranscript,
  phaseFor,
  projectNameForPath,
  terminalProcessName,
  transcriptActionForLine,
} from "../../scripts/agent-pulse-codex-hook.mjs";

function transcriptFile(entries) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "agentpulse-transcript-"));
  const file = path.join(directory, "session.jsonl");
  fs.writeFileSync(file, `${entries.map(JSON.stringify).join("\n")}\n`);
  return file;
}

test("session content is flattened and shortened for the list", () => {
  assert.equal(conciseContent("  修复登录\n流程  "), "修复登录 流程");
  assert.equal(conciseContent("一".repeat(81)), `${"一".repeat(77)}...`);
});

test("the current prompt survives tool lifecycle events", () => {
  const prompt = eventPayload({
    hook_event_name: "UserPromptSubmit",
    session_id: "session-content",
    cwd: "/tmp/AgentPulse",
    prompt: "请帮我修复\n会话列表显示",
  });
  const tool = eventPayload({
    hook_event_name: "PreToolUse",
    session_id: "session-content",
    cwd: "/tmp/AgentPulse",
    tool_name: "Bash",
    title: "AgentPulse",
  });

  assert.equal(prompt.detail, "请帮我修复 会话列表显示");
  assert.equal(prompt.title, "请帮我修复 会话列表显示");
  assert.equal(tool.detail, null);
  assert.equal(tool.title, null);
});

test("tool lifecycle events show the latest GPT reply from the current transcript turn", () => {
  const transcriptPath = transcriptFile([
    { type: "event_msg", payload: { type: "user_message", message: "修复动态展示" } },
    { type: "event_msg", payload: {
      type: "agent_message",
      phase: "commentary",
      message: "我已经定位到更新链路，正在修改适配器。",
    } },
  ]);
  const payload = eventPayload({
    hook_event_name: "PreToolUse",
    session_id: "live-transcript",
    cwd: "/tmp/AgentPulse",
    transcript_path: transcriptPath,
    tool_name: "Bash",
  });

  assert.equal(payload.title, null);
  assert.equal(payload.detail, "我已经定位到更新链路，正在修改适配器。");
});

test("a new turn never reuses the preceding turn's GPT reply", () => {
  const transcriptPath = transcriptFile([
    { type: "event_msg", payload: { type: "agent_message", message: "上一轮回答" } },
    { type: "event_msg", payload: { type: "user_message", message: "新问题" } },
  ]);

  assert.equal(latestAssistantMessageFromTranscript(transcriptPath), null);
  assert.equal(eventPayload({
    hook_event_name: "PreToolUse",
    session_id: "new-turn",
    cwd: "/tmp/AgentPulse",
    transcript_path: transcriptPath,
  }).detail, null);
});

test("assistant response items are supported as a transcript fallback", () => {
  const transcriptPath = transcriptFile([
    { type: "response_item", payload: {
      type: "message",
      role: "user",
      content: [{ type: "input_text", text: "检查状态" }],
    } },
    { type: "response_item", payload: {
      type: "message",
      role: "assistant",
      content: [{ type: "output_text", text: "正在检查会话状态。" }],
    } },
  ]);

  assert.equal(
    latestAssistantMessageFromTranscript(transcriptPath),
    "正在检查会话状态。",
  );
});

test("Codex notify input messages become the session title", () => {
  const payload = eventPayload({
    type: "agent-turn-complete",
    "thread-id": "notify-content",
    cwd: "/tmp/AgentPulse",
    "input-messages": ["帮我优化", "会话内容展示"],
    "last-assistant-message": "已经完成修改",
  });

  assert.equal(payload.title, "帮我优化 会话内容展示");
  assert.equal(payload.detail, "已经完成修改");
});

test("alternate prompt fields can provide the session title", () => {
  const payload = eventPayload({
    hook_event_name: "UserPromptSubmit",
    session_id: "alternate-prompt",
    cwd: "/tmp/AgentPulse",
    user_prompt: "优化会话内容展示",
  });

  assert.equal(payload.title, "优化会话内容展示");
  assert.equal(payload.detail, "优化会话内容展示");
});

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
  assert.equal(payload.title, null);
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

test("an app-server interrupt request immediately pauses the matching session", () => {
  const payload = eventPayload({
    method: "turn/interrupt",
    params: {
      threadId: "thread-interrupt-request",
      turnId: "turn-1",
    },
  }, "/tmp/AgentPulse");

  assert.equal(payload.phase, "paused");
  assert.equal(payload.session_id, "thread-interrupt-request");
});

test("a transcript turn_aborted record pauses a lifecycle-hook session", () => {
  assert.deepEqual(transcriptActionForLine(JSON.stringify({
    timestamp: "2026-07-16T11:12:55.447Z",
    type: "event_msg",
    payload: { type: "turn_aborted" },
  })), {
    phase: "paused",
    detail: "已由用户中止",
    occurredAt: "2026-07-16T11:12:55.447Z",
  });
  assert.deepEqual(transcriptActionForLine(JSON.stringify({
    type: "event_msg",
    payload: { type: "task_complete" },
  })), { stop: true });
  assert.equal(transcriptActionForLine("not json"), null);
});

test("each completed app-server GPT message refreshes session detail without changing its title", () => {
  const payload = eventPayload({
    method: "item/completed",
    params: {
      threadId: "thread-live-reply",
      item: {
        type: "agentMessage",
        id: "message-1",
        phase: "commentary",
        text: "我已经定位到状态更新链路，接下来补充测试。",
      },
    },
  }, "/tmp/AgentPulse");

  assert.equal(payload.phase, "running");
  assert.equal(payload.session_id, "thread-live-reply");
  assert.equal(payload.title, null);
  assert.equal(payload.detail, "我已经定位到状态更新链路，接下来补充测试。");
});

test("non-message app-server items do not overwrite session content", () => {
  assert.equal(eventPayload({
    method: "item/completed",
    params: {
      threadId: "thread-tool",
      item: { type: "commandExecution", id: "command-1" },
    },
  }, "/tmp/AgentPulse"), null);
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

test("SessionStart reports ready and unsupported events cannot overwrite it", () => {
  assert.equal(phaseFor("SessionStart"), "ready");
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
  assert.equal(payload.detail, "等待确认：Bash");
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
