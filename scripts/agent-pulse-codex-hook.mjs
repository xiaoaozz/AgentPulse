#!/usr/bin/env node

/**
 * Codex hook adapter for AgentPulse.
 *
 * Reads one Codex hook payload from stdin, translates it to AgentPulse's
 * agent-neutral event schema, and sends it over a local Unix socket. The hook
 * is deliberately fire-and-forget and never makes permission decisions.
 */

import net from "node:net";
import process from "node:process";
import { pathToFileURL } from "node:url";

const socketPath = process.env.AGENTPULSE_SOCKET || "/tmp/agentpulse.sock";
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

export function phaseFor(event, reviewer = "user") {
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
    case "PostToolUseFailure":
      return "warning";
    case "SessionEnd":
      return "offline";
    default:
      return null;
  }
}

function terminalBundleId() {
  const program = (process.env.TERM_PROGRAM || "").toLowerCase();
  return {
    apple_terminal: "com.apple.Terminal",
    "iterm.app": "com.googlecode.iterm2",
    ghostty: "com.mitchellh.ghostty",
    warpterminal: "dev.warp.Warp-Stable",
  }[program] || null;
}

function detailFor(event, payload, reviewer) {
  if (event === "PermissionRequest" && reviewer === "auto_review") {
    return payload.tool_name
      ? `Codex 正在代为审批：${payload.tool_name}`
      : "Codex 正在代为审批";
  }

  return (
    payload.last_assistant_message ||
    payload["last-assistant-message"] ||
    payload.assistant_message ||
    payload.message ||
    payload.error ||
    payload.tool_error ||
    payload.tool_name ||
    (event === "UserPromptSubmit" ? payload.prompt : null) ||
    null
  );
}

export function eventPayload(
  data,
  fallbackCwd = process.cwd(),
  options = {},
) {
  const event = data.hook_event_name || data.event || data.type || "";
  const reviewer = options.approvalReviewer || approvalReviewer;
  const phase = phaseFor(event, reviewer);
  if (!phase) return null;

  const cwd = data.cwd || fallbackCwd;
  const sessionId =
    data.session_id ||
    data.thread_id ||
    data["thread-id"] ||
    data.conversation_id ||
    "unknown";
  const projectName = cwd.split("/").filter(Boolean).at(-1) || cwd;

  return {
    session_id: sessionId,
    agent: agent === "codex" ? "Codex" : agent,
    cwd,
    title: data.title || projectName,
    phase,
    detail: detailFor(event, data, reviewer),
    pid: process.ppid,
    terminal_bundle_id: terminalBundleId(),
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
