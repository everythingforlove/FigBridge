import Foundation

public struct HarmonyProjectGenerationOptions: Equatable, Sendable {
    public var arkUIOptions: ArkUIGenerationOptions
    public var overwriteExistingFiles: Bool
    public var createTargetDirectory: Bool
    public var reportRelativePath: String

    public init(
        arkUIOptions: ArkUIGenerationOptions = ArkUIGenerationOptions(),
        overwriteExistingFiles: Bool = true,
        createTargetDirectory: Bool = true,
        reportRelativePath: String = "figbridge-harmony-report.md"
    ) {
        self.arkUIOptions = arkUIOptions
        self.overwriteExistingFiles = overwriteExistingFiles
        self.createTargetDirectory = createTargetDirectory
        self.reportRelativePath = reportRelativePath
    }
}

public struct HarmonyProjectGenerationResult: Equatable, Sendable {
    public var generatedFiles: [URL]
    public var copiedResources: [URL]
    public var resourceMappings: [ArkUIResourceMapping]
    public var warnings: [String]
    public var reportFile: URL
    public var report: HarmonyProjectGenerationReport

    public init(
        generatedFiles: [URL],
        copiedResources: [URL],
        resourceMappings: [ArkUIResourceMapping],
        warnings: [String],
        reportFile: URL,
        report: HarmonyProjectGenerationReport
    ) {
        self.generatedFiles = generatedFiles
        self.copiedResources = copiedResources
        self.resourceMappings = resourceMappings
        self.warnings = warnings
        self.reportFile = reportFile
        self.report = report
    }
}

public enum HarmonyProjectCheckStatus: String, Equatable, Sendable {
    case passed
    case warning
    case failed

    public var displayName: String {
        switch self {
        case .passed:
            "通过"
        case .warning:
            "警告"
        case .failed:
            "失败"
        }
    }
}

public struct HarmonyProjectCheck: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var status: HarmonyProjectCheckStatus
    public var detail: String

    public init(id: String, title: String, status: HarmonyProjectCheckStatus, detail: String) {
        self.id = id
        self.title = title
        self.status = status
        self.detail = detail
    }
}

public struct HarmonyProjectReviewItem: Equatable, Sendable, Identifiable {
    public var id: String
    public var nodeName: String
    public var nodePath: String
    public var warnings: [String]

    public init(id: String, nodeName: String, nodePath: String, warnings: [String]) {
        self.id = id
        self.nodeName = nodeName
        self.nodePath = nodePath
        self.warnings = warnings
    }
}

public struct HarmonyProjectGenerationReport: Equatable, Sendable {
    public var packageID: String
    public var screenName: String
    public var targetProjectPath: String
    public var generatedFilePaths: [String]
    public var copiedResourcePaths: [String]
    public var resourceMappings: [ArkUIResourceMapping]
    public var warnings: [String]
    public var reviewItems: [HarmonyProjectReviewItem]
    public var checks: [HarmonyProjectCheck]

    public init(
        packageID: String,
        screenName: String,
        targetProjectPath: String,
        generatedFilePaths: [String],
        copiedResourcePaths: [String],
        resourceMappings: [ArkUIResourceMapping],
        warnings: [String],
        reviewItems: [HarmonyProjectReviewItem],
        checks: [HarmonyProjectCheck]
    ) {
        self.packageID = packageID
        self.screenName = screenName
        self.targetProjectPath = targetProjectPath
        self.generatedFilePaths = generatedFilePaths
        self.copiedResourcePaths = copiedResourcePaths
        self.resourceMappings = resourceMappings
        self.warnings = warnings
        self.reviewItems = reviewItems
        self.checks = checks
    }

    public var markdown: String {
        var lines: [String] = [
            "# FigBridge Harmony 生成报告",
            "",
            "- 设计包: \(packageID)",
            "- 页面: \(screenName)",
            "- 目标项目: \(targetProjectPath)",
            ""
        ]

        lines.append("## 生成文件")
        if generatedFilePaths.isEmpty {
            lines.append("- 无")
        } else {
            lines.append(contentsOf: generatedFilePaths.map { "- \($0)" })
        }
        lines.append("")

        lines.append("## 资源文件")
        if copiedResourcePaths.isEmpty {
            lines.append("- 无")
        } else {
            lines.append(contentsOf: copiedResourcePaths.map { "- \($0)" })
        }
        lines.append("")

        lines.append("## 资源映射")
        if resourceMappings.isEmpty {
            lines.append("- 无")
        } else {
            lines.append(contentsOf: resourceMappings.map { "- \($0.sourcePath) -> \($0.targetPath) (`\($0.resourceName)`)" })
        }
        lines.append("")

        lines.append("## Warnings")
        if warnings.isEmpty {
            lines.append("- 无")
        } else {
            lines.append(contentsOf: warnings.map { "- \($0)" })
        }
        lines.append("")

        lines.append("## Needs Review")
        if reviewItems.isEmpty {
            lines.append("- 无")
        } else {
            for item in reviewItems {
                lines.append("- \(item.nodePath) [\(item.id)] \(item.nodeName)")
                for warning in item.warnings {
                    lines.append("  - \(warning)")
                }
            }
        }
        lines.append("")

        lines.append("## 检查")
        if checks.isEmpty {
            lines.append("- 未执行")
        } else {
            lines.append(contentsOf: checks.map { "- [\($0.status.displayName)] \($0.title): \($0.detail)" })
        }

        return lines.joined(separator: "\n")
    }
}

