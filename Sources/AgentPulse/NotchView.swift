import AgentPulseCore
import AppKit
import SwiftUI

struct NotchView: View {
    private static let expansionDelay = Duration.milliseconds(180)
    private static let collapseDelay = Duration.milliseconds(120)

    @ObservedObject var repository: SessionRepository
    let onHoverChanged: (Bool) -> Void
    let onJump: (AgentSession) -> Void
    let onQuit: () -> Void
    @State private var expanded = false
    @State private var hoverTransitionTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            collapsedContent
                .frame(height: 38)
            if expanded {
                Divider().overlay(Color.white.opacity(0.12))
                VStack(spacing: 0) {
                    expandedToolbar
                    Divider().overlay(Color.white.opacity(0.08))
                    expandedContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider().overlay(Color.white.opacity(0.10))
                    expandedFooter
                }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .foregroundStyle(.white)
        .background(Color.black)
        .clipShape(
            UnevenRoundedRectangle(
                cornerRadii: .init(
                    topLeading: 0,
                    bottomLeading: expanded ? 18 : 12,
                    bottomTrailing: expanded ? 18 : 12,
                    topTrailing: 0
                ),
                style: .continuous
            )
        )
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.18), value: expanded)
        .onHover { hovering in
            scheduleHoverTransition(expanded: hovering)
        }
        .onDisappear {
            hoverTransitionTask?.cancel()
        }
    }

    /// A brief dwell distinguishes an intentional visit from a pointer merely
    /// crossing the menu bar or the notch while moving between applications.
    private func scheduleHoverTransition(expanded target: Bool) {
        hoverTransitionTask?.cancel()

        guard expanded != target else { return }
        let delay = target ? Self.expansionDelay : Self.collapseDelay
        hoverTransitionTask = Task { @MainActor in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            expanded = target
            onHoverChanged(target)
        }
    }

    private var collapsedContent: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            HStack(spacing: 0) {
            Text(statusText(at: context.date))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(primaryPhase(at: context.date).displayColor)
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
        }
        .padding(.horizontal, 12)
    }

    private var expandedToolbar: some View {
        HStack {
            Spacer()
            Button {
                repository.clearCompleted()
            } label: {
                Label("清除终态", systemImage: "trash")
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(repository.clearableCount > 0 ? 0.68 : 0.28))
            .disabled(repository.clearableCount == 0)
            .help("清除所有已中止、已完成、警告和失败的会话")
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
    }

    private var expandedFooter: some View {
        HStack {
            Spacer()
            Button(action: onQuit) {
                Image(systemName: "power")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .background(.red.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red.opacity(0.9))
            .help("退出 AgentPulse")
        }
        .padding(.trailing, 12)
        .frame(height: 40)
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
                    HStack(spacing: 0) {
                        Button { onJump(session) } label: {
                            HStack(spacing: 11) {
                                SessionStatusIndicator(phase: session.phase, diameter: 10)
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
                            .padding(.leading, 14)
                            .padding(.trailing, session.phase.isClearable ? 8 : 14)
                            .frame(maxWidth: .infinity, minHeight: 64)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("跳转到 \(session.title)")

                        if session.phase.isClearable {
                            Button {
                                repository.removeCompletedSession(id: session.id)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .semibold))
                                    .frame(width: 26, height: 26)
                                    .background(.white.opacity(0.07), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.white.opacity(0.58))
                            .padding(.trailing, 10)
                            .help("删除这个已完成会话")
                            .accessibilityLabel("删除 \(session.title)")
                        }
                    }
                }
            }
        }
    }

    private func primaryPhase(at date: Date) -> SessionPhase {
        repository.globalPhase(at: date)
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

    private func statusText(at date: Date) -> String {
        switch primaryPhase(at: date) {
        case .preparing: "Preparing..."
        case .running: "Running..."
        case .waitingForAction: "Action"
        case .done: "Done"
        case .warning: "Warning"
        case .failed: "Failed"
        case .paused: "Paused"
        case .offline: "Offline"
        case .ready: "Ready"
        }
    }

    private func sessionHeadline(for session: AgentSession) -> String {
        session.title
    }

    private func sessionSubtitle(for session: AgentSession) -> String {
        session.detail ?? session.phase.meaning
    }
}
