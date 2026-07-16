#!/usr/bin/env node

/**
 * Codex hook adapter for AgentPulse.
 *
 * Reads one Codex hook payload from stdin, translates it to AgentPulse's
 * agent-neutral event schema, and sends it over a local Unix socket or Windows
 * named pipe. The hook is deliberately fire-and-forget and never makes
 * permission decisions.
 */

import net from "node:net";
import process from "node:process";
import { pathToFileURL } from "node:url";

export function endpointForPlatform(platform = process.platform, env = process.env) {
  return env.AGENTPULSE_SOCKET ||
    (platform === "win32" ? String.raw`\\.\pipe\agentpulse` : "/tmp/agentpulse.sock");
}

const socketPath = endpointForPlatform();
const sourceIndex = process.argv.indexOf("--source");
const agent = sourceIndex >= 0 ? process.argv[sourceIndex + 1] || "Codex" : "Codex";
const approvalReviewer = approvalReviewerForArgs(process.argv, process.env);

export function approvalReviewerForArgs(args, env = {}) {
  const index = args.indexOf("--approval-reviewer");
  const inline = args.find((value) => value.startsWith("--approval-reviewer="));
  const value =
    (index >= 0 ? args[index + 1] : null) ||
    inline?.slice("--approval-reviewer=".length) ||
    env.AGENTPULSE_APPROVAL_REVIEWER;

  return value === "auto_review" ? "auto_review" : "user";
}

function completionStatus(data) {
  return data.params?.turn?.status || data.turn?.status || data.status || null;
}

function wasInterrupted(data) {
  const status = completionStatus(data);
  if (["interrupted", "cancelled", "canceled", "aborted"].includes(status)) {
    return true;
  }

  const response = data.tool_response;
  return [data, response].some((value) =>
    value && typeof value === "object" &&
    ["interrupted", "cancelled", "canceled", "aborted"].some(
      (key) => value[key] === true,
    )
  );
}

export function phaseFor(event, reviewer = "user", data = {}) {
  const interruptibleEvents = [
    "PostToolUse",
    "PostToolUseFailure",
    "Stop",
    "agent-turn-complete",
    "turn/completed",
  ];
  if (interruptibleEvents.includes(event) && wasInterrupted(data)) {
    return "paused";
  }

  switch (event) {
    case "SessionStart":
      return "idle";
    case "UserPromptSubmit":
      return "preparing";
    case "PreToolUse":
    case "PostToolUse":
      return "running";
    case "PermissionRequest":
      return reviewer === "auto_review" ? "running" : "waiting_for_action";
    case "Stop":
    case "agent-turn-complete":
      return "done";
    case "turn/completed":
      return completionStatus(data) === "failed" ? "failed" : "done";
    case "PostToolUseFailure":
      return "warning";
    case "SessionEnd":
      return "offline";
    default:
      return null;
  }
}

function terminalBundleId(env = process.env) {
  const program = (env.TERM_PROGRAM || "").toLowerCase();
  return {
    apple_terminal: "com.apple.Terminal",
    "iterm.app": "com.googlecode.iterm2",
    ghostty: "com.mitchellh.ghostty",
    warpterminal: "dev.warp.Warp-Stable",
  }[program] || null;
}

export function terminalProcessName(env = process.env, platform = process.platform) {
  if (platform !== "win32") return null;
  if (env.WT_SESSION) return "WindowsTerminal.exe";

  const program = (env.TERM_PROGRAM || "").toLowerCase();
  return {
    vscode: "Code.exe",
    "warpterminal": "Warp.exe",
  }[program] || null;
}

export function projectNameForPath(cwd) {
  return cwd.split(/[\\/]/).filter(Boolean).at(-1) || cwd;
}

