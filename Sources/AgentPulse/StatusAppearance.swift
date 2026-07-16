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

struct SessionStatusIndicator: View {
    let phase: SessionPhase
    let diameter: CGFloat

    @State private var isPulsing = false

    var body: some View {
        ZStack {
            if phase == .running {
                Circle()
                    .stroke(Color(hex: 0x38BDF8).opacity(isPulsing ? 0 : 0.9), lineWidth: 1.5)
                    .frame(width: diameter, height: diameter)
                    .scaleEffect(isPulsing ? 2.25 : 1)

                Circle()
                    .fill(Color(hex: 0x38BDF8).opacity(0.2))
                    .frame(width: diameter * 1.7, height: diameter * 1.7)
                    .blur(radius: 3)
            }

            Circle()
                .fill(phase.displayColor)
                .frame(width: diameter, height: diameter)
                .shadow(
                    color: phase == .running ? Color(hex: 0x38BDF8).opacity(0.75) : .clear,
                    radius: 4
                )
        }
        .frame(width: diameter, height: diameter)
        .onAppear {
            guard phase == .running else { return }
            withAnimation(.easeOut(duration: 1.35).repeatForever(autoreverses: false)) {
                isPulsing = true
            }
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
