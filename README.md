# FigBridge

macOS 原生 `SwiftUI` Figma DesignIR 工作台，采用 `MVVM` 架构。

当前仓库已实现首版工程骨架与核心链路：

- `生成` 页：解析多行 Figma `design` 链接、检测 `claude` / `codex`、顺序或并发生成 DesignIR
- `查看` 页：扫描批次目录、查看 DesignIR、导出 zip、从 zip 导入批次
- `设置` 页：保存 Figma Token、默认 Prompt、默认输出目录、预览图片格式
- `Figma REST API`：节点元数据、节点预览图、图片资源解析与本地缓存

## 工程结构

- `Sources/FigBridgeCore`
  - 领域模型
  - 链接解析
  - Agent 检测/执行
  - Figma REST API 服务
  - 批次存储与导入导出
  - 生成协调器
- `Sources/FigBridgeApp`
  - SwiftUI App 入口
  - 三页视图
  - ViewModel

## 运行

```bash
swift run FigBridge
```

## 测试

```bash
swift test
```

## 质量门禁

本地与 CI 共用同一套检查：

```bash
./scripts/ci-checks.sh
```

当前门禁包含：

- 禁止常见生成物或本地缓存进入版本库
- 校验已跟踪 JSON 文件语法
- 执行 `git diff --check`
- 执行 `swift build`
- 执行 `swift test`

## 打包 DMG

```bash
./scripts/package-dmg.sh arm64
./scripts/package-dmg.sh x86_64
```

## 内网鸿蒙生成方案

如果实际项目位于内网、无法访问当前外网大模型，仅能使用 MiniMax，建议采用“外网生成离线设计包 + 内网确定性生成 ArkUI 代码”的两阶段方案。详见 [docs/IntranetHarmonyPlan.md](docs/IntranetHarmonyPlan.md)。

产物分别输出到：

- `dist/FigBridge-arm64.dmg`：Apple Silicon Mac
- `dist/FigBridge-x86_64.dmg`：Intel Mac（含 macOS 12）

脚本会先执行对应架构的 `swift build -c release --arch <arch>`，再组装 `FigBridge.app` 并打包为 `dmg`。打包前会校验二进制架构与最低系统版本仍为 `macOS 12.0`。

DMG 内同时包含：

- `Applications` 快捷方式（用于拖拽安装）
- `Fix Quarantine.command`（拖入应用后双击，一键执行 `xattr -rd com.apple.quarantine /Applications/FigBridge.app`）
- `安装说明.txt`

## 当前已实现的关键行为

- 支持解析：
  - `@url`
  - `描述: @url`
  - 多行混合输入
- 以 `fileKey + nodeId` 去重
- 节点 `node-id` 自动标准化为 `2522:8028`
- 启动时检测本机 `claude` / `codex`
- 选中生成条目时懒加载 Figma 预览和资源
- 批次目录写入 `batch.json`、`meta.json`、`source-input.txt`
- 支持目录导入、zip 导出、zip 导入

## 当前未完成

- 查看页的批次删除、目录打开
- 系统文件选择器接入
- 节点 `PNG/SVG` 单独导出按钮
- 生成过程取消、中断恢复、进度展示
- 更完整的 Figma 节点遍历和资源分类
- `.xcodeproj` 工程文件
