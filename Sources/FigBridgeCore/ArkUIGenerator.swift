import Foundation

public struct ArkUIGenerationOptions: Equatable, Sendable {
    public var pageName: String?
    public var pagesDirectory: String
    public var mediaDirectory: String
    public var mediaResourcePrefix: String

    public init(
        pageName: String? = nil,
        pagesDirectory: String = "entry/src/main/ets/pages",
        mediaDirectory: String = "entry/src/main/resources/base/media",
        mediaResourcePrefix: String = "app.media"
    ) {
        self.pageName = pageName
        self.pagesDirectory = pagesDirectory
        self.mediaDirectory = mediaDirectory
        self.mediaResourcePrefix = mediaResourcePrefix
    }
}

public struct ArkUIGeneratedFile: Equatable, Sendable {
    public var relativePath: String
    public var content: String

    public init(relativePath: String, content: String) {
        self.relativePath = relativePath
        self.content = content
    }
}

public struct ArkUIResourceMapping: Equatable, Sendable {
    public var sourcePath: String
    public var targetPath: String
    public var resourceName: String

    public init(sourcePath: String, targetPath: String, resourceName: String) {
        self.sourcePath = sourcePath
        self.targetPath = targetPath
        self.resourceName = resourceName
    }
}

public struct ArkUIGenerationResult: Equatable, Sendable {
    public var files: [ArkUIGeneratedFile]
    public var resources: [ArkUIResourceMapping]
    public var warnings: [String]

    public init(files: [ArkUIGeneratedFile], resources: [ArkUIResourceMapping] = [], warnings: [String] = []) {
        self.files = files
        self.resources = resources
        self.warnings = warnings
    }
}

public enum ArkUIGeneratorError: LocalizedError, Equatable {
    case invalidDesignIR(String)

    public var errorDescription: String? {
        switch self {
        case .invalidDesignIR(let message):
            "ArkUI 生成失败: \(message)"
        }
    }
}

public struct ArkUIGenerator: Sendable {
    private let validator: DesignIRValidator

    public init(validator: DesignIRValidator = DesignIRValidator()) {
        self.validator = validator
    }

    public func generate(design: DesignIR, options: ArkUIGenerationOptions = ArkUIGenerationOptions()) throws -> ArkUIGenerationResult {
        do {
            try validator.validate(design)
        } catch {
            throw ArkUIGeneratorError.invalidDesignIR(error.localizedDescription)
        }

        var warnings = design.warnings
        var resources: [ArkUIResourceMapping] = []
        var usedResourceNames = Set<String>()
        let pageName = sanitizeTypeName(options.pageName ?? design.screenName)
        let body = emitNode(
            design.rootNode,
            level: 2,
            options: options,
            resources: &resources,
            usedResourceNames: &usedResourceNames,
            warnings: &warnings
        )
        let content = """
        @Entry
        @Component
        struct \(pageName) {
          build() {
        \(body)
          }
        }
        """

        let relativePath = "\(options.pagesDirectory)/\(pageName).ets"
        return ArkUIGenerationResult(
            files: [ArkUIGeneratedFile(relativePath: relativePath, content: content)],
            resources: resources,
            warnings: Array(Set(warnings)).sorted()
        )
    }

    private func emitNode(
        _ node: DesignNode,
        level: Int,
        options: ArkUIGenerationOptions,
        resources: inout [ArkUIResourceMapping],
        usedResourceNames: inout Set<String>,
        warnings: inout [String]
    ) -> String {
        warnings.append(contentsOf: node.warnings.map { "\(node.name): \($0)" })
        if node.needsReview {
            warnings.append("\(node.name) 需要人工复核")
        }

        let indent = indentation(level)
        let childIndent = indentation(level + 1)
        let componentStart: String
        var emittedChildren = ""

        switch node.type {
        case .text:
            componentStart = "\(indent)Text('\(escapeString(node.text ?? node.name))')"
        case .image, .icon:
            if let asset = node.asset {
                let resourceName = uniqueResourceName(for: asset, usedResourceNames: &usedResourceNames)
                resources.append(
                    ArkUIResourceMapping(
                        sourcePath: asset.localPath,
                        targetPath: "\(options.mediaDirectory)/\(resourceName).\(asset.format.rawValue)",
                        resourceName: resourceName
                    )
                )
                componentStart = "\(indent)Image($r('\(options.mediaResourcePrefix).\(resourceName)'))"
            } else {
                warnings.append("\(node.name) 缺少图片资源，已降级为空 Stack")
                componentStart = "\(indent)Stack()"
            }
        case .button:
            if node.children.isEmpty {
                componentStart = "\(indent)Button('\(escapeString(node.text ?? node.name))')"
            } else {
                componentStart = "\(indent)Button() {"
                emittedChildren = node.children.map {
                    emitNode($0, level: level + 1, options: options, resources: &resources, usedResourceNames: &usedResourceNames, warnings: &warnings)
                }.joined(separator: "\n")
            }
        case .input:
            componentStart = "\(indent)TextInput({ placeholder: '\(escapeString(node.text ?? node.name))' })"
        case .frame, .list, .unknown:
            componentStart = "\(indent)\(containerExpression(for: node, warnings: &warnings)) {"
            emittedChildren = node.children.map {
                emitNode($0, level: level + 1, options: options, resources: &resources, usedResourceNames: &usedResourceNames, warnings: &warnings)
            }.joined(separator: "\n")
        }

        var lines: [String] = [componentStart]
        if !emittedChildren.isEmpty {
            lines.append(emittedChildren)
            lines.append("\(indent)}")
        } else if componentStart.hasSuffix("{") {
            lines.append("\(childIndent)// TODO: 补充 \(node.name) 的内容")
            lines.append("\(indent)}")
        }

        lines.append(contentsOf: modifierLines(for: node, level: level))
        return lines.joined(separator: "\n")
    }

