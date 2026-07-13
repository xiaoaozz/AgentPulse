import AgentPulseCore
import SwiftUI

extension SessionPhase {
    var displayColor: Color {
        switch self {
        case .idle: Color(hex: 0x9CA3AF)
        case .preparing: Color(hex: 0x3B82F6)
        case .running: Color(hex: 0xF59E0B)
        case .waitingForAction: Color(hex: 0xEF4444)
        case .done: Color(hex: 0x22C55E)
        case .warning: Color(hex: 0xF97316)
        case .failed: Color(hex: 0xDC2626)
        case .paused: Color(hex: 0x8B5CF6)
        case .offline: Color(hex: 0x4B5563)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
