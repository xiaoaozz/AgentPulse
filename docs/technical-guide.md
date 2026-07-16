# AgentPulse 技术指南

> 返回 [项目首页](../README.md)。本文档保留原 README 中的完整安装、接入、协议、构建、发布与故障排查说明。



AgentPulse 是一个面向 macOS 和 Windows 的本地 Agent 会话状态面板。它集中展示多个 Codex、Claude Code 或自研 Agent 会话当前在做什么，以及哪些会话正在等待用户操作。

AgentPulse 只做状态聚合和入口跳转，不代替 Agent 处理权限审批，也不会发送系统通知。出现 `waiting_for_action` 时，应用会突出显示对应会话；点击会话后回到原 Agent 或终端继续处理。

## 功能

- macOS 原生刘海常驻：默认不创建菜单栏或 Dock 图标，无需 Electron 常驻运行时。
- Windows 原生托盘：点击系统托盘图标后在任务栏右下角展开 WinUI 3 会话面板。
- 多会话聚合：同一 `session_id` 的事件会原地更新，并按处理优先级排序。
- 待操作提示：刘海面板会优先展示等待操作的会话状态。
- 刘海常驻面板：自动识别内置刘海屏幕，在刘海两侧显示英文状态和进行中会话数；稳定悬停后展开面板，避免指针经过屏幕顶部时误触，并按最近使用时间倒序展示最多 5 个会话。
- 快速返回：macOS 根据 `terminal_bundle_id` 或 `pid` 激活来源应用；Windows 根据 `pid` 或 `terminal_process` 激活 Windows Terminal、VS Code、Warp 或 PowerShell。
- 本机事件通道：macOS 使用权限为 `0600` 的 Unix Domain Socket，Windows 使用当前用户 Named Pipe，不开放 TCP 端口。
- Agent 无关协议：内置 Codex 和 Claude 风格 Hook 适配器，也允许任意程序直接发送 JSON。
- 终态保留：`paused`、`done`、`warning` 和 `failed` 会话支持单条删除，也可以在展开面板中一键清除。
- 精简发布产物：Release 只提供 macOS 使用包、Windows 安装包和 Windows 便携包。

## 系统要求

- macOS 14 或更高版本，或者 Windows 10 1809/Windows 11
- macOS 源码构建需要支持 Swift 6.1 package manifest 的 Swift 工具链
- Windows 源码构建需要 .NET 8 SDK
- 接入 Codex 适配器时需要 Node.js
- 接入 Python 适配器时需要 Python 3

## 安装