    private func containerExpression(for node: DesignNode, warnings: inout [String]) -> String {
        let layout = node.layout?.mode ?? .none
        switch layout {
        case .vertical:
            if let spacing = node.layout?.spacing {
                return "Column({ space: \(formatNumber(spacing)) })"
            }
            return "Column()"
        case .horizontal:
            if let spacing = node.layout?.spacing {
                return "Row({ space: \(formatNumber(spacing)) })"
            }
            return "Row()"
        case .wrap:
            return "Flex({ wrap: FlexWrap.Wrap })"
        case .absolute:
            warnings.append("\(node.name) 使用绝对布局，已生成 Stack，需人工检查响应式效果")
            return "Stack()"
        case .none:
            if !node.children.isEmpty {
                warnings.append("\(node.name) 缺少布局方向，已生成 Stack")
            }
            return "Stack()"
        }
    }

    private func modifierLines(for node: DesignNode, level: Int) -> [String] {
        let indent = indentation(level + 1)
        var lines: [String] = []

        if let bounds = node.bounds {
            if bounds.width > 0 {
                lines.append("\(indent).width(\(formatNumber(bounds.width)))")
            }
            if bounds.height > 0 {
                lines.append("\(indent).height(\(formatNumber(bounds.height)))")
            }
        }

        if let padding = node.layout?.padding {
            lines.append("\(indent).padding({ top: \(formatNumber(padding.top)), right: \(formatNumber(padding.right)), bottom: \(formatNumber(padding.bottom)), left: \(formatNumber(padding.left)) })")
        }

        if let style = node.style {
            if let fill = style.fill {
                lines.append("\(indent).backgroundColor('\(escapeString(fill))')")
            }
            if let cornerRadius = style.cornerRadius {
                lines.append("\(indent).borderRadius(\(formatNumber(cornerRadius)))")
            }
            if let opacity = style.opacity {
                lines.append("\(indent).opacity(\(formatNumber(opacity)))")
            }
            if style.stroke != nil || style.strokeWidth != nil {
                let color = style.stroke.map { "'\(escapeString($0))'" } ?? "'#000000'"
                let width = formatNumber(style.strokeWidth ?? 1)
                lines.append("\(indent).border({ width: \(width), color: \(color) })")
            }
            if let textStyle = style.text {
                lines.append(contentsOf: textModifierLines(for: textStyle, indent: indent))
            }
        }

        return lines
    }

    private func textModifierLines(for style: DesignTextStyle, indent: String) -> [String] {
        var lines: [String] = []
        if let fontSize = style.fontSize {
            lines.append("\(indent).fontSize(\(formatNumber(fontSize)))")
        }
        if let color = style.color {
            lines.append("\(indent).fontColor('\(escapeString(color))')")
        }
        if let lineHeight = style.lineHeight {
            lines.append("\(indent).lineHeight(\(formatNumber(lineHeight)))")
        }
        if let fontWeight = style.fontWeight {
            lines.append("\(indent).fontWeight(\(fontWeightExpression(fontWeight)))")
        }
        if let textAlign = style.textAlign, let expression = textAlignExpression(textAlign) {
            lines.append("\(indent).textAlign(\(expression))")
        }
        return lines
    }

    private func fontWeightExpression(_ value: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let numeric = Int(normalized) {
            if numeric >= 700 {
                return "FontWeight.Bold"
            }
            if numeric >= 500 {
                return "FontWeight.Medium"
            }
            return "FontWeight.Regular"
        }
        if normalized.contains("bold") {
            return "FontWeight.Bold"
        }
        if normalized.contains("medium") || normalized.contains("semi") {
            return "FontWeight.Medium"
        }
        return "FontWeight.Regular"
    }

    private func textAlignExpression(_ value: String) -> String? {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "left", "start":
            return "TextAlign.Start"
        case "center", "middle":
            return "TextAlign.Center"
        case "right", "end":
            return "TextAlign.End"
        default:
            return nil
        }
    }

    private func uniqueResourceName(for asset: DesignAssetRef, usedResourceNames: inout Set<String>) -> String {
        let rawName = asset.name.isEmpty ? URL(fileURLWithPath: asset.localPath).deletingPathExtension().lastPathComponent : asset.name
        let baseName = sanitizeResourceName(rawName)
        var candidate = baseName
        var index = 2
        while usedResourceNames.contains(candidate) {
            candidate = "\(baseName)_\(index)"
            index += 1
        }
        usedResourceNames.insert(candidate)
        return candidate
    }

    private func sanitizeTypeName(_ value: String) -> String {
        let words = value.split { !$0.isLetter && !$0.isNumber }
        let joined = words.map { word in
            let lower = word.lowercased()
            return lower.prefix(1).uppercased() + String(lower.dropFirst())
        }.joined()
        let candidate = joined.isEmpty ? "GeneratedPage" : joined
        guard let first = candidate.first, first.isLetter || first == "_" else {
            return "Generated\(candidate)"
        }
        return candidate
    }

    private func sanitizeResourceName(_ value: String) -> String {
        let mapped = value.lowercased().map { character -> Character in
            if character.isLetter || character.isNumber {
                return character
            }
            return "_"
        }
        let collapsed = String(mapped)
            .replacingOccurrences(of: "_{2,}", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        let candidate = collapsed.isEmpty ? "asset" : collapsed
        guard let first = candidate.first, first.isLetter || first == "_" else {
            return "asset_\(candidate)"
        }
        return candidate
    }

    private func escapeString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")
    }

    private func formatNumber(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.2f", value).replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    }

    private func indentation(_ level: Int) -> String {
        String(repeating: "  ", count: level)
    }
}
