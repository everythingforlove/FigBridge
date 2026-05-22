import Foundation

public protocol AgentRunning: Sendable {
    func run(
        provider: AgentProvider,
        prompt: String,
        item: FigmaLinkItem,
        eventHandler: (@Sendable (AgentRunEvent) async -> Void)?
    ) async throws -> AgentRunResult
}

extension AgentService: AgentRunning {
    public func run(
        provider: AgentProvider,
        prompt: String,
        item: FigmaLinkItem,
        eventHandler: (@Sendable (AgentRunEvent) async -> Void)?
    ) async throws -> AgentRunResult {
        try await runDetailed(provider: provider, prompt: prompt, eventHandler: eventHandler)
    }
}

public struct GenerationCoordinator: Sendable {
    public let batchStore: BatchStore
    public let agentRunner: AgentRunning
    private let resultParser: AgentGenerationResultParser

    public init(
        batchStore: BatchStore,
        agentRunner: AgentRunning,
        resultParser: AgentGenerationResultParser = AgentGenerationResultParser()
    ) {
        self.batchStore = batchStore
        self.agentRunner = agentRunner
        self.resultParser = resultParser
    }

    public func generate(
        agent: AgentProvider,
        promptTemplate: String,
        sourceInputText: String,
        outputDirectory: URL,
        mode: GenerationMode,
        parallelism: Int,
        callStrategy: AgentCallStrategy,
        existingBatchID: String? = nil,
        items: [FigmaLinkItem],
        itemStarted: (@Sendable (FigmaLinkItem) async -> Void)? = nil,
        progress: (@Sendable (Int, Int, FigmaLinkItem) async -> Void)? = nil,
        itemEvent: (@Sendable (UUID, AgentRunEvent) async -> Void)? = nil
    ) async throws -> PersistedBatch {
        let existingBatch = try existingBatchID.flatMap { try batchStore.loadBatch(id: $0) }
        let batchID = existingBatch?.summary.id ?? BatchNaming.makeBatchID()
        let batchDirectory = batchStore.batchDirectory(for: batchID)
        let exportsDirectory = batchStore.exportsDirectory(for: batchDirectory)
        try FileManager.default.createDirectory(at: batchDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: exportsDirectory, withIntermediateDirectories: true)

        let pendingItems = items.filter { $0.generatedYAMLPath == nil }
        let resolvedPendingItems: [FigmaLinkItem]

        switch callStrategy {
        case .singlePerLink:
            switch mode {
            case .sequential:
                resolvedPendingItems = try await runSequential(items: pendingItems, provider: agent, promptTemplate: promptTemplate, batchDirectory: batchDirectory, itemStarted: itemStarted, progress: progress, itemEvent: itemEvent)
            case .parallel:
                resolvedPendingItems = try await runParallel(items: pendingItems, provider: agent, promptTemplate: promptTemplate, batchDirectory: batchDirectory, parallelism: parallelism, itemStarted: itemStarted, progress: progress, itemEvent: itemEvent)
            }
        case .singleForBatch:
            resolvedPendingItems = try await runBatchSingleCall(items: pendingItems, provider: agent, promptTemplate: promptTemplate, batchDirectory: batchDirectory, itemStarted: itemStarted, progress: progress, itemEvent: itemEvent)
        }

        let resolvedMap = Dictionary(uniqueKeysWithValues: resolvedPendingItems.map { ($0.id, $0) })
        let resolvedItems = items.map { resolvedMap[$0.id] ?? $0 }

        if existingBatch == nil {
            let batch = GenerationBatch(
                id: batchID,
                createdAt: Date(),
                agent: agent,
                promptSnapshot: promptTemplate,
                sourceInputText: sourceInputText,
                outputDirectory: exportsDirectory.path,
                mode: mode,
                parallelism: parallelism,
                callStrategy: callStrategy,
                items: resolvedItems
            )
            return try batchStore.createBatch(batch)
        }

        return try batchStore.updateBatch(
            id: batchID,
            sourceInputText: sourceInputText,
            agent: agent,
            promptSnapshot: promptTemplate,
            outputDirectory: exportsDirectory,
            mode: mode,
            parallelism: parallelism,
            callStrategy: callStrategy,
            items: resolvedItems
        )
    }

