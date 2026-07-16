import AgentPulseCore
import AppKit
import Foundation

enum TerminalNavigator {
    @MainActor
    static func jump(to session: AgentSession) {
        if let bundleId = session.terminalBundleId,
           let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
            app.activate(options: [.activateAllWindows])
            return
        }

        if let pid = session.pid,
           let app = NSRunningApplication(processIdentifier: pid) {
            app.activate(options: [.activateAllWindows])
            return
        }

        let candidates = [
            "com.openai.codex", "com.googlecode.iterm2", "com.mitchellh.ghostty",
            "dev.warp.Warp-Stable", "com.apple.Terminal"
        ]
        for bundleId in candidates {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
                app.activate(options: [.activateAllWindows])
                return
            }
        }
    }
}
