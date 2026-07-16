import AgentPulseCore
import SwiftUI

struct SessionPanel: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var repository: SessionRepository

    init(model: AppModel) {
        self.model = model
        _repository = ObservedObject(wrappedValue: model.repository)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if repository.sessions.isEmpty { emptyState }
            else { sessionList }
            Divider()
            footer
        }
        .frame(width: 380)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("AgentPulse").font(.headline)
                Text(summary).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if repository.attentionCount > 0 {
                Text("待操作 \(repository.attentionCount)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(hex: 0xEF4444))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color(hex: 0xEF4444).opacity(0.12), in: Capsule())
            }
        }
        .padding(14)
    }

    private var summary: String {
        repository.sessions.isEmpty ? "等待 Agent 会话" :
            "\(repository.activeCount) 运行中 · \(repository.sessions.count) 个会话"
    }

    private var sessionList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(repository.sessions) { session in
                    SessionRow(session: session, emphasizeAttention: model.useAttentionColor) {
                        model.jump(to: session)
                    }
                }
            }
            .padding(10)
        }
        .frame(maxHeight: 460)
    }

    private var emptyState: some View {
        VStack(spacing: 9) {
            Image(systemName: "waveform.path.ecg").font(.title).foregroundStyle(.secondary)
            Text("还没有会话事件").font(.subheadline.weight(.medium))
            Text("接入 Hook 后，会话状态会显示在这里")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 170)
    }

    private var footer: some View {
        HStack {
            Button("一键清理结果 (\(repository.clearableCount))") { repository.clearCompleted() }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .disabled(repository.clearableCount == 0)
            Spacer()
            SettingsLink { Image(systemName: "gearshape") }
                .buttonStyle(.plain)
            Button("退出") { NSApplication.shared.terminate(nil) }.buttonStyle(.plain)
        }
        .font(.caption)
        .padding(12)
    }
}

private struct SessionRow: View {
    let session: AgentSession
    let emphasizeAttention: Bool
    let jump: () -> Void

    var body: some View {
        Button(action: jump) {
            HStack(spacing: 11) {
                SessionStatusIndicator(phase: session.phase, diameter: 9)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(headline).lineLimit(1).font(.subheadline.weight(.medium))
                        Spacer()
                        Text(session.agent).font(.caption2).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 6) {
                        Text(session.phase.label).foregroundStyle(session.phase.needsAttention ? color : Color.secondary)
                            .help(session.phase.meaning)
                        Text("·")
                        Text(session.projectName).lineLimit(1)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Image(systemName: "arrow.up.forward.app").foregroundStyle(.tertiary)
            }
            .padding(10)
            .contentShape(Rectangle())
            .background(background, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .help("跳转到这个会话")
    }

    private var color: Color {
        session.phase.displayColor
    }

    private var background: Color {
        session.phase.needsAttention && emphasizeAttention ? color.opacity(0.10) : Color.primary.opacity(0.04)
    }

    private var headline: String {
        session.title
    }

    private var subtitle: String {
        session.detail ?? session.phase.meaning
    }
}
