import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("状态面板") {
                Picker("显示方式", selection: $model.statusSurfaceMode) {
                    ForEach(StatusSurfaceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                LabeledContent(
                    "交互",
                    value: model.statusSurfaceMode == .floatingBall
                        ? "拖动定位，点击展开"
                        : "悬停展开"
                )
                LabeledContent("收起按钮", value: "切换为悬浮球")
                Text("悬浮球会记住拖动位置，点击即可展开最近会话。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("交互原则") {
                Label("只展示状态，不发送 macOS 通知或弹出审批框。", systemImage: "hand.tap")
                    .font(.callout)
            }
            Section("事件入口") {
                Text("Unix Socket: /tmp/agentpulse.sock")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            Section("版本") {
                LabeledContent("当前版本", value: model.currentVersion)
                Text("新版本请前往 GitHub Releases 手动下载安装。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 390)
    }
}
