import importlib.util
import pathlib
import unittest


SCRIPT = pathlib.Path(__file__).parents[2] / "scripts" / "agentpulse-hook.py"
SPEC = importlib.util.spec_from_file_location("agentpulse_hook", SCRIPT)
HOOK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(HOOK)


class HookTransportTests(unittest.TestCase):
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