function detailFor(event, payload, reviewer) {
  if (event === "PermissionRequest" && reviewer === "auto_review") {
    return conciseContent(payload.tool_name
      ? `Codex 正在代为审批：${payload.tool_name}`
      : "Codex 正在代为审批");
  }

  if (event === "UserPromptSubmit") {
    return promptContent(payload);
  }

  if (event === "PermissionRequest") {
    return conciseContent(payload.message || (
      payload.tool_name ? `等待确认：${payload.tool_name}` : "等待用户确认"
    ));
  }

  // Tool lifecycle payloads commonly only contain `tool_name`. Treating that
  // as session content replaces the user's prompt with values such as "Bash".
  // Returning no detail lets the repository retain the current turn summary.
  return conciseContent(
    payload.last_assistant_message ||
    payload["last-assistant-message"] ||
    payload.assistant_message ||
    payload.error ||
    payload.params?.turn?.error?.message ||
    payload.tool_error ||
    (event !== "PreToolUse" && event !== "PostToolUse" ? payload.message : null) ||
    null
  );
}

function promptContent(payload) {
  return conciseContent(
    payload.prompt ||
    payload.user_prompt ||
    payload.userPrompt ||
    payload.input_messages ||
    payload["input-messages"] ||
    payload.input ||
    payload.message ||
    payload.params?.prompt ||
    payload.params?.input
  );
}

function titleFor(event, payload, projectName) {
  if (event === "UserPromptSubmit" || event === "agent-turn-complete") {
    return promptContent(payload) || conciseContent(payload.title) || null;
  }

  // Only the session-start event may use the project as a fallback title.
  // Sending it for every tool event would overwrite the current prompt.
  return event === "SessionStart"
    ? conciseContent(payload.title) || projectName
    : null;
}

export function conciseContent(value, maxLength = 80) {
  if (Array.isArray(value)) {
    value = value
      .map((item) => typeof item === "string" ? item : item?.text || item?.content)
      .filter((item) => typeof item === "string")
      .join(" ");
  }
  if (typeof value !== "string") return null;
  const normalized = value.replace(/\s+/g, " ").trim();
  if (!normalized) return null;

  const characters = Array.from(normalized);
  return characters.length <= maxLength
    ? normalized
    : `${characters.slice(0, maxLength - 3).join("")}...`;
}

export function eventPayload(
  data,
  fallbackCwd = process.cwd(),
  options = {},
) {
  const event =
    data.hook_event_name || data.event || data.type || data.method || "";
  const reviewer = options.approvalReviewer || approvalReviewer;
  const phase = phaseFor(event, reviewer, data);
  if (!phase) return null;

  const cwd = data.cwd || fallbackCwd;
  const sessionId =
    data.session_id ||
    data.params?.threadId ||
    data.thread_id ||
    data["thread-id"] ||
    data.conversation_id ||
    "unknown";
  const projectName = projectNameForPath(cwd);

  return {
    session_id: sessionId,
    agent: agent === "codex" ? "Codex" : agent,
    cwd,
    title: titleFor(event, data, projectName),
    phase,
    detail: detailFor(event, data, reviewer),
    pid: process.ppid,
    terminal_bundle_id: terminalBundleId(options.env),
    terminal_process: terminalProcessName(options.env, options.platform),
    occurred_at: new Date().toISOString().replace(/\.\d{3}Z$/, "Z"),
  };
}

function send(payload) {
  return new Promise((resolve) => {
    const client = net.createConnection({ path: socketPath });
    const finish = () => {
      client.destroy();
      resolve();
    };
    client.setTimeout(300, finish);
    client.once("error", finish);
    client.once("connect", () => {
      client.end(JSON.stringify(payload), resolve);
    });
  });
}

async function main() {
  let input = "";
  process.stdin.setEncoding("utf8");
  for await (const chunk of process.stdin) input += chunk;

  // Lifecycle hooks send JSON on stdin. Codex's legacy `notify` command sends
  // the same kind of information as a single JSON command-line argument.
  const argument = process.argv.slice(2).find((value) => value.trim().startsWith("{"));
  const encoded = input.trim() || argument;
  if (!encoded) return;

  const data = JSON.parse(encoded);
  const payload = eventPayload(data);
  if (!payload) return;

  await send(payload);

  // Stop-family hooks require JSON output on successful completion. An empty
  // object acknowledges the hook without changing Codex's control flow.
  if (data.hook_event_name === "Stop" || data.hook_event_name === "SubagentStop") {
    process.stdout.write("{}");
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch(() => {
    // Monitoring must never block or fail the Codex lifecycle hook.
    process.exitCode = 0;
  });
}
