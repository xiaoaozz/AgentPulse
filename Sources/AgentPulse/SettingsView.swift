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
            Section("软件更新") {
                LabeledContent("当前版本", value: model.currentVersion)
                Button("检查更新…") {
                    model.checkForUpdates()
                }
                .disabled(!model.canCheckForUpdates)
                if !model.canCheckForUpdates {
                    Text("源码运行版本未配置更新源。正式安装包会自动检查更新。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 390)
    }
}