public enum HarmonyProjectGenerationError: LocalizedError, Equatable {
    case missingTargetDirectory(String)
    case missingPackageResource(String)
    case targetFileAlreadyExists(String)

    public var errorDescription: String? {
        switch self {
        case .missingTargetDirectory(let path):
            "目标 Harmony 项目目录不存在: \(path)"
        case .missingPackageResource(let path):
            "设计包资源不存在: \(path)"
        case .targetFileAlreadyExists(let path):
            "目标文件已存在: \(path)"
        }
    }
}

public struct HarmonyProjectGenerator: Sendable {
    private let arkUIGenerator: ArkUIGenerator

    public init(arkUIGenerator: ArkUIGenerator = ArkUIGenerator()) {
        self.arkUIGenerator = arkUIGenerator
    }

    public func generate(
        package: PersistedDesignPackage,
        targetProjectDirectory: URL,
        options: HarmonyProjectGenerationOptions = HarmonyProjectGenerationOptions()
    ) throws -> HarmonyProjectGenerationResult {
        let fileManager = FileManager.default
        if options.createTargetDirectory {
            try fileManager.createDirectory(at: targetProjectDirectory, withIntermediateDirectories: true)
        } else if !fileManager.fileExists(atPath: targetProjectDirectory.path) {
            throw HarmonyProjectGenerationError.missingTargetDirectory(targetProjectDirectory.path)
        }

        let generated = try arkUIGenerator.generate(design: package.design, options: options.arkUIOptions)
        var writtenFiles: [URL] = []
        var copiedResources: [URL] = []

        for file in generated.files {
            let targetURL = targetProjectDirectory.appendingPathComponent(file.relativePath)
            try writeFile(file.content, to: targetURL, overwrite: options.overwriteExistingFiles)
            writtenFiles.append(targetURL)
        }

        for mapping in generated.resources {
            let sourceURL = package.packageDirectory.appendingPathComponent(mapping.sourcePath)
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                throw HarmonyProjectGenerationError.missingPackageResource(mapping.sourcePath)
            }
            let targetURL = targetProjectDirectory.appendingPathComponent(mapping.targetPath)
            try copyResource(from: sourceURL, to: targetURL, overwrite: options.overwriteExistingFiles)
            copiedResources.append(targetURL)
        }

        let checks = makeChecks(
            generatedFiles: writtenFiles,
            copiedResources: copiedResources,
            generated: generated,
            targetProjectDirectory: targetProjectDirectory
        )
        let report = HarmonyProjectGenerationReport(
            packageID: package.manifest.packageID,
            screenName: package.design.screenName,
            targetProjectPath: targetProjectDirectory.path,
            generatedFilePaths: writtenFiles.map { relativePath(for: $0, baseDirectory: targetProjectDirectory) },
            copiedResourcePaths: copiedResources.map { relativePath(for: $0, baseDirectory: targetProjectDirectory) },
            resourceMappings: generated.resources,
            warnings: generated.warnings,
            reviewItems: collectReviewItems(in: package.design),
            checks: checks
        )
        let reportURL = targetProjectDirectory.appendingPathComponent(options.reportRelativePath)
        try writeFile(report.markdown, to: reportURL, overwrite: options.overwriteExistingFiles)

