import Foundation

enum StatusSurfaceMode: String, CaseIterable, Identifiable {
    case floatingBall
    case notch

    var id: Self { self }

    var title: String {
        switch self {
        case .floatingBall: "悬浮球"
        case .notch: "刘海面板"
        }
    }
}
