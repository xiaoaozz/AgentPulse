import AgentPulseCore
import AppKit
import SwiftUI

struct NotchView: View {
    @ObservedObject var repository: SessionRepository
    let onHoverChanged: (Bool) -> Void
    let onJump: (AgentSession) -> Void
    let onQuit: () -> Void
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 0) {
            collapsedContent
                .frame(height: 38)
            if expanded {
                Divider().overlay(Color.white.opacity(0.12))
                VStack(spacing: 0) {
                    expandedContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider().overlay(Color.white.opacity(0.10))
                    Button("退出 AgentPulse", action: onQuit)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.red.opacity(0.9))
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .contentShape(Rectangle())
                        .help("退出 AgentPulse")
                }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .foregroundStyle(.white)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: expanded ? 18 : 14, style: .continuous))
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.18), value: expanded)
        .onHover { hovering in
            expanded = hovering
            onHoverChanged(hovering)
        }
    }

    private var collapsedContent: some View {
        HStack(spacing: 0) {
            Text(statusText)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(primaryPhase.displayColor)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .frame(width: 92, alignment: .trailing)

            Spacer(minLength: detectedNotchWidth)

            HStack(spacing: 5) {
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
                Text("\(repository.ongoingCount)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .frame(width: 92, alignment: .leading)
        }
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private var expandedContent: some View {
        if recentSessions.isEmpty {
            Text("等待 Agent 会话")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
        } else {
            VStack(spacing: 0) {
                ForEach(Array(recentSessions.enumerated()), id: \.element.id) { index, session in
                    if index > 0 {
                        Divider().overlay(Color.white.opacity(0.08))
                    }
                    Button { onJump(session) } label: {
                        HStack(spacing: 11) {
                            Circle().fill(session.phase.displayColor).frame(width: 10, height: 10)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(sessionHeadline(for: session))
                                        .font(.system(size: 13, weight: .semibold))
                                        .lineLimit(1)
                                    Spacer()
                                    Text(session.agent).font(.caption2).foregroundStyle(.white.opacity(0.55))
                                }
                                Text(sessionSubtitle(for: session))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.65))
                                    .lineLimit(1)
                            }
                            Image(systemName: "arrow.up.forward.app")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("跳转到 \(session.title)")
                }
            }
        }
    }

    private var primaryPhase: SessionPhase {
        repository.sessions.first?.phase ?? .idle
    }

    private var recentSessions: [AgentSession] {
        Array(repository.sessions.sorted { $0.updatedAt > $1.updatedAt }.prefix(5))
    }

    private var detectedNotchWidth: CGFloat {
        guard let screen = NSScreen.screens.first(where: {
            $0.auxiliaryTopLeftArea != nil && $0.auxiliaryTopRightArea != nil
        }), let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea else { return 190 }
        return max(150, right.minX - left.maxX)
    }

    private var statusText: String {
        switch primaryPhase {
        case .preparing: "Preparing..."
        case .running: "Running..."
        case .waitingForAction: "Action"
        case .done: "Done"
        case .warning: "Warning"
        case .failed: "Failed"
        case .paused: "Paused"
        case .offline: "Offline"
        case .idle: "Idle"
        }
    }

    private func sessionHeadline(for session: AgentSession) -> String {
        session.detail ?? session.title
    }

    private func sessionSubtitle(for session: AgentSession) -> String {
        session.detail == nil ? session.phase.meaning : session.title
    }
}
