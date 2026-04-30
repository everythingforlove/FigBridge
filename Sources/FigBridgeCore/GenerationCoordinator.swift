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

    public init(batchStore: BatchStore, agentRunner: AgentRunning) {
        self.batchStore = batchStore
        self.agentRunner = agentRunner
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
        let yamlDirectory = BatchStore.itemDirectory(in: batchDirectory, item: item).appendingPathComponent("yaml", isDirectory: true)
        try FileManager.default.createDirectory(at: yamlDirectory, withIntermediateDirectories: true)

        do {
            let result = try await agentRunner.run(provider: provider, prompt: prompt, item: item) { event in
                if let itemEvent {
                    await itemEvent(item.id, event)
                }
            }
            let yamlURL = yamlDirectory.appendingPathComponent("figma-node-\(BatchStore.pathSafe(item.nodeId)).yaml")
            let rawOutputURL = yamlDirectory.appendingPathComponent("agent-output.txt")
            try result.output.write(to: rawOutputURL, atomically: true, encoding: .utf8)
            try result.output.write(to: yamlURL, atomically: true, encoding: .utf8)
            resolvedItem.generatedYAMLPath = yamlURL.path
            resolvedItem.agentOutputPath = rawOutputURL.path
            resolvedItem.generationStatus = .success
            resolvedItem.errorMessage = nil
            resolvedItem.logSummary = "\(provider.displayName) 已执行：\(result.executablePath)"
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
                    yamlPath: nil,
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
        let outputMap = MultiYAMLOutputParser.parse(result.output)

        var completed = 0
        for index in resolvedItems.indices {
            let item = resolvedItems[index]
            let key = MultiYAMLOutputParser.ResultKey(fileKey: item.fileKey, nodeId: item.nodeId)
            guard let yamlText = outputMap[key], !yamlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                finalizeBatchItem(
                    &resolvedItems[index],
                    status: .failed,
                    errorMessage: "agent 输出缺少该链接的 YAML 分段",
                    yamlPath: nil,
                    agentOutputPath: rawOutputURL.path,
                    logSummary: "执行失败"
                )
                completed += 1
                if let progress {
                    await progress(completed, resolvedItems.count, resolvedItems[index])
                }
                continue
            }

            let yamlDirectory = BatchStore.itemDirectory(in: batchDirectory, item: item).appendingPathComponent("yaml", isDirectory: true)
            try FileManager.default.createDirectory(at: yamlDirectory, withIntermediateDirectories: true)
            let yamlURL = yamlDirectory.appendingPathComponent("figma-node-\(BatchStore.pathSafe(item.nodeId)).yaml")
            try yamlText.write(to: yamlURL, atomically: true, encoding: .utf8)

            finalizeBatchItem(
                &resolvedItems[index],
                status: .success,
                errorMessage: nil,
                yamlPath: yamlURL.path,
                agentOutputPath: rawOutputURL.path,
                logSummary: "\(provider.displayName) 已执行：\(result.executablePath)"
            )

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
        yamlPath: String?,
        agentOutputPath: String?,
        logSummary: String
    ) {
        item.generationStatus = status
        item.generatedYAMLPath = yamlPath
        item.agentOutputPath = agentOutputPath
        item.errorMessage = errorMessage
        item.logSummary = logSummary
    }

    private func makeBatchRawOutputURL(for item: FigmaLinkItem, batchDirectory: URL) -> URL {
        BatchStore.itemDirectory(in: batchDirectory, item: item)
            .appendingPathComponent("yaml", isDirectory: true)
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
    static func makeSinglePrompt(template: String, item: FigmaLinkItem) -> String {
        """
        \(template)

        Figma URL: \(item.url)
        File Key: \(item.fileKey)
        Node ID: \(item.nodeId)
        Title: \(item.title ?? "")
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
            """
        }.joined(separator: "\n\n")

        return """
        \(template)

        You will process multiple Figma links. Output one YAML for each link and strictly use the segmented format below:

        <<<FIGBRIDGE_YAML_START fileKey=<fileKey> nodeId=<nodeId>>>
        <YAML content>
        <<<FIGBRIDGE_YAML_END>>>

        Rules:
        1. Each input link must produce exactly one segment.
        2. The fileKey and nodeId in each segment must exactly match the input.
        3. Do not include markdown code block markers in YAML content.
        4. Do not output any explanatory text outside the segments above.

        Links to process:
        \(itemLines)
        """
    }
}

enum MultiYAMLOutputParser {
    struct ResultKey: Hashable {
        let fileKey: String
        let nodeId: String
    }

    static func parse(_ output: String) -> [ResultKey: String] {
        let pattern = #"<<<FIGBRIDGE_YAML_START\s+fileKey=([^\s>]+)\s+nodeId=([^\s>]+)>>>[\r\n]+([\s\S]*?)<<<FIGBRIDGE_YAML_END>>>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [:]
        }
        let source = output as NSString
        let matches = regex.matches(in: output, range: NSRange(location: 0, length: source.length))
        var result: [ResultKey: String] = [:]
        for match in matches where match.numberOfRanges == 4 {
            let fileKey = source.substring(with: match.range(at: 1))
            let nodeId = source.substring(with: match.range(at: 2))
            let yamlText = source.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespacesAndNewlines)
            result[ResultKey(fileKey: fileKey, nodeId: nodeId)] = yamlText
        }
        return result
    }
}
