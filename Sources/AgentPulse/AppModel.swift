import AgentPulseCore
import AppKit
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    let repository = SessionRepository()
    @Published var useAttentionColor = true
    private var server: SocketServer?
    private var notchPanel: NotchPanelController?
    private var subscriptions: Set<AnyCancellable> = []

    init() {
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
