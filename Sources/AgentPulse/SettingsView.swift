import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("刘海面板") {
                LabeledContent("显示方式", value: "状态文字 + 会话数量")
                LabeledContent("菜单栏图标", value: "默认隐藏")
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
