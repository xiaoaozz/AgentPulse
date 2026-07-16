# Plan 007: 统一 macOS 与 Windows 平台目录结构

> **Executor instructions**: 本计划只有在维护者明确批准后才能执行。逐步执行并在每一步运行验证命令；出现 STOP 条件时停止并报告，不要自行扩大范围。完成后更新 `plans/README.md` 中本计划的状态。
>
> **Drift check (run first)**: `git diff --stat 560f269..HEAD -- Package.swift Sources Tests Resources Windows Protocol scripts .github README.md docs plans`
> 如果迁移范围在本计划编写后发生变化，先逐项核对“Current state”和路径引用；无法一一映射时停止执行。

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: `plans/windows-to-do-list.md`
- **Category**: tech-debt / dx
- **Planned at**: commit `560f269`, 2026-07-16

## Why this matters

当前 macOS 代码遵循 SwiftPM 默认布局，散落在仓库根的 `Sources/`、`Tests/`、`Resources/`；Windows app、core 和 contract tests 则全部位于 `Windows/`。同样的 app/core/test 概念因此处在不同层级，新增代码、配置 CI 或让新贡献者定位文件时都需要记忆平台特例。

目标是把两端统一到 `Platforms/<platform>/Sources|Tests`，同时保留 SwiftPM 与 .NET 的项目名称和内部命名。共享协议单独归入 `Shared/`，Hook 适配器继续留在通用的 `scripts/`，避免把跨平台内容错误归属到某个平台。

## Target layout

```text
AgentPulse/
├── Package.swift                         # 保留根目录，维持 swift run/test 的现有入口
├── Platforms/
│   ├── macOS/
│   │   ├── Sources/
│   │   │   ├── AgentPulse/              # macOS app
│   │   │   └── AgentPulseCore/          # macOS core
│   │   ├── Tests/
│   │   │   └── AgentPulseCoreTests/
│   │   └── Resources/
│   └── Windows/
│       ├── Sources/
│       │   ├── AgentPulse.Windows/       # Windows app
│       │   └── AgentPulse.Windows.Core/  # Windows core
│       └── Tests/
│           └── AgentPulse.Windows.ContractTests/
├── Shared/
│   ├── Protocol/
│   │   ├── agent-event.schema.json
│   │   └── Fixtures/session-scenarios.json
│   └── Tests/
│       └── HookTests/
├── scripts/                              # Hook 适配器与平台构建脚本
├── docs/
└── plans/
```

目录命名规则：平台根使用官方名称 `macOS`、`Windows`；语言生态目录使用 `Sources`、`Tests`；项目目录继续使用现有 target/project 名称。不要把目录整理扩大为 Swift module、C# namespace、程序集、bundle identifier 或发布产物重命名。

## Current state

- `Package.swift:11-17` 使用 SwiftPM 的隐式默认路径，分别映射根目录下的 `Sources/AgentPulseCore`、`Sources/AgentPulse` 和 `Tests/AgentPulseCoreTests`。
- `Windows/AgentPulse.Windows/AgentPulse.Windows.csproj:19` 引用相邻的 `../AgentPulse.Windows.Core/AgentPulse.Windows.Core.csproj`。
- `Windows/AgentPulse.Windows.ContractTests/AgentPulse.Windows.ContractTests.csproj:9` 引用相邻的 core project；迁移后 tests 与 sources 分层，该相对路径必须改变。
- `Tests/AgentPulseCoreTests/ProtocolFixtureTests.swift:8-12` 通过固定层数向上寻找 `Protocol/Fixtures/session-scenarios.json`。
- `Windows/AgentPulse.Windows.ContractTests/Program.cs:18-23` 同样以固定层数和旧 `Protocol` 路径寻找共享 fixture。
- `.github/workflows/ci.yml`、`.github/workflows/release.yml`、`scripts/build-app.sh`、`scripts/build-windows.ps1`、`README.md` 和 `docs/technical-guide.md` 均包含旧路径。
- 代码内部模块命名目前稳定：Swift UI 通过 `import AgentPulseCore` 引用 core；C# app/test 通过 `AgentPulse.Windows.Core.*` namespace 引用 core。这些符号不需要改变。

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Swift build/tests | `swift test` | exit 0；20 个 XCTest 通过 |
| Node Hook tests | `node --test Shared/Tests/HookTests/agent-pulse-codex-hook.test.mjs` | exit 0；22 个测试通过 |
| Python Hook tests | `python3 -m unittest discover -s Shared/Tests/HookTests -p 'test_*.py'` | exit 0；15 个测试通过 |
| Windows contract tests | `dotnet run --project Platforms/Windows/Tests/AgentPulse.Windows.ContractTests/AgentPulse.Windows.ContractTests.csproj --configuration Release -- Shared/Protocol/Fixtures/session-scenarios.json` | exit 0；共享场景和 Named Pipe 集成测试通过 |
| Windows app build | `dotnet build Platforms/Windows/Sources/AgentPulse.Windows/AgentPulse.Windows.csproj --configuration Release -p:Platform=x64` | exit 0 |
| macOS release bundle | `VERSION=0.0.0-layout BUILD_NUMBER=1 ARCHS=arm64 ARTIFACT_SUFFIX=-unsigned scripts/build-app.sh` | exit 0；生成并校验 macOS ZIP |
| Windows release bundle | `scripts/build-windows.ps1 -Version 0.0.1-layout -Runtime win-x64` | exit 0；生成 Setup 与 Portable 包 |