    private func runSequential(items: [FigmaLinkItem], provider: AgentProvider, promptTemplate: String, batchDirectory: URL, itemStarted: (@Sendable (FigmaLinkItem) async -> Void)?, progress: (@Sendable (Int, Int, FigmaLinkItem) async -> Void)?, itemEvent: (@Sendable (UUID, AgentRunEvent) async -> Void)? = nil) async throws -> [FigmaLinkItem] {
        var resolved: [FigmaLinkItem] = []
        for (index, item) in items.enumerated() {
            try Task.checkCancellation()
            let result = try await runSingle(item: item, index: index, provider: provider, promptTemplate: promptTemplate, batchDirectory: batchDirectory, itemStarted: itemStarted, itemEvent: itemEvent)
            resolved.append(result)
            if let progress {
                await progress(index + 1, items.count, result)
            }
        }
        return resolved
    }

    private func runParallel(items: [FigmaLinkItem], provider: AgentProvider, promptTemplate: String, batchDirectory: URL, parallelism: Int, itemStarted: (@Sendable (FigmaLinkItem) async -> Void)?, progress: (@Sendable (Int, Int, FigmaLinkItem) async -> Void)?, itemEvent: (@Sendable (UUID, AgentRunEvent) async -> Void)?) async throws -> [FigmaLinkItem] {
        let limit = max(1, parallelism)
        var iterator = items.enumerated().makeIterator()
        var results = Array<FigmaLinkItem?>(repeating: nil, count: items.count)
        var completedCount = 0

        try await withThrowingTaskGroup(of: (Int, FigmaLinkItem).self) { group in
            for _ in 0..<min(limit, items.count) {
                guard let next = iterator.next() else {
                    break
                }
                group.addTask {
                    let resolved = try await runSingle(item: next.element, index: next.offset, provider: provider, promptTemplate: promptTemplate, batchDirectory: batchDirectory, itemStarted: itemStarted, itemEvent: itemEvent)
                    return (next.offset, resolved)
                }
            }

            while let completed = try await group.next() {
                try Task.checkCancellation()
                results[completed.0] = completed.1
                completedCount += 1
                if let progress {
                    await progress(completedCount, items.count, completed.1)
                }
                if let next = iterator.next() {
                    group.addTask {
                        let resolved = try await runSingle(item: next.element, index: next.offset, provider: provider, promptTemplate: promptTemplate, batchDirectory: batchDirectory, itemStarted: itemStarted, itemEvent: itemEvent)
                        return (next.offset, resolved)
                    }
                }
            }
        }

        return results.compactMap { $0 }
    }

    private func runSingle(item: FigmaLinkItem, index: Int, provider: AgentProvider, promptTemplate: String, batchDirectory: URL, itemStarted: (@Sendable (FigmaLinkItem) async -> Void)?, itemEvent: (@Sendable (UUID, AgentRunEvent) async -> Void)?) async throws -> FigmaLinkItem {
        var resolvedItem = item
        resolvedItem.generationStatus = .running
        resolvedItem.logSummary = "执行中"
        if let itemStarted {
            await itemStarted(resolvedItem)
        }
        try Task.checkCancellation()
        let prompt = PromptBuilder.makeSinglePrompt(template: promptTemplate, item: item)
        let designDirectory = makeDesignIRDirectory(for: item, batchDirectory: batchDirectory)
        try FileManager.default.createDirectory(at: designDirectory, withIntermediateDirectories: true)

        do {
            let result = try await agentRunner.run(provider: provider, prompt: prompt, item: item) { event in
                if let itemEvent {
                    await itemEvent(item.id, event)
                }
            }
            let designURL = makeDesignIRURL(for: item, batchDirectory: batchDirectory)
            let rawOutputURL = makeRawOutputURL(for: item, batchDirectory: batchDirectory)
            try result.output.write(to: rawOutputURL, atomically: true, encoding: .utf8)
            do {
                let parsed = try resultParser.parse(result.output, expectedItem: item)
                try parsed.normalizedJSON.write(to: designURL, atomically: true, encoding: .utf8)
                resolvedItem.generatedYAMLPath = designURL.path
                resolvedItem.agentOutputPath = rawOutputURL.path
                resolvedItem.generationStatus = .success
                resolvedItem.errorMessage = nil
                resolvedItem.logSummary = "\(provider.displayName) 已执行：\(result.executablePath)"
            } catch {
                resolvedItem.generatedYAMLPath = nil
                resolvedItem.agentOutputPath = rawOutputURL.path
                resolvedItem.generationStatus = .failed
                resolvedItem.errorMessage = error.localizedDescription
                resolvedItem.logSummary = "DesignIR 解析失败"
                if let itemEvent {
                    await itemEvent(item.id, .failed(message: error.localizedDescription))
                }
            }
        } catch is CancellationError {
            resolvedItem.generationStatus = .cancelled
            resolvedItem.generatedYAMLPath = nil
            resolvedItem.agentOutputPath = nil
            resolvedItem.errorMessage = nil
            resolvedItem.logSummary = "已取消"
            if let itemEvent {
                await itemEvent(item.id, .cancelled)
            }
        } catch {
            resolvedItem.generationStatus = .failed
            resolvedItem.generatedYAMLPath = nil
            resolvedItem.agentOutputPath = nil
            resolvedItem.errorMessage = error.localizedDescription
            resolvedItem.logSummary = "执行失败"
            if let itemEvent {
                await itemEvent(item.id, .failed(message: error.localizedDescription))
            }
        }

        return resolvedItem
    }

