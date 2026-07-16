import importlib.util
import pathlib
import json
import tempfile
import unittest


SCRIPT = pathlib.Path(__file__).parents[2] / "scripts" / "agentpulse-hook.py"
SPEC = importlib.util.spec_from_file_location("agentpulse_hook", SCRIPT)
HOOK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(HOOK)


class HookTransportTests(unittest.TestCase):
    def test_session_start_reports_ready(self):
        self.assertEqual(HOOK.phase_for("SessionStart", {}), "ready")

    def transcript_file(self, entries):
        file = tempfile.NamedTemporaryFile(mode="w", suffix=".jsonl", delete=False)
        with file:
            for entry in entries:
                file.write(json.dumps(entry, ensure_ascii=False) + "\n")
        self.addCleanup(pathlib.Path(file.name).unlink, missing_ok=True)
        return file.name

    def test_current_prompt_survives_tool_lifecycle_events(self):
        self.assertEqual(
            HOOK.detail_for("UserPromptSubmit", {"prompt": "修复登录\n流程"}),
            "修复登录 流程",
        )
        self.assertIsNone(
            HOOK.detail_for("PreToolUse", {"tool_name": "Bash"}),
        )
        self.assertEqual(
            HOOK.title_for(
                "UserPromptSubmit",
                {"user_prompt": "优化会话内容展示"},
                "AgentPulse",
            ),
            "优化会话内容展示",
        )
        self.assertIsNone(
            HOOK.title_for(
                "PreToolUse",
                {"tool_name": "Bash", "title": "AgentPulse"},
                "AgentPulse",
            )
        )
        self.assertEqual(
            HOOK.title_for(
                "agent-turn-complete",
                {"input-messages": ["优化", "会话展示"]},
                "AgentPulse",
            ),
            "优化 会话展示",
        )

    def test_session_content_is_shortened(self):
        self.assertEqual(
            HOOK.concise_content("一" * 81),
            "一" * 77 + "...",
        )

    def test_tool_event_uses_latest_gpt_reply_from_current_transcript_turn(self):
        transcript = self.transcript_file([
            {"type": "event_msg", "payload": {
                "type": "user_message", "message": "修复动态展示"
            }},
            {"type": "event_msg", "payload": {
                "type": "agent_message",
                "phase": "commentary",
                "message": "我已经定位到更新链路，正在修改适配器。",
            }},
        ])
        self.assertEqual(
            HOOK.detail_for("PreToolUse", {
                "tool_name": "Bash", "transcript_path": transcript
            }),
            "我已经定位到更新链路，正在修改适配器。",
        )

    def test_new_turn_does_not_reuse_previous_gpt_reply(self):
        transcript = self.transcript_file([
            {"type": "event_msg", "payload": {
                "type": "agent_message", "message": "上一轮回答"
            }},
            {"type": "event_msg", "payload": {
                "type": "user_message", "message": "新问题"
            }},
        ])
        self.assertIsNone(HOOK.latest_assistant_message_from_transcript(transcript))
        self.assertIsNone(HOOK.detail_for(
            "PreToolUse", {"transcript_path": transcript}
        ))

    def test_interrupted_tool_call_pauses_session(self):
        self.assertEqual(
            HOOK.phase_for(
                "PostToolUse",
                {"tool_response": {"cancelled": True}},
            ),
            "paused",
        )

    def test_interrupted_app_server_turn_pauses_session(self):
        self.assertEqual(
            HOOK.phase_for(
                "turn/completed",
                {"params": {"turn": {"status": "interrupted"}}},
            ),
            "paused",
        )

    def test_app_server_interrupt_request_pauses_session_immediately(self):
        self.assertEqual(
            HOOK.phase_for(
                "turn/interrupt",
                {
                    "params": {
                        "threadId": "thread-interrupt-request",
                        "turnId": "turn-1",
                    }
                },
            ),
            "paused",
        )

    def test_completed_app_server_gpt_message_updates_detail(self):
        event = {
            "params": {
                "threadId": "thread-live-reply",
                "item": {
                    "type": "agentMessage",
                    "phase": "commentary",
                    "text": "已经完成状态链路检查，正在补充测试。",
                },
            },
        }
        self.assertEqual(HOOK.phase_for("item/completed", event), "running")
        self.assertEqual(
            HOOK.detail_for("item/completed", event),
            "已经完成状态链路检查，正在补充测试。",
        )

    def test_completed_app_server_tool_item_is_ignored(self):
        event = {"params": {"item": {"type": "commandExecution"}}}
        self.assertIsNone(HOOK.phase_for("item/completed", event))
        self.assertIsNone(HOOK.detail_for("item/completed", event))

    def test_unknown_interrupted_event_is_ignored(self):
        self.assertIsNone(HOOK.phase_for("UnknownEvent", {"status": "interrupted"}))

    def test_transport_endpoint_follows_platform(self):
        self.assertEqual(HOOK.transport_endpoint("darwin", {}), "/tmp/agentpulse.sock")
        self.assertEqual(HOOK.transport_endpoint("win32", {}), r"\\.\pipe\agentpulse")
        self.assertEqual(
            HOOK.transport_endpoint("win32", {"AGENTPULSE_SOCKET": "custom"}),
            "custom",
        )

    def test_windows_terminal_metadata(self):
        self.assertEqual(
            HOOK.terminal_process_name("win32", {"WT_SESSION": "session"}),
            "WindowsTerminal.exe",
        )
        self.assertEqual(
            HOOK.terminal_process_name("win32", {"TERM_PROGRAM": "vscode"}),
            "Code.exe",
        )


if __name__ == "__main__":
    unittest.main()