本计划编写时，旧目录上的 `swift test`、Node tests 和 Python tests 已通过。Windows 两条命令必须先按 Plan 006 在 Windows 上形成迁移前基线，再开始本计划。

## Scope

**In scope**:

- 仅使用 `git mv` 搬迁上述 macOS、Windows、Shared 文件。
- 更新 `Package.swift` 的显式 target 路径。
- 更新两个 `.csproj` 中受影响的 `ProjectReference`。
- 更新 fixture 定位、CI、发布工作流、构建脚本及文档路径。
- 更新 `plans/README.md` 中迁移后的常用验证命令和本计划状态。

**Out of scope**:

- 不修改 Swift 类型/target 名、C# namespace/project 名、程序集名、应用 ID 或发布文件名。
- 不改业务逻辑、UI、协议字段或 Hook 行为。
- 不引入新的 workspace/solution、构建系统、测试框架或依赖。
- 不顺便清理 build artifacts、私钥、IDE 文件或其他技术债。
- `plans/windows-to-do-list.md` 是迁移后的 Windows 验证待办；需要随着路径迁移同步命令。

## Git workflow

- Branch: `codex/007-normalize-platform-layout`
- 使用 `git mv` 保留文件历史。
- 建议一个原子提交：`refactor: normalize platform directory layout`
- 未经操作人明确要求，不 push、不创建 PR。

## Steps

### Step 1: 建立迁移前双平台基线

确认 Plan 006 已在 Windows 环境执行并标记为 `DONE`。在当前目录结构上重新运行 Swift、Node、Python、Windows contract 和 Windows app build；保存失败信息，不能以“只是目录变更”为由忽略既有失败。

**Verify**: Plan 006 为 `DONE`，五组现有测试/构建命令均 exit 0。

### Step 2: 搬迁 macOS app、core、tests 和 resources

使用 `git mv` 完成以下一一映射：

- `Sources/AgentPulse` → `Platforms/macOS/Sources/AgentPulse`
- `Sources/AgentPulseCore` → `Platforms/macOS/Sources/AgentPulseCore`
- `Tests/AgentPulseCoreTests` → `Platforms/macOS/Tests/AgentPulseCoreTests`
- `Resources` → `Platforms/macOS/Resources`

保持根目录 `Package.swift`，为三个 target 增加显式 `path`：

- `Platforms/macOS/Sources/AgentPulseCore`
- `Platforms/macOS/Sources/AgentPulse`
- `Platforms/macOS/Tests/AgentPulseCoreTests`

不要更改 product/target 名。此时先只验证 Swift 编译和测试；资源路径在 Step 5 更新构建脚本。

**Verify**: `swift test` → exit 0，20 个 XCTest 通过；`find Sources Tests Resources -maxdepth 1 -print` → 这三个旧路径均不存在。

### Step 3: 搬迁 Windows app、core 和 contract tests

使用 `git mv` 完成以下映射：

- `Windows/AgentPulse.Windows` → `Platforms/Windows/Sources/AgentPulse.Windows`
- `Windows/AgentPulse.Windows.Core` → `Platforms/Windows/Sources/AgentPulse.Windows.Core`
- `Windows/AgentPulse.Windows.ContractTests` → `Platforms/Windows/Tests/AgentPulse.Windows.ContractTests`

app 到 core 的引用仍可保持 `../AgentPulse.Windows.Core/AgentPulse.Windows.Core.csproj`；contract tests 到 core 的引用应改为 `../../Sources/AgentPulse.Windows.Core/AgentPulse.Windows.Core.csproj`。不要修改 namespace、`RootNamespace` 或 XAML 中的 `using:`。

**Verify**: `dotnet run --project Platforms/Windows/Tests/AgentPulse.Windows.ContractTests/AgentPulse.Windows.ContractTests.csproj --configuration Release -- <当前 fixture 路径>` 和 Windows app build 均 exit 0；`test ! -d Windows` 成功。

### Step 4: 将真正共享的协议与 Hook tests 归入 Shared

使用 `git mv`：

- `Protocol` → `Shared/Protocol`
- `Tests/HookTests` → `Shared/Tests/HookTests`

Hook 运行脚本和构建脚本保留在根 `scripts/`，因为它们已经是跨平台的公共执行入口。修改 Swift 与 C# contract tests 的 fixture 定位逻辑：从测试文件/输出目录逐级查找仓库祖先，直到发现 `Shared/Protocol/Fixtures/session-scenarios.json`；找不到时抛出包含期望相对路径的明确错误。不要继续依赖写死的 `..` 数量。