    private func runBatchSingleCall(
        items: [FigmaLinkItem],
        provider: AgentProvider,
        promptTemplate: String,
        batchDirectory: URL,
        itemStarted: (@Sendable (FigmaLinkItem) async -> Void)?,
        progress: (@Sendable (Int, Int, FigmaLinkItem) async -> Void)?,
        itemEvent: (@Sendable (UUID, AgentRunEvent) async -> Void)?
    ) async throws -> [FigmaLinkItem] {
        guard !items.isEmpty else {
            return []
        }

        var resolvedItems = items
        for index in resolvedItems.indices {
            resolvedItems[index].generationStatus = .running
            resolvedItems[index].logSummary = "执行中"
            resolvedItems[index].errorMessage = nil
            if let itemStarted {
                await itemStarted(resolvedItems[index])
            }
        }

        try Task.checkCancellation()
        let prompt = PromptBuilder.makeBatchPrompt(template: promptTemplate, items: items)
        let callItem = items[0]
        let result: AgentRunResult
        let rawOutputURL = makeBatchRawOutputURL(for: callItem, batchDirectory: batchDirectory)
        do {
            result = try await agentRunner.run(provider: provider, prompt: prompt, item: callItem) { event in
                if let itemEvent {
                    for item in items {
                        await itemEvent(item.id, event)
                    }
                }
            }
            try FileManager.default.createDirectory(at: rawOutputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try result.output.write(to: rawOutputURL, atomically: true, encoding: .utf8)
        } catch {
            var completed = 0
            for index in resolvedItems.indices {
                finalizeBatchItem(
                    &resolvedItems[index],
                    status: .failed,
                    errorMessage: error.localizedDescription,
                    designIRPath: nil,
                    agentOutputPath: nil,
                    logSummary: "执行失败"
                )
                if let itemEvent {
                    await itemEvent(resolvedItems[index].id, .failed(message: error.localizedDescription))
                }
                completed += 1
                if let progress {
                    await progress(completed, resolvedItems.count, resolvedItems[index])
                }
            }
            return resolvedItems
        }
        let outputMap = SegmentedAgentOutputParser.parse(result.output)

        var completed = 0
        for index in resolvedItems.indices {
            let item = resolvedItems[index]
            let key = SegmentedAgentOutputParser.ResultKey(fileKey: item.fileKey, nodeId: item.nodeId)
            guard let designText = outputMap[key], !designText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                finalizeBatchItem(
                    &resolvedItems[index],
                    status: .failed,
                    errorMessage: "agent 输出缺少该链接的 DesignIR 分段",
                    designIRPath: nil,
                    agentOutputPath: rawOutputURL.path,
                    logSummary: "执行失败"
                )
                if let itemEvent {
                    await itemEvent(item.id, .failed(message: resolvedItems[index].errorMessage ?? "agent 输出缺少该链接的 DesignIR 分段"))
                }
                completed += 1
                if let progress {
                    await progress(completed, resolvedItems.count, resolvedItems[index])
                }
                continue
            }

            let designDirectory = makeDesignIRDirectory(for: item, batchDirectory: batchDirectory)
            try FileManager.default.createDirectory(at: designDirectory, withIntermediateDirectories: true)
            let designURL = makeDesignIRURL(for: item, batchDirectory: batchDirectory)

            do {
                let parsed = try resultParser.parse(designText, expectedItem: item)
                try parsed.normalizedJSON.write(to: designURL, atomically: true, encoding: .utf8)
                finalizeBatchItem(
                    &resolvedItems[index],
                    status: .success,
                    errorMessage: nil,
                    designIRPath: designURL.path,
                    agentOutputPath: rawOutputURL.path,
                    logSummary: "\(provider.displayName) 已执行：\(result.executablePath)"
                )
            } catch {
                finalizeBatchItem(
                    &resolvedItems[index],
                    status: .failed,
                    errorMessage: error.localizedDescription,
                    designIRPath: nil,
                    agentOutputPath: rawOutputURL.path,
                    logSummary: "DesignIR 解析失败"
                )
                if let itemEvent {
                    await itemEvent(item.id, .failed(message: error.localizedDescription))
                }
            }

            completed += 1
            if let progress {
                await progress(completed, resolvedItems.count, resolvedItems[index])
            }
        }

        return resolvedItems
    }

