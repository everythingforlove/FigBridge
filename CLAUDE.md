# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目定位

macOS 12+ 原生 SwiftUI 应用,使用 Swift Package Manager 管理,Swift 6 (`swiftLanguageModes: [.v6]`),严格 Sendable / actor 隔离。整体架构为 MVVM:`Sources/FigBridgeCore` 承载领域逻辑与服务,`Sources/FigBridgeApp` 承载 UI 与 ViewModel。两者之间唯一允许的依赖方向是 App → Core。

不要在 Core 中引入 SwiftUI / AppKit,也不要在 App 中实现可被复用的纯逻辑(应下沉到 Core 并加测试)。

## 常用命令

```bash
swift run FigBridge                           # 运行 macOS App
swift build                                   # 调试构建
swift test                                    # 跑全部测试
swift test --filter LinkParserTests           # 跑单个测试套件
swift test --filter LinkParserTests/parsePureURLLine  # 跑单个测试用例
./scripts/package-dmg.sh arm64                # 打包 Apple Silicon DMG
./scripts/package-dmg.sh x86_64               # 打包 Intel DMG(macOS 12+)
```

测试框架是 swift-testing(`import Testing` + `@Test`),不是 XCTest。

## 核心架构(需读多文件才能理解)

### 依赖装配
`AppContainer.init()`(`Sources/FigBridgeApp/AppContainer.swift`)是唯一的依赖装配点,它:
- 在 `~/Library/Application Support/FigBridge/` 下建立 `Batches/`、`settings.json`、`generate-workspace-draft.json`
- 构建 `SettingsStore` / `BatchStore` / `AgentService` / `FigmaService` / `GenerationCoordinator` / `GenerateWorkspaceDraftStore`
- 装配三个 ViewModel(Settings / Generate / Viewer)和 `TabSelectionCoordinator`(用于"查看页继续编辑批次"跳回生成页)

新增服务时优先扩展 AppContainer 的初始化,不要在 View 内部直接创建实例。

### 生成主链路
`GenerationCoordinator.generate(...)`(`Sources/FigBridgeCore/GenerationCoordinator.swift`)是写代码时最常触碰的入口。要点:
- 支持基于 `existingBatchID` **续跑**:已存在批次会复用其 `createdAt` 与 `runLogsByItemID`,只对 `generatedYAMLPath == nil` 的条目进行处理
- 两层正交策略:
  - `GenerationMode`:`sequential` / `parallel`(并发由 `parallelism` 上限通过 `withThrowingTaskGroup` 控制)
  - `AgentCallStrategy`:`singlePerLink` 每个链接一次 agent 调用;`singleForBatch` 整批一次调用,需要 agent 按段落格式输出
- `singleForBatch` 使用 `<<<FIGBRIDGE_YAML_START fileKey=... nodeId=...>>>` ... `<<<FIGBRIDGE_YAML_END>>>` 段标记,由 `MultiYAMLOutputParser` 用 `NSRegularExpression` 解析。修改 prompt 模板(`PromptBuilder.makeBatchPrompt`)时必须保持这个协议兼容
- 单条目通过 `AgentRunEvent` 流式回调(`started/stdout/stderr/finished/failed/cancelled`),ViewModel 据此更新运行日志面板

### Agent 调用
`AgentService` 通过 `ShellClient.resolveExecutable(named:)` 在 `PATH` 上查找本机 `claude` / `codex` 二进制,因此用户必须先安装。命令行约定:
- Claude: `claude -p <prompt>`
- Codex: `codex exec --skip-git-repo-check <prompt>`(`--skip-git-repo-check` 用于绕过 codex 的目录信任弹窗,有专门的 `CodexTrustBypassTests`)

`ShellClient.runStreaming` 用 `Process` + `Pipe` + `readabilityHandler` 提供逐行 stdout/stderr 推送,并支持 `Task` 取消与超时(默认 300s)。任何 agent 行为变更都要兼顾流式回调与取消语义。

### 批次持久化(BatchStore)
`BatchStore`(`Sources/FigBridgeCore/BatchStore.swift`)负责把 `GenerationBatch` 落盘为以下结构:

```
<rootDirectory>/<batchID>/
├── batch.json          # 持久化态(路径已相对化)
├── source-input.txt    # 原始输入文本
├── exports/            # 用户导出区(YAML 等)
└── items/<itemUUID>-<nodeId>/
    ├── meta.json       # 单条目持久化态
    ├── assets/         # preview.png / 图片资源(被 archiveLocalAssetIfNeeded 拷贝至此)
    └── yaml/           # agent 产生的 YAML + agent-output.txt
```

**路径相对化是关键不变量**:写盘前 `makePersistable(...)` 会把 `outputDirectory` / `previewImagePath` / `generatedYAMLPath` / `agentOutputPath` / `resourceItems[].localPath` 转成相对于 `batchDirectory` 的路径(否则保留原值);读盘后 `makeRuntimeBatch(...)` 反向还原成绝对路径。这样导入/重命名/迁移目录时路径仍然有效。新增任何"指向批次内文件"的字段都要在这两个映射函数里加上。

`importBatchDirectory` / `importBatchArchive` / `renameBatch` 都会调用 `rewriteBatchID(at:to:originalDirectory:)`,通过 `rebasePathsIfNeeded` 重写指向旧路径的字段,使外部带过来的批次能在本机继续工作。

### Figma 服务
`FigmaService` 是 `actor`,内部缓存 `<baseDirectory>/figma-cache`,通过 `FigmaHTTPTransport` 抽象注入(测试时用假 transport)。`loadPreviewAndResources` 触发懒加载预览图和子节点资源,产出 `FigmaLinkItem` 的更新副本。任何对图片缓存路径的变动都要同步更新 `BatchStore` 的归档逻辑。

### 链接解析
`FigmaLinkParser` 接受多行输入,识别 `https://www.figma.com/design/...` 链接(`@url` 前缀和"标题: @url"形式都支持),对 `fileKey + nodeId` 去重,并把 `node-id=2522-8028` 标准化为 `2522:8028`。新增链接形态时优先扩展 `parse(_:)` 与 `parseURL(_:)` 并补单测。

### 状态与持久化的两套 Store
- **`SettingsStore`** → `settings.json`:用户偏好(token / prompt 模板 / 默认输出目录 / 默认模式与并发度 / 默认调用策略)。`SettingsViewModel` 在 `settings` 变化时 300ms 防抖自动保存
- **`GenerateWorkspaceDraftStore`** → `generate-workspace-draft.json`:生成页"未提交工作台"的草稿(输入文本、解析后的条目、当前批次指针等),保证关闭/重启 App 后能恢复未保存的工作

修改 `AppSettings` / `GenerateWorkspaceDraft` 任何字段时,务必同时:
1. 更新 `Codable` 实现(常见做法是用 `decodeIfPresent` + 默认值,以兼容旧文件)
2. 更新对应 ViewModel 的 `@Published` 属性与 didSet 持久化钩子

### UI 入口
`RootView` 是 `TabView`,三个 Tab 对应 `GeneratePage` / `ViewerPage` / `SettingsPage`。窗口最小尺寸 1280×820。`FigBridgeAppDelegate` 在启动时设置 dock 图标和激活策略。

## 编码约定

- Swift 6 严格并发:Core 中的服务都是 `Sendable`(`AgentService` / `BatchStore` / `ShellClient` 都是 `struct/final class Sendable`,`FigmaService` 是 `actor`)。所有跨 actor 闭包都已标 `@Sendable`,新增回调签名必须沿用
- ViewModel 一律 `@MainActor final class ... ObservableObject`,后台工作通过 `Task { ... }` 或 `await` 服务方法发起
- 文件命名与首要类型一致(`GenerationCoordinator.swift` / `SettingsViewModelTests.swift`)
- 错误类型实现 `LocalizedError` 并提供中文 `errorDescription`,UI 直接展示 `error.localizedDescription`

## 待完善标记

待完善内容统一使用注释:`// TODO: xqm {#待完善说明#}`。