        return HarmonyProjectGenerationResult(
            generatedFiles: writtenFiles,
            copiedResources: copiedResources,
            resourceMappings: generated.resources,
            warnings: generated.warnings,
            reportFile: reportURL,
            report: report
        )
    }

    public func generate(
        packageDirectory: URL,
        packageStore: DesignPackageStore,
        targetProjectDirectory: URL,
        options: HarmonyProjectGenerationOptions = HarmonyProjectGenerationOptions()
    ) throws -> HarmonyProjectGenerationResult {
        let package = try packageStore.loadPackage(at: packageDirectory)
        return try generate(package: package, targetProjectDirectory: targetProjectDirectory, options: options)
    }

    private func writeFile(_ content: String, to targetURL: URL, overwrite: Bool) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: targetURL.path) {
            guard overwrite else {
                throw HarmonyProjectGenerationError.targetFileAlreadyExists(targetURL.path)
            }
            try fileManager.removeItem(at: targetURL)
        }
        try fileManager.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: targetURL, atomically: true, encoding: .utf8)
    }

    private func copyResource(from sourceURL: URL, to targetURL: URL, overwrite: Bool) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: targetURL.path) {
            guard overwrite else {
                throw HarmonyProjectGenerationError.targetFileAlreadyExists(targetURL.path)
            }
            try fileManager.removeItem(at: targetURL)
        }
        try fileManager.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.copyItem(at: sourceURL, to: targetURL)
    }

    private func makeChecks(
        generatedFiles: [URL],
        copiedResources: [URL],
        generated: ArkUIGenerationResult,
        targetProjectDirectory: URL
    ) -> [HarmonyProjectCheck] {
        let fileManager = FileManager.default
        var checks: [HarmonyProjectCheck] = []

        let missingGeneratedFiles = generatedFiles.filter { !fileManager.fileExists(atPath: $0.path) }
        checks.append(
            HarmonyProjectCheck(
                id: "generated-files-exist",
                title: "页面文件存在",
                status: missingGeneratedFiles.isEmpty ? .passed : .failed,
                detail: missingGeneratedFiles.isEmpty ? "\(generatedFiles.count) 个 .ets 文件已写入" : missingGeneratedFiles.map(\.path).joined(separator: ", ")
            )
        )

        let missingResources = copiedResources.filter { !fileManager.fileExists(atPath: $0.path) }
        checks.append(
            HarmonyProjectCheck(
                id: "resources-exist",
                title: "资源文件存在",
                status: missingResources.isEmpty ? .passed : .failed,
                detail: missingResources.isEmpty ? "\(copiedResources.count) 个资源文件已写入" : missingResources.map(\.path).joined(separator: ", ")
            )
        )

        let unresolvedResourceMappings = generated.resources.filter {
            !fileManager.fileExists(atPath: targetProjectDirectory.appendingPathComponent($0.targetPath).path)
        }
        checks.append(
            HarmonyProjectCheck(
                id: "resource-references-resolve",
                title: "资源引用可解析",
                status: unresolvedResourceMappings.isEmpty ? .passed : .failed,
                detail: unresolvedResourceMappings.isEmpty ? "所有 Image($r(...)) 资源均有目标文件" : unresolvedResourceMappings.map(\.targetPath).joined(separator: ", ")
            )
        )

        let etsContents = generated.files.map(\.content).joined(separator: "\n")
        let containsMarkdownFence = etsContents.contains("```")
        let hasBalancedDelimiters = delimitersAreBalanced(in: etsContents)
        checks.append(
            HarmonyProjectCheck(
                id: "ets-syntax-sanity",
                title: "ETS 基础静态检查",
                status: !containsMarkdownFence && hasBalancedDelimiters ? .passed : .failed,
                detail: !containsMarkdownFence && hasBalancedDelimiters ? "未发现 Markdown 代码块，括号和花括号数量匹配" : "存在 Markdown 代码块或括号/花括号不匹配"
            )
        )

        if generated.warnings.isEmpty {
            checks.append(
                HarmonyProjectCheck(
                    id: "warnings",
                    title: "Warnings",
                    status: .passed,
                    detail: "无 warning"
                )
            )
        } else {
            checks.append(
                HarmonyProjectCheck(
                    id: "warnings",
                    title: "Warnings",
                    status: .warning,
                    detail: "\(generated.warnings.count) 条 warning 需要追踪"
                )
            )
        }

        return checks
    }

    private func collectReviewItems(in design: DesignIR) -> [HarmonyProjectReviewItem] {
        collectReviewItems(in: design.rootNode, path: design.screenName)
    }

    private func collectReviewItems(in node: DesignNode, path: String) -> [HarmonyProjectReviewItem] {
        let currentPath = "\(path) / \(node.name)"
        var result: [HarmonyProjectReviewItem] = []
        if node.needsReview || !node.warnings.isEmpty {
            let warnings = node.warnings.isEmpty ? ["needsReview=true"] : node.warnings
            result.append(
                HarmonyProjectReviewItem(
                    id: node.id,
                    nodeName: node.name,
                    nodePath: currentPath,
                    warnings: warnings
                )
            )
        }
        for child in node.children {
            result.append(contentsOf: collectReviewItems(in: child, path: currentPath))
        }
        return result
    }

    private func delimitersAreBalanced(in content: String) -> Bool {
        var stack: [Character] = []
        let pairs: [Character: Character] = [")": "(", "}": "{", "]": "["]
        for character in content {
            if character == "(" || character == "{" || character == "[" {
                stack.append(character)
            } else if let opening = pairs[character] {
                guard stack.popLast() == opening else {
                    return false
                }
            }
        }
        return stack.isEmpty
    }

    private func relativePath(for url: URL, baseDirectory: URL) -> String {
        let basePath = baseDirectory.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(basePath + "/") else {
            return path
        }
        return String(path.dropFirst(basePath.count + 1))
    }
}
