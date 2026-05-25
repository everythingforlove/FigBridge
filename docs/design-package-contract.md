# FigBridge Design Package Contract

当前设计包格式固定为 JSON，不再使用 `design.yaml`。一个可导入包是一个目录或 zip 解压后的目录，最小结构如下：

```text
figbridge-package/
├── manifest.json
├── design.json
└── assets/
```

可选文件：

- `figma-node.json`：Figma 原始节点追溯信息。
- `preview.png` 或其他预览文件：仅允许放在包根目录。
- `assets/**`：DesignIR 引用的本地资源文件。

## Version Rules

- `manifest.schemaVersion` 当前值为 `figbridge-design-package/v1`。
- `design.version` 当前值为 `design-ir/v1`。
- 破坏性字段变更必须提升版本，并提供显式迁移逻辑或拒绝导入。
- 当前实现只接受 `manifest.designFile == "design.json"`，旧的 `design.yaml` 包会被明确拒绝。

## Manifest Rules

- `manifest.json` 是包入口，`manifest.json` 本身不参与 checksum。
- `packageID`、`source.figmaURL`、`source.fileKey`、`source.nodeId`、`source.exporter` 必填且非空。
- `manifest.targetPlatform` 必须与 `design.targetPlatform` 一致。
- `manifest.source.fileKey` 和 `manifest.source.nodeId` 必须与 `design.fileKey`、`design.nodeId` 一致。
- `assetsDirectory` 当前固定为 `assets`。

## Checksum Rules

- `manifest.checksums` 使用 SHA-256 小写 64 位十六进制字符串。
- 必须覆盖 `design.json`、可选根文件 `figma-node.json`/`preview.*`，以及 `assets/` 下的每一个文件。
- 不允许存在多余 checksum 条目。
- 任一文件缺失、checksum 缺失、多余或不匹配都会拒绝导入。

## Path Rules

- 所有路径使用 POSIX 相对路径。
- 不允许绝对路径、`~`、反斜杠、空路径、空路径片段、`.` 或 `..`。
- `designFile`、`figmaNodeFile`、`previewFile` 只能是包根目录文件名。
- `DesignAssetRef.localPath` 必须位于 `assets/` 下，且扩展名必须与 `format` 一致。
- 资源引用必须指向包内实际存在的文件，不允许 Figma CDN 或外部 URL 作为内网生成输入。

## DesignIR Rules

`design.json` 必须符合 [design-ir.schema.json](design-ir.schema.json)，Swift 侧还会执行补充校验：

- `viewport.width` 和 `viewport.height` 必须为正数。
- `rootNode.type` 必须是 `frame`。
- 所有 node id 在整棵树内必须唯一。
- `confidence` 必须在 `0...1`。
- bounds、spacing、padding、opacity、字号、行高等数值必须在有效范围内。
- token 名称不能为空，颜色 token 和文本样式 token 名称不能重复。
