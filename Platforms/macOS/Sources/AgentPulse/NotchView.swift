import AgentPulseCore
import AppKit
import SwiftUI

struct NotchView: View {
    private static let expansionDelay = Duration.milliseconds(180)
    private static let collapseDelay = Duration.milliseconds(120)

    @ObservedObject var repository: SessionRepository
    let mode: StatusSurfaceMode
    let onExpandedChanged: (Bool) -> Void
    let onDragEnded: () -> Void
    let onJump: (AgentSession) -> Void
    let onHide: () -> Void
    let onQuit: () -> Void
    @State private var expanded = false
    @State private var hoverTransitionTask: Task<Void, Never>?
    @State private var footerHint: String?
    @State private var floatingBallHovered = false

    @ViewBuilder
    var body: some View {
        switch mode {
        case .notch:
            notchBody
        case .floatingBall:
            floatingBody
        }
    }

    private var notchBody: some View {
        VStack(spacing: 0) {
            notchCollapsedContent
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

    private var floatingBody: some View {
        VStack(spacing: 0) {
            floatingHeader
            if expanded {
                Divider().overlay(Color.white.opacity(0.12))
                expandedToolbar
                Divider().overlay(Color.white.opacity(0.08))
                expandedContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider().overlay(Color.white.opacity(0.10))
                expandedFooter
            }
        }
        .foregroundStyle(.white)
        .background {
            if expanded {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(hex: 0x18191C).opacity(0.98))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: expanded ? 18 : 22, style: .continuous))
        .overlay {
            if expanded {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.14), lineWidth: 0.75)
            }
        }
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.18), value: expanded)
    }

    private var floatingHeader: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            HStack(spacing: 10) {
                if expanded {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(statusText(at: context.date))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(primaryPhase(at: context.date).displayColor)
                        Text("\(repository.ongoingCount) 个进行中会话")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer()
                }

                ZStack {
                    Circle()
                        .fill(Color(hex: 0x24262B).opacity(0.98))
                        .overlay {
                            Circle()
                                .stroke(
                                    primaryPhase(at: context.date).displayColor.opacity(0.72),
                                    lineWidth: 1.25
                                )
                        }
                        .frame(width: 34, height: 34)
                        .shadow(
                            color: primaryPhase(at: context.date).displayColor.opacity(0.22),
                            radius: floatingBallHovered ? 7 : 4
                        )

                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                }
                .overlay(alignment: .topTrailing) {
                    if repository.ongoingCount > 0 {
                        Text("\(min(repository.ongoingCount, 99))")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.black)
                            .padding(.horizontal, 3)
                            .frame(minWidth: 14, minHeight: 14)
                            .background(primaryPhase(at: context.date).displayColor, in: Capsule())
                            .overlay { Capsule().stroke(.black.opacity(0.30), lineWidth: 0.5) }
                            .offset(x: 1, y: -1)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if repository.ongoingCount == 0 {
                        Circle()
                            .fill(primaryPhase(at: context.date).displayColor)
                            .frame(width: 7, height: 7)
                            .overlay { Circle().stroke(.black.opacity(0.65), lineWidth: 1) }
                            .offset(x: -1, y: -1)
                    }
                }
                .scaleEffect(floatingBallHovered ? 1.045 : 1)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
                .overlay {
                    FloatingBallInteractionView(
                        onClick: toggleFloatingPanel,
                        onDragEnded: onDragEnded
                    )
                    .clipShape(Circle())
                }
                .onHover { floatingBallHovered = $0 }
                .help(expanded ? "拖动悬浮球；点击收起" : "拖动悬浮球；点击展开")
                .accessibilityLabel(expanded ? "收起 AgentPulse" : "展开 AgentPulse")
            }
        }
        .padding(.leading, expanded ? 14 : 0)
        .frame(height: expanded ? 48 : 44)
        .animation(.easeOut(duration: 0.14), value: floatingBallHovered)
    }

    private func toggleFloatingPanel() {
        expanded.toggle()
        onExpandedChanged(expanded)
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
            onExpandedChanged(target)
        }
    }

    private var notchCollapsedContent: some View {
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
            .help("清除所有已离线、已中止、已完成、警告和失败的会话")
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
    }

    private var expandedFooter: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 6) {
                Spacer()
                Button(action: minimizeToFloatingBall) {
                    Image(systemName: "circle.dotted.circle")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .background(.white.opacity(0.07), in: Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.68))
                .help("收起为悬浮球")
                .accessibilityLabel("收起为悬浮球")
                .onHover { hovering in
                    updateFooterHint("收起", hovering: hovering)
                }

                Button(action: onQuit) {
                    Image(systemName: "power")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .background(.red.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red.opacity(0.9))
                .help("退出 AgentPulse")
                .accessibilityLabel("退出")
                .onHover { hovering in
                    updateFooterHint("退出", hovering: hovering)
                }
            }

            if let footerHint {
                Text(footerHint)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.88))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.12), in: Capsule())
                    .offset(y: -26)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottomTrailing)))
                    .allowsHitTesting(false)
            }
        }
        .padding(.trailing, 12)
        .frame(height: 40)
        .animation(.easeOut(duration: 0.12), value: footerHint)
    }

    private func updateFooterHint(_ text: String, hovering: Bool) {
        if hovering {
            footerHint = text
        } else if footerHint == text {
            footerHint = nil
        }
    }

    private func minimizeToFloatingBall() {
        hoverTransitionTask?.cancel()
        expanded = false
        onExpandedChanged(false)
        onHide()
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
                            .help("删除这条终态会话")
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

private struct FloatingBallInteractionView: NSViewRepresentable {
    let onClick: () -> Void
    let onDragEnded: () -> Void

    func makeNSView(context: Context) -> FloatingBallInteractionNSView {
        FloatingBallInteractionNSView(onClick: onClick, onDragEnded: onDragEnded)
    }

    func updateNSView(_ nsView: FloatingBallInteractionNSView, context: Context) {
        nsView.onClick = onClick
        nsView.onDragEnded = onDragEnded
    }
}

private final class FloatingBallInteractionNSView: NSView {
    var onClick: () -> Void
    var onDragEnded: () -> Void
    private var mouseDownLocation: NSPoint?
    private var windowOriginAtMouseDown: NSPoint?
    private var didDrag = false

    init(onClick: @escaping () -> Void, onDragEnded: @escaping () -> Void) {
        self.onClick = onClick
        self.onDragEnded = onDragEnded
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        mouseDownLocation = NSEvent.mouseLocation
        windowOriginAtMouseDown = window.frame.origin
        didDrag = false
        NSCursor.closedHand.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window,
              let mouseDownLocation,
              let windowOriginAtMouseDown else { return }

        let currentLocation = NSEvent.mouseLocation
        let deltaX = currentLocation.x - mouseDownLocation.x
        let deltaY = currentLocation.y - mouseDownLocation.y
        didDrag = didDrag || hypot(deltaX, deltaY) >= 3

        window.setFrameOrigin(
            NSPoint(
                x: windowOriginAtMouseDown.x + deltaX,
                y: windowOriginAtMouseDown.y + deltaY
            )
        )
    }

    override func mouseUp(with event: NSEvent) {
        let wasDragged = didDrag
        mouseDownLocation = nil
        windowOriginAtMouseDown = nil
        didDrag = false
        NSCursor.openHand.set()

        onDragEnded()
        if !wasDragged {
            onClick()
        }
    }
}
