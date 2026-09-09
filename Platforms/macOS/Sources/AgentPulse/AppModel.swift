import AgentPulseCore
import AppKit
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    private static let statusSurfaceModeKey = "statusSurfaceMode"

    let repository = SessionRepository()
    @Published var useAttentionColor = true
    @Published var statusSurfaceMode: StatusSurfaceMode {
        didSet {
            UserDefaults.standard.set(statusSurfaceMode.rawValue, forKey: Self.statusSurfaceModeKey)
            notchPanel?.setMode(statusSurfaceMode)
        }
    }
    private var server: SocketServer?
    private var notchPanel: NotchPanelController?
    private var subscriptions: Set<AnyCancellable> = []

    init() {
        statusSurfaceMode = UserDefaults.standard.string(forKey: Self.statusSurfaceModeKey)
            .flatMap(StatusSurfaceMode.init(rawValue:)) ?? .floatingBall
        let repository = repository
        repository.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &subscriptions)
        server = SocketServer { event in
            Task { @MainActor in repository.receive(event) }
        } onError: { error in
            Task { @MainActor in repository.report(error) }
        }
        server?.start()

        // AppModel is created while SwiftUI's AttributeGraph is updating the
        // app scene. Creating another NSHostingView synchronously here can
        // re-enter that graph and abort the process. Start the notch surface on
        // the next main-run-loop turn, after the current update has committed.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.notchPanel = NotchPanelController(
                repository: repository,
                mode: self.statusSurfaceMode,
                onModeChanged: { [weak self] mode in self?.statusSurfaceMode = mode },
                onJump: { session in TerminalNavigator.jump(to: session) },
                onQuit: { NSApplication.shared.terminate(nil) }
            )
        }
    }

    func jump(to session: AgentSession) {
        TerminalNavigator.jump(to: session)
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
    }

}
