# FigBridge 内网鸿蒙生成方案

## 背景判断

当前 FigBridge 的核心能力是把 Figma 链接交给外部 agent，生成并保存 YAML。这个模式适合外网，因为 agent 可以访问 Figma、MCP 和通用大模型；但实际项目在内网，只能使用 MiniMax 时，如果继续让模型直接从 Figma 链接推断鸿蒙 UI，准确性和可复现性都会不稳定。

更稳妥的边界是：

- 外网阶段负责读取 Figma、理解设计、固化中间产物。
- 内网阶段只消费离线设计包，不再访问 Figma。
- MiniMax 在内网只做受控补全、局部修复和项目适配。
- 鸿蒙 ArkUI/ArkTS 代码生成尽量由确定性模板和规则完成。

MiniMax 官方提供 OpenAI 兼容的 Chat Completions 接口，适合做成可配置 provider。内网环境可以通过 MiniMax 私有网关或统一模型服务暴露兼容接口，FigBridge 不应该绑定公网地址。

参考：

- MiniMax OpenAI 兼容接口：https://platform.minimax.io/docs/api-reference/text-openai-api
- MiniMax Chat Completions：https://platform.minimax.io/docs/api-reference/text-chat

## 推荐方案：外网设计包 + 内网确定性生成

### 1. 外网阶段：生成离线设计包

外网仍然允许使用 Figma、Figma MCP、REST API 和能力更强的大模型。但外网输出不应该是项目代码，而应该是可校验的设计中间表示。

建议导出一个 zip 包：

```text
figbridge-package.zip
├── manifest.json
├── design.json
├── figma-node.json
├── preview.png
└── assets/
    ├── image-001.png
    └── icon-001.svg
```

`design.json` 需要成为稳定 schema，而不是自由文本。建议包含：

- 页面信息：`screenName`、`fileKey`、`nodeId`、设计尺寸、目标设备。
- 设计 token：颜色、字号、字体、圆角、间距、阴影。
- 树结构：Frame、Text、Image、Icon、Button、List、Input 等节点。
- 布局信息：auto layout 方向、间距、padding、alignment、absolute bounds。
- 资源引用：使用本地 assets 路径，不使用 Figma CDN。
- 交互意图：点击、跳转、状态、表单校验，只记录可见或明确的信息。
- 不确定项：`warnings`、`confidence`、`needsReview`。

外网阶段可以使用大模型，但必须经过校验：

- JSON 可解析。
- 符合 JSON Schema 或 Swift Codable 模型。
- 所有资源路径存在。
- 不允许出现解释性 Markdown。
- 保留 Figma 原始节点 JSON 作为追溯依据。

### 2. 内网阶段：导入设计包

内网 FigBridge 不再接受 Figma 链接作为核心输入，而是接受外网导出的 `figbridge-package.zip`。

导入时执行：

- 校验 `manifest.json` 版本。
- 校验 checksum，防止资产缺失。
- 解析 `design.json` 为强类型模型。
- 展示预览图、节点树、风险项。
- 允许人工修改目标页面名、模块名、资源命名和组件映射。

### 3. 内网阶段：确定性生成 ArkUI 代码

鸿蒙代码生成应优先走规则和模板，而不是让 MiniMax 从头写。

建议新增 `ArkUIGenerator`，输入为 `DesignIR`，输出为：

```text
entry/src/main/ets/pages/<ScreenName>.ets
entry/src/main/resources/base/media/*
entry/src/main/resources/base/profile/main_pages.json
```

映射规则示例：

- Figma Auto Layout 垂直方向 -> ArkUI `Column`
- Figma Auto Layout 水平方向 -> ArkUI `Row`
- Wrap 或复杂排列 -> ArkUI `Flex`
- 文本节点 -> `Text`
- 图片填充或导出资源 -> `Image($r("app.media.xxx"))`
- 圆角 -> `.borderRadius(...)`
- 填充色 -> `.backgroundColor(...)`
- 字号 -> `.fontSize(...fp)`
- 宽高 -> `.width(...vp)`、`.height(...vp)`
- 间距 -> `.padding(...)`、`.margin(...)`

复杂布局需要降级策略：

- 可结构化 auto layout：生成自适应 ArkUI。
- 非 auto layout 但 bounds 清晰：生成半绝对布局，并标记 `needsReview`。
- 模糊交互、组件变体、多状态弹窗：生成骨架和 TODO 标记。

### 4. MiniMax 在内网的角色

MiniMax 不建议直接承担完整 Figma 到 ArkUI 生成。更适合以下受控任务：

- 根据内网项目已有代码风格，选择已有组件名和资源命名。
- 将确定性生成的 ArkTS 做小范围格式优化。
- 根据编译错误给出局部修复 patch。
- 将 `needsReview` 节点转换成人类可读的检查清单。
- 生成页面 ViewModel、mock 数据或注释，但不覆盖核心 UI 布局规则。

MiniMax 输出也要受控：

