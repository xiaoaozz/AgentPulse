import AgentPulseCore
import AppKit
import Combine
import SwiftUI

@MainActor
final class NotchPanelController: NSObject {
    private static let floatingBallSize: CGFloat = 44
    private static let floatingBallRadius: CGFloat = floatingBallSize / 2
    private static let floatingAnchorXKey = "floatingBallAnchorX"
    private static let floatingAnchorYKey = "floatingBallAnchorY"

    private let panel: NotchPanel
    private let repository: SessionRepository
    private let onModeChanged: (StatusSurfaceMode) -> Void
    private let onJump: (AgentSession) -> Void
    private let onQuit: () -> Void
    private var mode: StatusSurfaceMode
    private var expanded = false
    private var floatingAnchor: NSPoint?
    private var screenObserver: NotificationObserverToken?
    private var sessionsObserver: AnyCancellable?

    init(
        repository: SessionRepository,
        mode: StatusSurfaceMode,
        onModeChanged: @escaping (StatusSurfaceMode) -> Void,
        onJump: @escaping (AgentSession) -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.repository = repository
        self.mode = mode
        self.onModeChanged = onModeChanged
        self.onJump = onJump
        self.onQuit = onQuit
        panel = NotchPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = mode == .floatingBall
        panel.hidesOnDeactivate = false
        panel.isMovable = mode == .floatingBall
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        super.init()

        // Establish the AppKit window geometry before attaching a SwiftUI view.
        // Resizing an attached NSHostingView while another SwiftUI graph is
        // being initialized can trip AttributeGraph's re-entrancy precondition.
        placePanel(animated: false)

        installRootView()

        sessionsObserver = repository.$sessions
            .map(\.count)
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self, self.expanded else { return }
                self.placePanel(animated: true)
            }

