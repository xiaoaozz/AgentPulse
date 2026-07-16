#!/usr/bin/env node

/**
 * Codex hook adapter for AgentPulse.
 *
 * Reads one Codex hook payload from stdin, translates it to AgentPulse's
 * agent-neutral event schema, and sends it over a local Unix socket or Windows
 * named pipe. The hook is deliberately fire-and-forget and never makes
 * permission decisions.
 */

import fs from "node:fs";
import { spawn } from "node:child_process";
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
const transcriptWatcherFlag = "--watch-transcript";

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
  // App Server clients emit this request as soon as the user cancels a turn.
  // Handle it directly instead of relying only on the later turn/completed
  // notification, which an event bridge may not forward.
  if (event === "turn/interrupt") {
    return "paused";
  }

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
      return "ready";
    case "UserPromptSubmit":
      return "preparing";
    case "PreToolUse":
    case "PostToolUse":
      return "running";
    case "item/completed":
      return data.params?.item?.type === "agentMessage" ? "running" : null;
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

function transcriptAssistantText(entry) {
  if (entry?.type === "event_msg" && entry.payload?.type === "agent_message") {
    return entry.payload.message;
  }

  if (entry?.type === "response_item" &&
      entry.payload?.type === "message" &&
      entry.payload?.role === "assistant") {
    return entry.payload.content
      ?.filter((item) => item?.type === "output_text")
      .map((item) => item.text)
      .filter((item) => typeof item === "string")
      .join(" ");
  }

  return null;
}

function isTranscriptUserMessage(entry) {
  return (entry?.type === "event_msg" && entry.payload?.type === "user_message") ||
    (entry?.type === "response_item" &&
      entry.payload?.type === "message" &&
      entry.payload?.role === "user");
}

export function latestAssistantMessageFromTranscript(path) {
  if (typeof path !== "string" || !path.trim()) return null;

  try {
    // Only inspect the tail. Hook invocations must remain fast even for long
    // sessions, and the latest user/assistant entries are appended to JSONL.
    const descriptor = fs.openSync(path, "r");
    try {
      const size = fs.fstatSync(descriptor).size;
      const length = Math.min(size, 1024 * 1024);
      const buffer = Buffer.alloc(length);
      fs.readSync(descriptor, buffer, 0, length, size - length);
      const lines = buffer.toString("utf8").split(/\r?\n/);

      for (let index = lines.length - 1; index >= 0; index -= 1) {
        if (!lines[index].trim()) continue;
        let entry;
        try { entry = JSON.parse(lines[index]); }
        catch { continue; }

        // Do not leak the previous turn's answer into a new turn that has not
        // emitted any assistant text yet.
        if (isTranscriptUserMessage(entry)) return null;
        const message = transcriptAssistantText(entry);
        if (message) return conciseContent(message);
      }
    } finally {
      fs.closeSync(descriptor);
    }
  } catch {
    // Transcript access is best-effort and must never break Codex hooks.
  }
  return null;
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

  if (event === "item/completed" && payload.params?.item?.type === "agentMessage") {
    return conciseContent(payload.params.item.text);
  }

  if (event === "PermissionRequest") {
    return conciseContent(payload.message || (
      payload.tool_name ? `等待确认：${payload.tool_name}` : "等待用户确认"
    ));
  }

  // Tool lifecycle payloads commonly only contain `tool_name`. Treating that
  // as session content replaces the user's prompt with values such as "Bash".
  // Codex does append assistant commentary to its transcript before invoking
  // the next tool hook, so use that text to refresh the visible session stage.
  const transcriptMessage = ["PreToolUse", "PostToolUse", "PreCompact"]
    .includes(event)
    ? latestAssistantMessageFromTranscript(payload.transcript_path)
    : null;
  return conciseContent(
    payload.last_assistant_message ||
    payload["last-assistant-message"] ||
    payload.assistant_message ||
    transcriptMessage ||
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

export function transcriptActionForLine(line) {
  let record;
  try {
    record = JSON.parse(line);
  } catch {
    return null;
  }

  if (record?.type !== "event_msg") return null;
  if (record.payload?.type === "turn_aborted") {
    return {
      phase: "paused",
      detail: "已由用户中止",
      occurredAt: record.timestamp,
    };
  }
  if (record.payload?.type === "task_complete") return { stop: true };
  return null;
}

function argumentValue(name, args = process.argv) {
  const index = args.indexOf(name);
  return index >= 0 ? args[index + 1] : null;
}

function sessionIdFor(data) {
  return data.session_id ||
    data.params?.threadId ||
    data.thread_id ||
    data["thread-id"] ||
    data.conversation_id ||
    "unknown";
}

function startTranscriptWatcher(data, fallbackCwd) {
  const transcriptPath = data.transcript_path;
  if (!transcriptPath || !process.argv[1]) return;

  let startOffset = 0;
  try {
    startOffset = fs.statSync(transcriptPath).size;
  } catch {
    // The transcript may be created just after the prompt hook fires.
  }

  const child = spawn(process.execPath, [
    process.argv[1],
    transcriptWatcherFlag,
    transcriptPath,
    "--start-offset",
    String(startOffset),
    "--session-id",
    sessionIdFor(data),
    "--cwd",
    data.cwd || fallbackCwd,
    "--source",
    agent,
  ], {
    detached: true,
    stdio: "ignore",
    env: process.env,
  });
  child.unref();
}

async function watchTranscript() {
  const transcriptPath = argumentValue(transcriptWatcherFlag);
  const sessionId = argumentValue("--session-id") || "unknown";
  const cwd = argumentValue("--cwd") || process.cwd();
  let position = Number(argumentValue("--start-offset")) || 0;
  let remainder = "";
  const deadline = Date.now() + 24 * 60 * 60 * 1000;

  while (Date.now() < deadline) {
    try {
      const info = await fs.promises.stat(transcriptPath);
      if (info.size < position) {
        position = 0;
        remainder = "";
      }

      if (info.size > position) {
        const handle = await fs.promises.open(transcriptPath, "r");
        try {
          while (position < info.size) {
            const length = Math.min(info.size - position, 256 * 1024);
            const buffer = Buffer.alloc(length);
            const { bytesRead } = await handle.read(buffer, 0, length, position);
            if (!bytesRead) break;
            position += bytesRead;
            remainder += buffer.subarray(0, bytesRead).toString("utf8");

            const lines = remainder.split("\n");
            remainder = lines.pop() || "";
            for (const line of lines) {
              const action = transcriptActionForLine(line);
              if (action?.stop) return;
              if (action?.phase === "paused") {
                await send({
                  session_id: sessionId,
                  agent: agent === "codex" ? "Codex" : agent,
                  cwd,
                  title: null,
                  phase: action.phase,
                  detail: action.detail,
                  occurred_at: action.occurredAt || new Date().toISOString(),
                });
                return;
              }
            }
          }
        } finally {
          await handle.close();
        }
      }
    } catch {
      // Missing or temporarily unavailable transcripts are retried quietly.
    }

    await new Promise((resolve) => setTimeout(resolve, 200));
  }
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
  const sessionId = sessionIdFor(data);
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
    occurred_at: new Date().toISOString(),
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
  if (process.argv.includes(transcriptWatcherFlag)) {
    await watchTranscript();
    return;
  }

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

  if (data.hook_event_name === "UserPromptSubmit") {
    startTranscriptWatcher(data, payload.cwd);
  }

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