- 使用固定 JSON 输出格式。
- 禁止自由解释性文本。
- 禁止直接覆盖整页文件，优先输出 patch 或建议。
- 每次输出后运行格式化、静态检查和编译。

## 对当前 FigBridge 的改造建议

### 阶段一：保留现有功能，新增离线包能力

新增模型：

- `DesignPackageManifest`
- `DesignIR`
- `DesignNode`
- `DesignTokenSet`
- `TargetPlatform`
- `ArkUIGenerationResult`

新增服务：

- `DesignPackageImporter`
- `DesignPackageExporter`
- `DesignIRValidator`

UI 改动：

- 生成页保留 Figma 链接输入，用于外网生成设计包。
- 查看页新增“导入设计包”。
- 详情页展示 `design.json` 的结构化树，而不只是原始文本。

### 阶段二：新增 MiniMax provider

将当前 `AgentProvider` 从 `claude/codex` 扩展为通用 provider：

```swift
enum LLMProviderKind {
    case claudeCLI
    case codexCLI
    case openAICompatibleHTTP
}
```

新增 MiniMax 设置项：

- Base URL：内网模型网关地址。
- API Key：如果内网网关需要。
- Model：例如由内网平台配置的 MiniMax 模型名。
- Streaming：是否启用流式输出。
- Timeout。

这样 MiniMax 不写死公网配置，也能复用 OpenAI 兼容协议。

### 阶段三：新增 ArkUI 生成器

建议把 ArkUI 生成放在 `FigBridgeCore`，保持可测试：

```text
Sources/FigBridgeCore/
├── DesignIR/
├── DesignPackage/
└── ArkUI/
    ├── ArkUIGenerator.swift
    ├── ArkUIComponentMapper.swift
    ├── ArkUIStyleEmitter.swift
    └── ArkUIResourceWriter.swift
```

测试重点：

- Figma auto layout 到 Row/Column 的映射。
- Text 样式到 ArkUI modifier 的映射。
- 资源名稳定生成。
- 嵌套节点顺序稳定。
- 相同输入生成相同输出。
- `needsReview` 节点不会被静默吞掉。

### 阶段四：接入内网项目验证

内网生成后必须跑项目级验证，而不是只看文本：

- ArkTS/ETS 语法检查。
- Harmony 工程构建。
- 资源引用检查。
- 页面注册检查。
- 可选截图比对。

如果内网没有完整 DevEco 命令行环境，也至少要做静态检查：

- 文件路径存在。
- `Image($r(...))` 引用资源存在。
- 括号和闭包结构平衡。
- 禁止输出 Markdown。
- 禁止输出不存在的组件导入。

## 全新方案：拆成两套工具

如果希望更干净，可以拆成两个独立工具，而不是让一个桌面 App 贯穿外网和内网。

### 外网工具：FigBridge Exporter

职责：

- 输入 Figma 链接。
- 调用 Figma MCP/REST。
- 导出离线设计包。
- 生成校验报告。

形态可以是现有 FigBridge 的外网模式，也可以做成 CLI。

### 内网工具：Harmony Bridge

职责：

- 导入离线设计包。
- 映射内网组件库。
- 生成 ArkUI/ArkTS。
- 调用 MiniMax 做局部补全。
- 运行内网工程校验。

这个工具可以更贴近实际项目目录，支持直接选择目标模块、页面路径、资源目录。

### 共享部分：Schema 与测试夹具

两端必须共享：

- `design-ir.schema.json`
- 示例设计包。
- golden output。
- 版本迁移规则。

这能避免外网产物和内网生成器各说各话。

## 推荐落地顺序

1. 定义 `DesignIR v1` schema。
2. 把当前设计理解 prompt 改为严格输出 `DesignIR v1` JSON。
3. 新增设计包 zip 导出和导入。
4. 实现最小 ArkUI 规则生成器，只覆盖 `Column`、`Row`、`Text`、`Image`、基础样式。
5. 加 MiniMax HTTP provider，但只用于“项目适配”和“错误修复”。
6. 接一个真实内网页面做 golden test。
7. 再扩展 Button、List、Input、Tabs、弹窗等组件。

## 风险与取舍

- 如果继续让 MiniMax 直接生成完整页面，短期快，但长期不可控。
- 如果先做 `DesignIR` 和确定性生成器，初期慢，但能持续提升准确率。
- 外网大模型应该用于“理解设计”，内网 MiniMax 应该用于“适配项目”，这条边界最重要。
- 对实际业务项目，组件库映射比模型能力更关键。需要尽早沉淀“Figma 组件名 -> 内网 ArkUI 组件”的映射表。

## 对当前产品定位的建议

FigBridge 可以从“Figma YAML 工作台”升级为“三段式桥接工具”：

1. 设计采集：Figma -> 离线设计包。
2. 设计审查：离线包 -> 可校验 DesignIR。
3. 项目生成：DesignIR -> Harmony ArkUI 项目代码。

这样既保留外网能力，又符合内网只能用 MiniMax 的现实限制。