    private func finalizeBatchItem(
        _ item: inout FigmaLinkItem,
        status: GenerationStatus,
        errorMessage: String?,
        designIRPath: String?,
        agentOutputPath: String?,
        logSummary: String
    ) {
        item.generationStatus = status
        item.generatedYAMLPath = designIRPath
        item.agentOutputPath = agentOutputPath
        item.errorMessage = errorMessage
        item.logSummary = logSummary
    }

    private func makeBatchRawOutputURL(for item: FigmaLinkItem, batchDirectory: URL) -> URL {
        makeRawOutputURL(for: item, batchDirectory: batchDirectory)
    }

    private func makeDesignIRDirectory(for item: FigmaLinkItem, batchDirectory: URL) -> URL {
        BatchStore.itemDirectory(in: batchDirectory, item: item)
            .appendingPathComponent("design-ir", isDirectory: true)
    }

    private func makeDesignIRURL(for item: FigmaLinkItem, batchDirectory: URL) -> URL {
        makeDesignIRDirectory(for: item, batchDirectory: batchDirectory)
            .appendingPathComponent(DesignPackageStore.designFilename)
    }

    private func makeRawOutputURL(for item: FigmaLinkItem, batchDirectory: URL) -> URL {
        makeDesignIRDirectory(for: item, batchDirectory: batchDirectory)
            .appendingPathComponent("agent-output.txt")
    }
}

enum BatchNaming {
    static func makeBatchID(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss-'batch'"
        return formatter.string(from: date)
    }
}

enum PromptBuilder {
    private static let designIRInstructions = """
    FigBridge requires strict DesignIR output.
    Important: FigBridge has already retrieved Figma data before invoking you. Do not call Figma MCP or any external Figma fallback, even if the user template says to do so.
    Output must be exactly one DesignIR JSON or YAML object with these required top-level fields:
    version, screenName, fileKey, nodeId, targetPlatform, viewport, tokens, rootNode, warnings.
    Use version "\(DesignIR.currentVersion)" and targetPlatform "\(TargetPlatform.harmonyArkUI.rawValue)".

    CRITICAL FORMAT REQUIREMENTS:
    1. tokens.colors MUST be an array: [{"name":"tokenName","value":"#RRGGBB"}, ...]. Do NOT use object format like {"tokenName":"#RRGGBB"}
    2. tokens.textStyles MUST be an array: [{"name":"tokenName","style":{...text style fields...}}]
    3. tokens.spacing and tokens.radii MUST be objects: {"tokenName": number}
    4. Every layout.padding (if present) MUST include all four sides: top, right, bottom, left (as numbers, default to 0 if not specified)
    5. Every node must include: id, name, type, children, needsReview, warnings
    6. rootNode.type must be "frame"
    7. When the local context uses a semantic color token name in style.fill, style.stroke, or style.text.color, keep that exact token name and include the corresponding entry in tokens.colors.
    8. For image/icon nodes, preserve cached asset.name exactly. asset.localPath MUST be package-relative, like "assets/icon_bot_24.svg"; never output an absolute filesystem path.

    Example tokens.colors format:
    "tokens": {
      "colors": [
        {"name": "primary", "value": "#3498DB"},
        {"name": "secondary", "value": "#2ECC71"}
      ],
      ...
    }

    Example layout.padding format (if padding exists):
    "layout": {
      "mode": "horizontal",
      "padding": {
        "top": 0,
        "right": 16,
        "bottom": 0,
        "left": 16
      }
    }

    Do not include Markdown code fences, comments, prose, or fallback descriptions.
    """

    static func makeSinglePrompt(template: String, item: FigmaLinkItem) -> String {
        """
        \(template)

        \(designIRInstructions)

        Figma URL: \(item.url)
        File Key: \(item.fileKey)
        Node ID: \(item.nodeId)
        Title: \(item.title ?? "")
        Node Name: \(item.nodeName ?? "")

        \(figmaContextInstructions(for: item))
        """
    }