从仓库的 [Releases](https://github.com/xiaoaozz/AgentPulse/releases) 页面下载最新的 `AgentPulse-*-macos-universal.zip`，解压后将 `AgentPulse.app` 拖入 `/Applications`。

正式签名并经过 Apple 公证的版本可以直接打开。文件名包含 `-unsigned` 的测试版本采用临时签名，第一次启动时需要在 Finder 中右键 App、选择“打开”并确认。

安装包同时支持 Apple Silicon 和 Intel Mac。随 App 提供的 Hook 脚本位于：

```text
/Applications/AgentPulse.app/Contents/Resources/Scripts/
```

Windows 推荐下载 `AgentPulse-Windows-Setup.exe`。安装后应用会常驻系统托盘，随包 Hook 位于安装目录的 `Scripts/`。不想安装时可下载 `AgentPulse-Windows-Portable.zip`。新版本均从 Releases 手动下载安装。

## 快速开始

在项目根目录运行：

```bash
swift run AgentPulse
```

应用启动后只在刘海区域显示，并监听：

```text
/tmp/agentpulse.sock
```

可以先发送一条测试事件确认界面工作正常：

```bash
printf '%s' '{"session_id":"demo","agent":"Demo","cwd":"/tmp/demo","title":"README 演示","phase":"waiting_for_action","detail":"请回到会话确认"}' \
  | nc -U /tmp/agentpulse.sock
```

点击该会话只会尝试激活来源应用；上面的测试事件没有提供来源信息，因此不保证跳转到特定窗口。

Windows 客户端监听 `\\.\pipe\agentpulse`，Node.js 与 Python Hook 会自动根据操作系统选择 Named Pipe，无需修改 Hook 配置。

### 本地 Release 构建

```bash
scripts/build-app.sh
```

Windows PowerShell 构建：

```powershell
scripts/build-windows.ps1 -Version 0.2.0 -Runtime win-x64
```

构建结果位于 `dist/`：

```text
dist/AgentPulse.app
dist/AgentPulse-0.1.0-macos-universal.zip
dist/release-win-x64/AgentPulse-Windows-Setup.exe
dist/release-win-x64/AgentPulse-Windows-Portable.zip
dist/velopack-win-x64/io.github.xiaoaozz.AgentPulse-0.1.0-full.nupkg
dist/velopack-win-x64/releases.win.json
```

默认构建 arm64 与 x86_64 通用版本并使用临时签名。可以通过环境变量指定版本、构建号或只构建一个架构：

```bash
VERSION=0.2.0 BUILD_NUMBER=2 ARCHS=arm64 scripts/build-app.sh
```

如果本机已安装 Developer ID Application 证书，可以生成正式签名版本：

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAM_ID)" \
NOTARY_PROFILE="AgentPulseNotary" \
VERSION=0.2.0 \
scripts/build-app.sh
```

其中 `AgentPulseNotary` 是预先通过 `xcrun notarytool store-credentials` 保存的钥匙串配置。脚本会签名 App、提交 Apple 公证、装订公证票据并重新生成 ZIP。

### GitHub Release

推送 `v*` 标签会触发 [`.github/workflows/release.yml`](../.github/workflows/release.yml)，运行全部测试、构建 Universal App 并创建 GitHub Release：

```bash
git tag v0.1.0
git push origin v0.1.0
```

没有配置 Apple 凭据时，工作流会发布文件名带 `-unsigned` 的测试包。正式签名与公证需要在仓库的 **Settings → Secrets and variables → Actions** 中同时配置以下六个 Secrets：

| Secret | 内容 |
| --- | --- |
| `MACOS_CERTIFICATE` | Developer ID Application `.p12` 文件的 Base64 内容 |
| `MACOS_CERTIFICATE_PASSWORD` | 导出 `.p12` 时设置的密码 |
| `MACOS_SIGN_IDENTITY` | 完整签名身份，例如 `Developer ID Application: Your Name (TEAM_ID)` |
| `APPLE_API_PRIVATE_KEY` | App Store Connect API `.p8` 文件的 Base64 内容 |
| `APPLE_API_KEY_ID` | API Key ID |
| `APPLE_API_ISSUER_ID` | API Issuer ID |

证书或 API Key 可分别这样转换为 Base64 后复制到 GitHub Secret：

```bash
base64 -i DeveloperID.p12 | pbcopy
base64 -i AuthKey_KEYID.p8 | pbcopy
```

不要将证书、私钥或密码提交到仓库。发布前也可以在 `dist/` 中验证本地构建：

```bash
lipo -archs dist/AgentPulse.app/Contents/MacOS/AgentPulse
codesign --verify --deep --strict --verbose=2 dist/AgentPulse.app
```

Release 页面只上传三个用户可直接使用的附件：macOS ZIP、Windows Setup 和 Windows Portable ZIP。Velopack 构建过程中仍会在本地产生内部打包文件，但工作流不会把它们上传到 Release。

## 接入 Codex

项目提供 [`scripts/agent-pulse-codex-hook.mjs`](../scripts/agent-pulse-codex-hook.mjs)。脚本采用 fire-and-forget 方式发送状态；AgentPulse 未运行或本机传输端点不可用时，脚本会静默退出，不阻断 Codex。

如果使用 GitHub Release 安装了 App，可以直接使用随 App 分发的脚本路径，无需保留源码仓库：

```bash
node /Applications/AgentPulse.app/Contents/Resources/Scripts/agent-pulse-codex-hook.mjs
```

### 方式一：生命周期 Hooks（推荐）

生命周期 Hooks 能展示 `ready`、`preparing`、`running`、`waiting_for_action` 和 `done` 的完整变化。将下面内容合并到 `~/.codex/hooks.json`，并把命令中的路径替换为本仓库脚本的绝对路径：

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "node /absolute/path/to/AgentPulse/scripts/agent-pulse-codex-hook.mjs",
            "timeout": 2
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "node /absolute/path/to/AgentPulse/scripts/agent-pulse-codex-hook.mjs",
            "timeout": 2
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "node /absolute/path/to/AgentPulse/scripts/agent-pulse-codex-hook.mjs",
            "timeout": 2
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "node /absolute/path/to/AgentPulse/scripts/agent-pulse-codex-hook.mjs",
            "timeout": 2
          }
        ]
      }
    ],
    "PermissionRequest": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "node /absolute/path/to/AgentPulse/scripts/agent-pulse-codex-hook.mjs",
            "timeout": 2
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "node /absolute/path/to/AgentPulse/scripts/agent-pulse-codex-hook.mjs",
            "timeout": 2
          }
        ]
      }
    ]
  }
}
```