        screenObserver = NotificationObserverToken(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.placePanel(animated: false) }
            }
        )

        panel.orderFrontRegardless()
    }

    func setMode(_ mode: StatusSurfaceMode) {
        guard self.mode != mode else { return }
        self.mode = mode
        expanded = false
        panel.hasShadow = mode == .floatingBall
        panel.isMovable = mode == .floatingBall
        installRootView()
        placePanel(animated: true)
        panel.orderFrontRegardless()
    }

    private func installRootView() {
        let root = NotchView(
            repository: repository,
            mode: mode,
            onExpandedChanged: { [weak self] expanded in self?.setExpanded(expanded) },
            onDragEnded: { [weak self] in self?.finishDraggingFloatingBall() },
            onJump: onJump,
            onHide: { [weak self] in self?.minimizeToFloatingBall() },
            onQuit: onQuit
        )
        panel.contentView = NSHostingView(rootView: root)
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver.value)
        }
    }

    private func setExpanded(_ value: Bool) {
        guard expanded != value else { return }
        expanded = value
        placePanel(animated: true)
    }

    private func minimizeToFloatingBall() {
        expanded = false
        if mode == .floatingBall {
            placePanel(animated: true)
            panel.orderFrontRegardless()
        } else {
            onModeChanged(.floatingBall)
        }
    }

    private func placePanel(animated: Bool) {
        guard let screen = targetScreen else { return }
        let size = panelSize(for: screen)
        let frame: NSRect
        switch mode {
        case .notch:
            frame = NSRect(
                x: screen.frame.midX - size.width / 2,
                y: screen.frame.maxY - size.height,
                width: size.width,
                height: size.height
            )
        case .floatingBall:
            let anchor = clampedFloatingAnchor(for: screen)
            frame = clamp(floatingFrame(size: size, anchor: anchor), to: screen)
            floatingAnchor = NSPoint(
                x: frame.maxX - floatingAnchorInset,
                y: frame.maxY - floatingAnchorInset
            )
        }
        panel.setFrame(frame, display: true, animate: animated)
    }

    private func finishDraggingFloatingBall() {
        guard mode == .floatingBall else { return }
        let draggedAnchor = NSPoint(
            x: panel.frame.maxX - floatingAnchorInset,
            y: panel.frame.maxY - floatingAnchorInset
        )
        floatingAnchor = draggedAnchor
        guard let screen = targetScreen else { return }
        floatingAnchor = clamp(draggedAnchor, to: screen)
        placePanel(animated: false)
        guard let floatingAnchor else { return }
        UserDefaults.standard.set(floatingAnchor.x, forKey: Self.floatingAnchorXKey)
        UserDefaults.standard.set(floatingAnchor.y, forKey: Self.floatingAnchorYKey)
    }

    private func clampedFloatingAnchor(for screen: NSScreen) -> NSPoint {
        if let floatingAnchor {
            return clamp(floatingAnchor, to: screen)
        }
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.floatingAnchorXKey) != nil,
           defaults.object(forKey: Self.floatingAnchorYKey) != nil {
            return clamp(
                NSPoint(
                    x: defaults.double(forKey: Self.floatingAnchorXKey),
                    y: defaults.double(forKey: Self.floatingAnchorYKey)
                ),
                to: screen
            )
        }
        return NSPoint(x: screen.visibleFrame.maxX - 30, y: screen.visibleFrame.maxY - 56)
    }

    private func clamp(_ point: NSPoint, to screen: NSScreen) -> NSPoint {
        let bounds = screen.visibleFrame.insetBy(dx: 26, dy: 26)
        return NSPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
    }

    private func clamp(_ frame: NSRect, to screen: NSScreen) -> NSRect {
        let bounds = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        var result = frame
        result.origin.x = min(max(result.minX, bounds.minX), bounds.maxX - result.width)
        result.origin.y = min(max(result.minY, bounds.minY), bounds.maxY - result.height)
        return result
    }

    private func floatingFrame(size: NSSize, anchor: NSPoint) -> NSRect {
        NSRect(
            x: anchor.x - size.width + floatingAnchorInset,
            y: anchor.y - size.height + floatingAnchorInset,
            width: size.width,
            height: size.height
        )
    }

    private var floatingAnchorInset: CGFloat {
        expanded ? 24 : Self.floatingBallRadius
    }

    private var targetScreen: NSScreen? {
        if mode == .floatingBall, let floatingAnchor,
           let screen = NSScreen.screens.first(where: { $0.frame.contains(floatingAnchor) }) {
            return screen
        }
        return NSScreen.screens.first(where: { screen in
            screen.auxiliaryTopLeftArea != nil && screen.auxiliaryTopRightArea != nil
        }) ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func panelSize(for screen: NSScreen) -> NSSize {
        if mode == .floatingBall {
            guard expanded else {
                return NSSize(width: Self.floatingBallSize, height: Self.floatingBallSize)
            }
            let displayedSessionCount = min(repository.sessions.count, 5)
            let height = displayedSessionCount == 0
                ? CGFloat(186)
                : 125 + CGFloat(displayedSessionCount * 65)
            return NSSize(width: 380, height: height)
        }

        let detectedNotchWidth: CGFloat = {
            guard let left = screen.auxiliaryTopLeftArea,
                  let right = screen.auxiliaryTopRightArea else { return 190 }
            return max(0, right.minX - left.maxX)
        }()
        let collapsedWidth = max(290, detectedNotchWidth + 220)
        let displayedSessionCount = min(repository.sessions.count, 5)
        let expandedHeight = displayedSessionCount == 0
            ? 178
            : 113 + CGFloat(displayedSessionCount * 65)
        return expanded
            ? NSSize(width: max(380, collapsedWidth), height: expandedHeight)
            : NSSize(width: collapsedWidth, height: 38)
    }
}

/// NotificationCenter's opaque observer token predates Swift concurrency.
/// The token is only created on the main actor and is safely removed in deinit.
private final class NotificationObserverToken: @unchecked Sendable {
    let value: NSObjectProtocol

    init(_ value: NSObjectProtocol) {
        self.value = value
    }
}

private final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