    static func makeBatchPrompt(template: String, items: [FigmaLinkItem]) -> String {
        let itemLines = items.enumerated().map { index, item in
            """
            [\(index + 1)]
            Figma URL: \(item.url)
            File Key: \(item.fileKey)
            Node ID: \(item.nodeId)
            Title: \(item.title ?? "")
            Node Name: \(item.nodeName ?? "")

            \(figmaContextInstructions(for: item))
            """
        }.joined(separator: "\n\n")

        return """
        \(template)

        \(designIRInstructions)

        You will process multiple Figma links. Output one DesignIR JSON/YAML object for each link and strictly use the segmented format below:

        <<<FIGBRIDGE_DESIGN_IR_START fileKey=<fileKey> nodeId=<nodeId>>>
        <DesignIR JSON/YAML content>
        <<<FIGBRIDGE_DESIGN_IR_END>>>

        Rules:
        1. Each input link must produce exactly one segment.
        2. The fileKey and nodeId in each segment must exactly match the input.
        3. Do not include markdown code block markers in DesignIR content.
        4. Do not output any explanatory text outside the segments above.

        Links to process:
        \(itemLines)
        """
    }

    private static func figmaContextInstructions(for item: FigmaLinkItem) -> String {
        var lines: [String] = [
            "FigBridge local Figma context:",
            "- Do not fetch this Figma node again.",
            "- Treat the local DesignIR seed as the primary source of truth when present.",
            "- The local seed may already resolve Figma semantic colors to tokens.colors and icon/image nodes to cached local library assets.",
        ]

        if let previewImagePath = item.previewImagePath {
            lines.append("- Preview image path: \(previewImagePath)")
        }
        if let figmaNodeJSONPath = item.figmaNodeJSONPath {
            lines.append("- Raw Figma node JSON path: \(figmaNodeJSONPath)")
        }
        if let figmaDerivedDesignIRPath = item.figmaDerivedDesignIRPath {
            lines.append("- FigBridge-derived DesignIR seed path: \(figmaDerivedDesignIRPath)")
            if let context = inlineFileContext(at: figmaDerivedDesignIRPath) {
                lines.append(
                    """
                    FigBridge-derived DesignIR seed content:
                    <<<FIGBRIDGE_LOCAL_DESIGN_IR_CONTEXT_START>>>
                    \(context)
                    <<<FIGBRIDGE_LOCAL_DESIGN_IR_CONTEXT_END>>>
                    """
                )
            }
        }

        if !item.resourceItems.isEmpty {
            let resources = item.resourceItems.map { resource in
                let cachedPath = resource.localPath ?? ""
                let assetPath = cachedPath.isEmpty ? "" : DesignIRAssetPathNormalizer.packageRelativeAssetPath(fromCachedPath: cachedPath)
                return "- \(resource.name) [\(resource.kind.rawValue), \(resource.format.rawValue)] asset.localPath=\(assetPath) cachedFile=\(cachedPath)"
            }.joined(separator: "\n")
            lines.append("Cached resources:\n\(resources)")
        }

        if item.figmaDerivedDesignIRPath == nil {
            lines.append("- No local DesignIR seed is available. Create the best strict DesignIR you can from the provided metadata and include a warning about missing local Figma context.")
        }

        return lines.joined(separator: "\n")
    }

    private static func inlineFileContext(at path: String) -> String? {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }
        let limit = 60_000
        guard text.count > limit else {
            return text
        }
        let prefix = text.prefix(limit)
        return "\(prefix)\n... truncated by FigBridge after \(limit) characters; read the local file path above if more context is needed."
    }
}

enum SegmentedAgentOutputParser {
    struct ResultKey: Hashable {
        let fileKey: String
        let nodeId: String
    }

    static func parse(_ output: String) -> [ResultKey: String] {
        let pattern = #"<<<FIGBRIDGE_(?:DESIGN_IR|YAML)_START\s+fileKey=([^\s>]+)\s+nodeId=([^\s>]+)>>>[\r\n]+([\s\S]*?)<<<FIGBRIDGE_(?:DESIGN_IR|YAML)_END>>>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [:]
        }
        let source = output as NSString
        let matches = regex.matches(in: output, range: NSRange(location: 0, length: source.length))
        var result: [ResultKey: String] = [:]
        for match in matches where match.numberOfRanges == 4 {
            let fileKey = source.substring(with: match.range(at: 1))
            let nodeId = source.substring(with: match.range(at: 2))
            let designText = source.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespacesAndNewlines)
            result[ResultKey(fileKey: fileKey, nodeId: nodeId)] = designText
        }
        return result
    }
}
