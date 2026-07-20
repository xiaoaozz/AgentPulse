import AgentPulseCore
import AppKit
import Combine
import SwiftUI

@MainActor
final class NotchPanelController: NSObject {
    private let panel: NotchPanel
    private let repository: SessionRepository
    private var expanded = false
    private var statusItem: NSStatusItem?
    private var screenObserver: NotificationObserverToken?
    private var sessionsObserver: AnyCancellable?

    init(
        repository: SessionRepository,
        onJump: @escaping (AgentSession) -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.repository = repository
        panel = NotchPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        super.init()

        // Establish the AppKit window geometry before attaching a SwiftUI view.
        // Resizing an attached NSHostingView while another SwiftUI graph is
        // being initialized can trip AttributeGraph's re-entrancy precondition.
        placePanel(animated: false)

        let root = NotchView(
            repository: repository,
            onHoverChanged: { [weak self] expanded in self?.setExpanded(expanded) },
            onJump: onJump,
            onHide: { [weak self] in self?.hideNotch() },
            onQuit: onQuit
        )
        panel.contentView = NSHostingView(rootView: root)

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

    private func hideNotch() {
        expanded = false
        panel.orderOut(nil)

        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: "AgentPulse")
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
            button.toolTip = "显示 AgentPulse 刘海面板"
            button.target = self
            button.action = #selector(restoreNotch)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
    }

    @objc private func restoreNotch() {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
        expanded = false
        placePanel(animated: false)
        panel.orderFrontRegardless()
    }

    private func placePanel(animated: Bool) {
        guard let screen = targetScreen else { return }
        let size = panelSize(for: screen)
        let frame = NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        panel.setFrame(frame, display: true, animate: animated)
    }

    private var targetScreen: NSScreen? {
        NSScreen.screens.first(where: { screen in
            screen.auxiliaryTopLeftArea != nil && screen.auxiliaryTopRightArea != nil
        }) ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func panelSize(for screen: NSScreen) -> NSSize {
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