**Verify**: Swift、Node、Python、Windows contract tests 全部通过；`test -f Shared/Protocol/agent-event.schema.json` 和 `test -d Shared/Tests/HookTests` 成功。

### Step 5: 更新所有构建、CI 与发布路径

逐项更新：

- `scripts/build-app.sh`：macOS `Info.plist` 与 icon 改为 `Platforms/macOS/Resources/...`。
- `scripts/build-windows.ps1`：project 改为 `Platforms/Windows/Sources/...`，协议 schema 改为 `Shared/Protocol/...`。
- `.github/workflows/ci.yml`、`.github/workflows/release.yml`：更新 Hook tests、Windows projects、fixture 参数路径。
- 保持根目录 `swift test` / `swift run AgentPulse` 可用，不让纯目录整理改变开发入口。

**Verify**: macOS release bundle、Windows contract tests、Windows app build、Windows release bundle 全部 exit 0；对应产物仍使用原文件名。

### Step 6: 更新文档和残留引用

更新 `README.md` 与 `docs/technical-guide.md` 的项目树、源码构建命令、测试命令、协议链接和 logo 路径。更新 `plans/README.md` 的当前验证命令，但保留已完成计划文件中的历史路径。

仅在活跃配置、源码和现行文档中搜索旧路径；忽略 `.git/`、`.build/`、`dist/`、`bin/`、`obj/` 和历史计划文件。

**Verify**:

```bash
rg -n '(Sources/AgentPulse|Sources/AgentPulseCore|Tests/AgentPulseCoreTests|Tests/HookTests|Windows/AgentPulse|Protocol/Fixtures|Resources/AppIcon)' \
  Package.swift .github scripts README.md docs Platforms Shared
```

期望：无旧根路径匹配；`Platforms/...`、`Shared/...` 的新路径匹配不算失败。

### Step 7: 运行完整验证并检查变更性质

运行 Commands 表中的全部验证。检查 rename detection，确保绝大部分源码文件显示为 rename，而不是删除后重建；人工审阅非 rename diff，应该只包含 manifest/project reference、fixture locator、脚本、CI 和文档路径。

**Verify**: `git diff --summary` 显示预期 rename；`git diff --check` 无错误；`git status --short` 不包含 scope 外文件。

## Test plan

- Swift：全部 20 个现有 XCTest，重点确认 `ProtocolFixtureTests` 在新目录仍能定位共享 fixture。
- Node：22 个现有 Hook tests 在 `Shared/Tests/HookTests` 下运行。
- Python：15 个现有 Hook tests 在新路径下运行。
- Windows：contract runner 的共享 fixtures 与 6 个 Named Pipe integration tests 通过；WinUI app Release x64 build 通过。
- Packaging：两端构建脚本仍复制 Hook scripts 与 protocol schema，产物命名不变。
- 不新增业务行为测试；只有 fixture locator 需要覆盖“能找到”与“找不到时报明确错误”两个路径行为（可用现有 contract runner/Swift test 直接覆盖成功路径，失败路径若难以隔离则至少通过清晰异常分支代码审阅）。

## Done criteria

- [ ] 目标目录树与 Target layout 一致，旧 `Sources/`、`Tests/`、`Resources/`、`Windows/`、`Protocol/` 不再存在。
- [ ] `swift run AgentPulse` 和 `swift test` 仍可从仓库根执行。
- [ ] Swift、Node、Python、Windows contract tests 全部通过。
- [ ] Windows app Release x64 build 通过。
- [ ] macOS 与 Windows release bundle 均成功，用户可见产物名称未变化。
- [ ] 活跃代码、配置和现行文档不再引用旧根路径。
- [ ] Swift target、C# namespace/project、bundle/application 标识未改变。
- [ ] `git diff --check` 通过，scope 外无修改。
- [ ] `plans/README.md` 状态更新为 `DONE`。

## STOP conditions

停止并报告，不要自行处理，如果：

- Plan 006 尚未在 Windows 上完成，或迁移前任一平台基线失败。
- `Package.swift` 无法在根目录通过显式 path 保持 `swift run` / `swift test` 入口。
- Windows project reference 更新要求修改 namespace、程序集名或应用标识。
- 共享 fixture 在 CI 与本地需要两套互斥路径，且无法通过稳定的祖先查找统一。
- 发布脚本要求改变用户可见产物名或安装包内容结构。
- 必须修改 Scope 之外的业务源码才能让测试通过。

## Maintenance notes

- 新平台代码只允许进入 `Platforms/<platform>/Sources`，平台专属测试进入对应 `Platforms/<platform>/Tests`。
- 同时被两端消费的协议、fixtures 与测试资产进入 `Shared/`；通用可执行脚本仍进入 `scripts/`。
- Review 时重点检查大小写路径。macOS 默认文件系统可能不暴露大小写错误，Windows/Linux CI 会暴露；配置与文档必须精确使用 `Platforms/macOS`、`Platforms/Windows`、`Shared/Protocol`。
- 后续如果引入第三个平台，复制 `Platforms/<Platform>/Sources|Tests` 的语义结构，不要求不同语言使用相同构建文件。