首次添加或修改非托管 Hook 后，在 Codex CLI 中使用 `/hooks` 检查并信任对应定义，否则 Codex 会跳过执行。项目级配置也可以放在 `<repo>/.codex/hooks.json`，但只会在仓库被信任时加载。详细规则参见 [Codex Hooks 官方文档](https://developers.openai.com/codex/hooks)。

事件映射如下：

| Codex 事件 | AgentPulse 状态 |
| --- | --- |
| `SessionStart` | `ready` |
| `UserPromptSubmit` | `preparing` |
| `PreToolUse`、`PostToolUse` | `running`；工具响应标记为已取消时为 `paused` |
| `PermissionRequest` | `waiting_for_action`（人工审批）或 `running`（替我审批） |
| `Stop` | `done` |

生命周期 Hook 的工具事件会通过 `transcript_path` 读取本轮最新 GPT 回复，并在保持会话标题不变的前提下更新详情。因此 GPT 给出阶段说明并继续调用工具时，用户不必等到整轮结束就能看到最新进度。`UserPromptSubmit` 后还会从当时的文件末尾监视本轮 transcript；Codex 写入 `turn_aborted` 时立即发送 `paused`，正常完成或监视超过 24 小时后自动退出。这补足了生命周期 Hook 没有“用户中止”事件的问题。读取以本轮用户消息为边界；如果 transcript 不存在或格式无法识别，适配器会保留已有详情且不阻断 Codex。

适配器也能转换由外部桥接器主动转发的 Codex App Server 事件：`turn/interrupt` 会立即把对应会话标记为 `paused`；每个 `item/completed` 的 `agentMessage` 会更新详情；`turn/completed` 中的 `failed` 映射为 `failed`，其余完成状态映射为 `done`。AgentPulse 不会旁路订阅其他客户端现有的 App Server 连接，因此常规 Hooks 接入的动态详情来自上述 transcript 路径。

### 审批者模式

Codex 的 `PermissionRequest` 表示工具需要审批，但审批者不一定是用户。AgentPulse 默认按人工审批处理，以保持现有接入兼容：

```text
PermissionRequest → waiting_for_action
```

如果 Codex 配置了 `approvals_reviewer = "auto_review"`（“替我审批”），请在 Hook 命令后增加：

```bash
node /absolute/path/to/AgentPulse/scripts/agent-pulse-codex-hook.mjs --approval-reviewer auto_review
```

此时 `PermissionRequest` 会继续显示为 `running`，详情为“Codex 正在代为审批”，不会计入待操作数量，也不会触发红色强调。也可以用环境变量配置相同语义：

```bash
AGENTPULSE_APPROVAL_REVIEWER=auto_review node /absolute/path/to/AgentPulse/scripts/agent-pulse-codex-hook.mjs
```

可用值如下：

| 值 | `PermissionRequest` 状态 | 用途 |
| --- | --- | --- |
| `user` | `waiting_for_action` | 由用户审批；默认值 |
| `auto_review` | `running` | 由 Codex reviewer agent 审批 |

Codex 当前公开的 Hook 输入不包含 `approvals_reviewer`，因此适配器不能可靠地自动识别该设置。如果同一 Codex 会话还安装了其他会阻塞 `PermissionRequest` 的 Hook，也需要将那些 Hook 切换为非阻塞监控或移除对应监听，否则其他工具仍可能显示人工审批入口。

### 方式二：`notify`（仅完成状态）

如果只需要在一轮 Agent 工作完成后记录结果，可在用户级 `~/.codex/config.toml` 中配置：

```toml
notify = ["node", "/absolute/path/to/AgentPulse/scripts/agent-pulse-codex-hook.mjs"]
```

Codex 会把 `agent-turn-complete` JSON 作为命令行参数传给脚本。`notify` 当前不能提供执行中或等待审批的完整状态，因此不应与“完整生命周期监控”等同。详细说明参见 [Codex 高级配置中的 Notifications](https://developers.openai.com/codex/config-advanced#notifications)。

如果同时配置生命周期 Hooks 和 `notify`，同一轮结束时可能收到两条 `done` 事件；它们使用相同会话 ID 时只会更新同一条会话记录。

## 接入 Claude Code 或其他 Hook

[`scripts/agentpulse-hook.py`](../scripts/agentpulse-hook.py) 接收 stdin 中的 Claude 风格 Hook JSON，支持以下映射：

使用 GitHub Release 安装时，对应命令为：

```bash
python3 /Applications/AgentPulse.app/Contents/Resources/Scripts/agentpulse-hook.py
```

| Hook 事件 | AgentPulse 状态 |
| --- | --- |
| `SessionStart` | `ready` |
| `UserPromptSubmit` | `preparing` |
| `PreToolUse`、`PostToolUse`、`PreCompact` | `running` |
| `PermissionRequest` | `waiting_for_action` |
| `Notification` 且类型为 `idle_prompt` 或 `permission_prompt` | `waiting_for_action` |
| `Stop`、`SubagentStop`、`agent-turn-complete` | `done` |
| `SessionEnd` | `offline` |

在 Agent 的各个生命周期 Hook 中执行以下命令即可：

```bash
python3 /absolute/path/to/AgentPulse/scripts/agentpulse-hook.py
```

适配器不会修改 `~/.claude`、`~/.codex` 或其他 Agent 配置，请根据实际客户端支持的事件，将命令合并到现有 Hook 设置中。未知事件会被忽略，避免错误地覆盖当前会话状态。

### 适配器环境变量

| 变量 | 使用者 | 说明 |
| --- | --- | --- |
| `AGENTPULSE_SOCKET` | Node.js、Python | 覆盖默认 Socket 路径 `/tmp/agentpulse.sock` |
| `AGENTPULSE_AGENT` | Python | 没有识别为 Codex 时使用的 Agent 名称，默认 `Agent` |
| `TERM_PROGRAM` | Node.js、Python | 自动推断 Terminal、iTerm2、Ghostty 或 Warp 的 bundle identifier |

Node.js 适配器还支持 `--source <name>`，用于覆盖界面显示的 Agent 名称：

```bash
node scripts/agent-pulse-codex-hook.mjs --source MyAgent
```

## 通用事件协议

每次连接发送一个 UTF-8 JSON 对象，发送完成后关闭连接。服务端以连接结束作为消息结束标记，因此不要在同一次连接中连续发送多个对象。

```json
{
  "session_id": "019f-session-id",
  "agent": "MyAgent",
  "cwd": "/Users/me/project",
  "title": "修复登录流程",
  "phase": "waiting_for_action",
  "detail": "需要确认是否修改数据库结构",
  "pid": 1234,
  "tty": "/dev/ttys001",
  "terminal_bundle_id": "com.googlecode.iterm2",
  "occurred_at": "2026-07-13T03:20:00Z"
}
```

### 字段

| 字段 | 必填 | 类型 | 说明 |
| --- | --- | --- | --- |
| `session_id` | 是 | string | 会话唯一标识；相同 ID 的后续事件更新原记录 |
| `agent` | 是 | string | 界面显示的 Agent 名称 |
| `cwd` | 是 | string | 会话工作目录，也用于推断项目名和默认标题 |
| `phase` | 是 | string | 下表中的状态值 |
| `title` | 否 | string | 会话标题；空值或空白值不会覆盖已有标题 |
| `detail` | 否 | string | 本轮会话的简短内容（用户输入、Agent 输出或错误摘要）；缺失或空白时保留上一次非空摘要 |
| `pid` | 否 | integer | 来源应用的进程 ID，用于点击会话时激活应用 |
| `tty` | 否 | string | 来源 TTY；当前仅存储，尚未用于窗口定位 |
| `terminal_bundle_id` | 否 | string | macOS 应用 bundle identifier，跳转时优先使用 |
| `occurred_at` | 否 | string | 带或不带小数秒的 ISO 8601 时间；省略时使用服务端接收时间 |

### 状态

| `phase` | 显示名称 | 颜色 | 含义 | 计入进行中数量 | 可一键清理 |
| --- | --- | --- | --- | --- | --- |
| `ready` | Ready | `#22C55E` | 工具已就绪，无任务执行 | 否 | 否 |
| `preparing` | Preparing | `#3B82F6` | 初始化、准备执行 | 是 | 否 |
| `running` | Running | `#F59E0B` | 正在执行任务 | 是 | 否 |
| `waiting_for_action` | Waiting for Action | `#EF4444` | 等待用户操作 | 是 | 否 |
| `done` | Done | `#22C55E` | 执行完成 | 否 | 是 |
| `warning` | Warning | `#F97316` | 已完成，但存在警告或异常 | 否 | 是 |
| `failed` | Failed | `#DC2626` | 执行失败 | 否 | 是 |
| `paused` | Paused | `#8B5CF6` | 任务已由用户中止 | 否 | 是 |
| `offline` | Offline | `#4B5563` | Agent 离线 | 否 | 否 |

主会话列表排序优先级为：等待操作 → 执行中/准备中 → 暂停 → 空闲 → 完成/警告/失败 → 离线。同一优先级内，最近更新的会话排在前面。刘海展开区域独立按最近使用时间倒序展示，最多显示 5 条会话。

刘海折叠状态和 Windows 托盘只反映当前仍在进行的工作：优先显示待操作，其次显示准备中或运行中；如果只剩中止、完成、失败、就绪或离线会话，全局状态恢复为初始 `Ready`/“等待 Agent 会话”。这些终态仍保留在展开后的单条会话中，并可单独删除或一键清理。清除 `paused` 后，如果用户在原 Codex 会话继续提交请求，新的 `UserPromptSubmit` 事件会以同一会话 ID 创建一条全新的任务记录。

正常完成时，全局工具状态会短暂显示 `Done` 5 秒。如果这段时间没有任何新会话事件，5 秒后自动恢复 `Ready`；新事件到达时立即按新状态更新。单条会话的 `done` 状态不会随全局状态计时而改变。

## 界面行为

- 列表标题中的“运行中”只统计 `preparing` 和 `running`；待操作数量单独显示。
- 设置中的“待操作状态使用强调色”只控制会话行背景，状态圆点和文字颜色不受影响。
- 点击会话只负责激活来源应用，不保证定位到某个终端标签页或 Codex 线程。
- 如果没有刘海屏幕，常驻面板会回退到主屏幕顶部中央显示。
- 会话仅保存在内存中；退出或重启 AgentPulse 后不会恢复历史记录。

### 刘海面板

- 折叠状态不显示状态图标，左侧以较大的英文文字完整显示最高优先级会话状态，例如 `Preparing...`、`Running...`、`Action` 和 `Done`；右侧显示进行中会话数。刘海两侧使用等宽布局，避免状态文字被截断或面板偏移。
- 鼠标稳定悬停约 180ms 后展开会话列表，按 `updatedAt` 从新到旧排列，最多显示最近 5 条会话。
- 每条会话以本轮用户消息 `title` 作为主标题，最新 Agent 输出 `detail` 作为辅助信息。Hook 会将用户消息压缩为空白规整的单行标题，超过 80 个字符时以 `...` 省略；后续工具事件不会再用项目名或 `Bash` 等工具名覆盖本轮内容。
- 每条会话都可以独立点击并尝试激活其来源应用；会话数量变化时，展开面板会同步调整高度。
- 没有会话时只显示“等待 Agent 会话”，不展示额外的品牌标题。
- 应用默认不显示 macOS 菜单栏或 Dock 图标；展开刘海面板后可点击右下角电源图标安全退出。

## 项目结构

```text
AgentPulse/
├── Sources/AgentPulse/             # 刘海面板、设置与应用跳转
├── Sources/AgentPulseCore/         # 事件模型、解码、会话仓库与 Socket 服务
├── Protocol/                       # 跨平台 JSON Schema 与行为 Fixtures
├── Windows/                        # WinUI 3 客户端、C# 核心与契约测试
├── scripts/                        # Codex/Claude 风格 Hook 适配器
├── Tests/AgentPulseCoreTests/      # Swift Core 单元与 Socket 测试
├── Tests/HookTests/                # Node.js Hook 映射测试
└── Package.swift
```

核心数据流：

```text
macOS:   Agent Hook → Unix Socket → SessionRepository → 刘海面板
Windows: Agent Hook → Named Pipe  → SessionRepository → 托盘浮层
```

## 开发与测试

运行 Swift 测试：

```bash
swift test
```

运行 Node.js Hook 测试：

```bash
node --test Tests/HookTests/agent-pulse-codex-hook.test.mjs
```

运行 Python Hook 测试：

```bash
python3 -m unittest discover -s Tests/HookTests -p 'test_*.py'
```

在 Windows 上运行共享协议测试与构建：

```powershell
dotnet run --project Windows/AgentPulse.Windows.ContractTests -- Protocol/Fixtures/session-scenarios.json
dotnet build Windows/AgentPulse.Windows/AgentPulse.Windows.csproj -c Release -p:Platform=x64
```

测试覆盖事件时间解析、会话更新与排序、结果清理、Socket 延迟写入，以及 Codex Hook 的主要事件映射。

## 故障排查

### 刘海面板没有出现事件

1. 确认 AgentPulse 正在运行。
2. 检查 Socket 是否存在：`ls -l /tmp/agentpulse.sock`。
3. 使用“快速开始”中的 `nc -U` 示例发送测试事件。
4. 如果手工事件正常，检查 Hook 命令是否使用了正确的绝对路径，以及对应的 Node.js/Python 是否在 Hook 的 `PATH` 中。
5. Codex 生命周期 Hook 还需在 `/hooks` 中完成信任审核。

### Socket 存在但事件被拒绝

- 确认 JSON 包含 `session_id`、`agent`、`cwd` 和合法的 `phase`。
- `occurred_at` 必须是 ISO 8601 格式，例如 `2026-07-13T03:20:00Z` 或 `2026-07-13T03:20:00.123Z`。
- 每个连接只发送一个完整 JSON 对象，并在发送后关闭连接。

### 点击会话没有回到正确窗口

建议在事件中提供 `terminal_bundle_id`；其次可提供来源应用的 `pid`。当前实现只激活应用，不读取终端标签页、TTY 或 Codex 线程的私有状态。

### 异常退出后残留 Socket

应用下次启动时会先删除同路径的旧 Socket 再重新监听。也可以在确认 AgentPulse 未运行后手动删除：

```bash
rm /tmp/agentpulse.sock
```

## 设计边界

- AgentPulse 不批准、拒绝或修改任何 Agent 权限请求。
- AgentPulse 不向 Hook 返回业务决策；Codex `Stop` Hook 仅输出空 JSON 以正常确认事件。
- AgentPulse 不发送系统通知，也不把事件上传到网络；Codex Hook 仅按需读取 transcript 尾部来提取本轮最新 GPT 回复，不保存完整对话。
- 当前没有会话持久化、开机自启、应用内更新或 DMG 打包能力；macOS 正式版本支持签名与公证。
