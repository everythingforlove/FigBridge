import Foundation
import Testing
@testable import FigBridgeCore

struct GenerationCoordinatorTests {
    @Test func runsSequentialGenerationAndPersistsOutputs() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let batchStore = BatchStore(rootDirectory: sandbox.root)
        let runner = MockAgentRunner(outputs: [
            "FILE1|1:2": .success(makeAgentDesignIRJSON(fileKey: "FILE1", nodeId: "1:2", screenName: "first")),
            "FILE2|3:4": .success(makeAgentDesignIRJSON(fileKey: "FILE2", nodeId: "3:4", screenName: "second")),
        ])
        let coordinator = GenerationCoordinator(batchStore: batchStore, agentRunner: runner)

        let items = [
            FigmaLinkItem(rawInputLine: "one", title: "one", url: "https://www.figma.com/design/FILE1/A?node-id=1-2", fileKey: "FILE1", nodeId: "1:2"),
            FigmaLinkItem(rawInputLine: "two", title: "two", url: "https://www.figma.com/design/FILE2/B?node-id=3-4", fileKey: "FILE2", nodeId: "3:4"),
        ]

        let batch = try await coordinator.generate(
            agent: .codex,
            promptTemplate: "prompt",
            sourceInputText: "input",
            outputDirectory: sandbox.root,
            mode: .sequential,
            parallelism: 2,
            callStrategy: .singlePerLink,
            items: items
        )

        #expect(batch.summary.items.allSatisfy { $0.generationStatus == .success })
        #expect(batch.summary.items.allSatisfy { $0.generatedYAMLPath != nil })
    }

    @Test func promptUsesLocalFigmaContextInsteadOfFigmaMCP() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let seedURL = sandbox.root.appendingPathComponent("figma-derived-design-ir.json")
        try #"{"version":"design-ir/v1","screenName":"Seed"}"#.write(to: seedURL, atomically: true, encoding: .utf8)
        let batchStore = BatchStore(rootDirectory: sandbox.root.appendingPathComponent("batches", isDirectory: true))
        let runner = MockAgentRunner(outputs: [
            "FILE1|1:2": .success(makeAgentDesignIRJSON(fileKey: "FILE1", nodeId: "1:2", screenName: "first")),
        ])
        let coordinator = GenerationCoordinator(batchStore: batchStore, agentRunner: runner)
        let item = FigmaLinkItem(
            rawInputLine: "one",
            title: "one",
            url: "https://www.figma.com/design/FILE1/A?node-id=1-2",
            fileKey: "FILE1",
            nodeId: "1:2",
            figmaDerivedDesignIRPath: seedURL.path
        )

        _ = try await coordinator.generate(
            agent: .codex,
            promptTemplate: AppSettings.legacyFigmaMCPDefaultPrompt,
            sourceInputText: "input",
            outputDirectory: sandbox.root,
            mode: .sequential,
            parallelism: 1,
            callStrategy: .singlePerLink,
            items: [item]
        )

        let prompt = try #require(await runner.recordedPrompts().first)
        #expect(prompt.contains("Do not call Figma MCP"))
        #expect(prompt.contains("FigBridge-derived DesignIR seed content"))
        #expect(prompt.contains(#""screenName":"Seed""#))
    }

    @Test func runsParallelGenerationAndKeepsFailures() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let batchStore = BatchStore(rootDirectory: sandbox.root)
        let runner = MockAgentRunner(outputs: [
            "FILE1|1:2": .success(makeAgentDesignIRJSON(fileKey: "FILE1", nodeId: "1:2", screenName: "first")),
            "FILE2|3:4": .failure(MockFailure()),
        ])
        let coordinator = GenerationCoordinator(batchStore: batchStore, agentRunner: runner)

        let items = [
            FigmaLinkItem(rawInputLine: "one", title: "one", url: "https://www.figma.com/design/FILE1/A?node-id=1-2", fileKey: "FILE1", nodeId: "1:2"),
            FigmaLinkItem(rawInputLine: "two", title: "two", url: "https://www.figma.com/design/FILE2/B?node-id=3-4", fileKey: "FILE2", nodeId: "3:4"),
        ]

        let batch = try await coordinator.generate(
            agent: .claude,
            promptTemplate: "prompt",
            sourceInputText: "input",
            outputDirectory: sandbox.root,
            mode: .parallel,
            parallelism: 2,
            callStrategy: .singlePerLink,
            items: items
        )

        #expect(batch.summary.items.filter { $0.generationStatus == .success }.count == 1)
        #expect(batch.summary.items.filter { $0.generationStatus == .failed }.count == 1)
    }

    @Test func reusesExistingBatchAndOnlyRunsPendingItems() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let batchStore = BatchStore(rootDirectory: sandbox.root)
        let runner = MockAgentRunner(outputs: [
            "FILE1|1:2": .success(makeAgentDesignIRJSON(fileKey: "FILE1", nodeId: "1:2", screenName: "first")),
            "FILE2|3:4": .success(makeAgentDesignIRJSON(fileKey: "FILE2", nodeId: "3:4", screenName: "second")),
        ])
        let coordinator = GenerationCoordinator(batchStore: batchStore, agentRunner: runner)

        let firstItem = FigmaLinkItem(rawInputLine: "one", title: "one", url: "https://www.figma.com/design/FILE1/A?node-id=1-2", fileKey: "FILE1", nodeId: "1:2")
        let secondItem = FigmaLinkItem(rawInputLine: "two", title: "two", url: "https://www.figma.com/design/FILE2/B?node-id=3-4", fileKey: "FILE2", nodeId: "3:4")

        let firstBatch = try await coordinator.generate(
            agent: .codex,
            promptTemplate: "prompt",
            sourceInputText: "input",
            outputDirectory: sandbox.root,
            mode: .sequential,
            parallelism: 2,
            callStrategy: .singlePerLink,
            items: [firstItem]
        )

        let secondBatch = try await coordinator.generate(
            agent: .codex,
            promptTemplate: "prompt",
            sourceInputText: "input",
            outputDirectory: sandbox.root,
            mode: .sequential,
            parallelism: 2,
            callStrategy: .singlePerLink,
            existingBatchID: firstBatch.summary.id,
            items: firstBatch.summary.items + [secondItem]
        )

        let calls = await runner.recordedCalls()
        #expect(firstBatch.summary.id == secondBatch.summary.id)
        #expect(secondBatch.summary.items.count == 2)
        #expect(calls == ["FILE1|1:2", "FILE2|3:4"])
    }

    @Test func retriesFailedItemsOnLaterGeneration() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let batchStore = BatchStore(rootDirectory: sandbox.root)
        let runner = RetryingMockAgentRunner()
        let coordinator = GenerationCoordinator(batchStore: batchStore, agentRunner: runner)
        let item = FigmaLinkItem(rawInputLine: "one", title: "one", url: "https://www.figma.com/design/FILE1/A?node-id=1-2", fileKey: "FILE1", nodeId: "1:2")

        let firstBatch = try await coordinator.generate(
            agent: .claude,
            promptTemplate: "prompt",
            sourceInputText: "input",
            outputDirectory: sandbox.root,
            mode: .sequential,
            parallelism: 1,
            callStrategy: .singlePerLink,
            items: [item]
        )

        #expect(firstBatch.summary.items[0].generationStatus == .failed)

        let retriedBatch = try await coordinator.generate(
            agent: .claude,
            promptTemplate: "prompt",
            sourceInputText: "input",
            outputDirectory: sandbox.root,
            mode: .sequential,
            parallelism: 1,
            callStrategy: .singlePerLink,
            existingBatchID: firstBatch.summary.id,
            items: firstBatch.summary.items
        )

        #expect(retriedBatch.summary.items[0].generationStatus == .success)
        #expect(retriedBatch.summary.items[0].generatedYAMLPath != nil)
        #expect(await runner.recordedCalls() == ["FILE1|1:2", "FILE1|1:2"])
    }

    @Test func cancellationPreservesExistingDesignIRArtifact() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let batchStore = BatchStore(rootDirectory: sandbox.root)
        let item = FigmaLinkItem(rawInputLine: "one", title: "one", url: "https://www.figma.com/design/FILE1/A?node-id=1-2", fileKey: "FILE1", nodeId: "1:2")
        let existing = try batchStore.createBatch(GenerationBatch(
            id: "batch-recover-existing-design-ir",
            createdAt: Date(timeIntervalSince1970: 0),
            agent: .codex,
            promptSnapshot: "prompt",
            sourceInputText: "input",
            outputDirectory: sandbox.root.path,
            mode: .sequential,
            parallelism: 1,
            callStrategy: .singleForBatch,
            items: [item]
        ))
        let itemDirectory = try #require(existing.itemDirectories.first)
        let designDirectory = itemDirectory.appendingPathComponent("design-ir", isDirectory: true)
        let designURL = designDirectory.appendingPathComponent(DesignPackageStore.designFilename)
        let rawOutputURL = designDirectory.appendingPathComponent("agent-output.txt")
        try FileManager.default.createDirectory(at: designDirectory, withIntermediateDirectories: true)
        try makeAgentDesignIRJSON(fileKey: item.fileKey, nodeId: item.nodeId, screenName: "Recovered")
            .write(to: designURL, atomically: true, encoding: .utf8)
        try "raw output".write(to: rawOutputURL, atomically: true, encoding: .utf8)

        let coordinator = GenerationCoordinator(batchStore: batchStore, agentRunner: CancellationThrowingRunner())
        let recovered = try await coordinator.generate(
            agent: .codex,
            promptTemplate: "prompt",
            sourceInputText: "input",
            outputDirectory: sandbox.root,
            mode: .sequential,
            parallelism: 1,
            callStrategy: .singleForBatch,
            existingBatchID: existing.summary.id,
            items: existing.summary.items
        )

        let recoveredItem = try #require(recovered.summary.items.first)
        #expect(recoveredItem.generationStatus == .success)
        #expect(recoveredItem.generatedYAMLPath == designURL.path)
        #expect(recoveredItem.agentOutputPath == rawOutputURL.path)
        #expect(recoveredItem.errorMessage == nil)
        #expect(recoveredItem.logSummary == "已恢复 DesignIR")
    }

    @Test func runsSingleBatchCallAndSplitsOutputsPerItem() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let batchStore = BatchStore(rootDirectory: sandbox.root)
        let runner = MockBatchAgentRunner(output: """
        <<<FIGBRIDGE_DESIGN_IR_START fileKey=FILE1 nodeId=1:2>>>
        \(makeAgentDesignIRJSON(fileKey: "FILE1", nodeId: "1:2", screenName: "first"))
        <<<FIGBRIDGE_DESIGN_IR_END>>>
        <<<FIGBRIDGE_DESIGN_IR_START fileKey=FILE2 nodeId=3:4>>>
        \(makeAgentDesignIRJSON(fileKey: "FILE2", nodeId: "3:4", screenName: "second"))
        <<<FIGBRIDGE_DESIGN_IR_END>>>
        """)
        let coordinator = GenerationCoordinator(batchStore: batchStore, agentRunner: runner)
        let items = [
            FigmaLinkItem(rawInputLine: "one", title: "one", url: "https://www.figma.com/design/FILE1/A?node-id=1-2", fileKey: "FILE1", nodeId: "1:2"),
            FigmaLinkItem(rawInputLine: "two", title: "two", url: "https://www.figma.com/design/FILE2/B?node-id=3-4", fileKey: "FILE2", nodeId: "3:4"),
        ]

        let batch = try await coordinator.generate(
            agent: .codex,
            promptTemplate: "prompt",
            sourceInputText: "input",
            outputDirectory: sandbox.root,
            mode: .sequential,
            parallelism: 2,
            callStrategy: .singleForBatch,
            items: items
        )

        #expect(batch.summary.callStrategy == .singleForBatch)
        #expect(batch.summary.items.allSatisfy { $0.generationStatus == .success })
        #expect(batch.summary.items.allSatisfy { $0.generatedYAMLPath != nil })
        #expect(await runner.recordedCalls() == ["FILE1|1:2"])
    }

    @Test func keepsMissingSegmentItemsAsFailedInSingleBatchCall() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let batchStore = BatchStore(rootDirectory: sandbox.root)
        let runner = MockBatchAgentRunner(output: """
        <<<FIGBRIDGE_DESIGN_IR_START fileKey=FILE1 nodeId=1:2>>>
        \(makeAgentDesignIRJSON(fileKey: "FILE1", nodeId: "1:2", screenName: "first"))
        <<<FIGBRIDGE_DESIGN_IR_END>>>
        """)
        let coordinator = GenerationCoordinator(batchStore: batchStore, agentRunner: runner)
        let items = [
            FigmaLinkItem(rawInputLine: "one", title: "one", url: "https://www.figma.com/design/FILE1/A?node-id=1-2", fileKey: "FILE1", nodeId: "1:2"),
            FigmaLinkItem(rawInputLine: "two", title: "two", url: "https://www.figma.com/design/FILE2/B?node-id=3-4", fileKey: "FILE2", nodeId: "3:4"),
        ]

        let batch = try await coordinator.generate(
            agent: .codex,
            promptTemplate: "prompt",
            sourceInputText: "input",
            outputDirectory: sandbox.root,
            mode: .sequential,
            parallelism: 2,
            callStrategy: .singleForBatch,
            items: items
        )

        let successCount = batch.summary.items.filter { $0.generationStatus == .success }.count
        let failedCount = batch.summary.items.filter { $0.generationStatus == .failed }.count
        #expect(successCount == 1)
        #expect(failedCount == 1)
        #expect(batch.summary.items.first(where: { $0.fileKey == "FILE2" })?.errorMessage?.contains("缺少") == true)
    }

    @Test func rejectsInvalidSingleItemAgentOutputsAndKeepsRawOutput() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let batchStore = BatchStore(rootDirectory: sandbox.root)
        let runner = MockAgentRunner(outputs: [
            "FILE1|1:2": .success(#"{"version":"design-ir/v1"}"#),
            "FILE2|3:4": .success("""
            ```json
            \(makeAgentDesignIRJSON(fileKey: "FILE2", nodeId: "3:4"))
            ```
            """),
            "FILE3|5:6": .success("not design ir"),
        ])
        let coordinator = GenerationCoordinator(batchStore: batchStore, agentRunner: runner)
        let items = [
            FigmaLinkItem(rawInputLine: "one", title: "one", url: "https://www.figma.com/design/FILE1/A?node-id=1-2", fileKey: "FILE1", nodeId: "1:2"),
            FigmaLinkItem(rawInputLine: "two", title: "two", url: "https://www.figma.com/design/FILE2/B?node-id=3-4", fileKey: "FILE2", nodeId: "3:4"),
            FigmaLinkItem(rawInputLine: "three", title: "three", url: "https://www.figma.com/design/FILE3/C?node-id=5-6", fileKey: "FILE3", nodeId: "5:6"),
        ]

        let batch = try await coordinator.generate(
            agent: .codex,
            promptTemplate: "prompt",
            sourceInputText: "input",
            outputDirectory: sandbox.root,
            mode: .sequential,
            parallelism: 1,
            callStrategy: .singlePerLink,
            items: items
        )

        #expect(batch.summary.items[0].generationStatus == .failed)
        #expect(batch.summary.items[0].generatedYAMLPath == nil)
        #expect(batch.summary.items[1].generationStatus == .success)
        #expect(batch.summary.items[1].generatedYAMLPath != nil)
        #expect(batch.summary.items[2].generationStatus == .failed)
        #expect(batch.summary.items[2].generatedYAMLPath == nil)
        #expect(batch.summary.items.allSatisfy { $0.agentOutputPath != nil })
        #expect(batch.summary.items[0].errorMessage?.contains("缺少字段") == true)
        #expect(batch.summary.items[2].errorMessage?.contains("不是有效") == true)
    }

    @Test func recordsPerItemSuccessAndFailureReasonsForSingleBatchCall() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let batchStore = BatchStore(rootDirectory: sandbox.root)
        let runner = MockBatchAgentRunner(output: """
        <<<FIGBRIDGE_DESIGN_IR_START fileKey=FILE1 nodeId=1:2>>>
        \(makeAgentDesignIRJSON(fileKey: "FILE1", nodeId: "1:2", screenName: "valid"))
        <<<FIGBRIDGE_DESIGN_IR_END>>>
        <<<FIGBRIDGE_DESIGN_IR_START fileKey=FILE2 nodeId=3:4>>>
        ```json
        \(makeAgentDesignIRJSON(fileKey: "FILE2", nodeId: "3:4", screenName: "markdown"))
        ```
        <<<FIGBRIDGE_DESIGN_IR_END>>>
        <<<FIGBRIDGE_DESIGN_IR_START fileKey=FILE3 nodeId=5:6>>>
        {"version":"design-ir/v1"}
        <<<FIGBRIDGE_DESIGN_IR_END>>>
        """)
        let coordinator = GenerationCoordinator(batchStore: batchStore, agentRunner: runner)
        let items = [
            FigmaLinkItem(rawInputLine: "one", title: "one", url: "https://www.figma.com/design/FILE1/A?node-id=1-2", fileKey: "FILE1", nodeId: "1:2"),
            FigmaLinkItem(rawInputLine: "two", title: "two", url: "https://www.figma.com/design/FILE2/B?node-id=3-4", fileKey: "FILE2", nodeId: "3:4"),
            FigmaLinkItem(rawInputLine: "three", title: "three", url: "https://www.figma.com/design/FILE3/C?node-id=5-6", fileKey: "FILE3", nodeId: "5:6"),
        ]

        let batch = try await coordinator.generate(
            agent: .codex,
            promptTemplate: "prompt",
            sourceInputText: "input",
            outputDirectory: sandbox.root,
            mode: .sequential,
            parallelism: 1,
            callStrategy: .singleForBatch,
            items: items
        )

        #expect(batch.summary.items[0].generationStatus == .success)
        #expect(batch.summary.items[0].generatedYAMLPath != nil)
        #expect(batch.summary.items[1].generationStatus == .success)
        #expect(batch.summary.items[1].generatedYAMLPath != nil)
        #expect(batch.summary.items[2].generationStatus == .failed)
        #expect(batch.summary.items[2].errorMessage?.contains("缺少字段") == true)
        #expect(batch.summary.items.allSatisfy { $0.agentOutputPath != nil })
    }

    @Test func emitsStreamingEventsForSingleItemRuns() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let batchStore = BatchStore(rootDirectory: sandbox.root)
        let runner = EventMockAgentRunner(mode: .single)
        let coordinator = GenerationCoordinator(batchStore: batchStore, agentRunner: runner)
        let item = FigmaLinkItem(rawInputLine: "one", title: "one", url: "https://www.figma.com/design/FILE1/A?node-id=1-2", fileKey: "FILE1", nodeId: "1:2")
        let recorder = AgentEventRecorder()

        _ = try await coordinator.generate(
            agent: .codex,
            promptTemplate: "prompt",
            sourceInputText: "input",
            outputDirectory: sandbox.root,
            mode: .sequential,
            parallelism: 1,
            callStrategy: .singlePerLink,
            items: [item],
            itemEvent: { _, event in
                await recorder.append(event, for: item.id)
            }
        )
        let events = try #require(await recorder.events(for: item.id))

        #expect(events.contains { if case .started(_, _, false) = $0 { return true } else { return false } })
        #expect(events.contains { if case .stdout(let text) = $0 { return text.contains("progress-1") } else { return false } })
        #expect(events.contains { if case .stderr(let text) = $0 { return text.contains("warn-1") } else { return false } })
        #expect(events.contains { if case .finished(0) = $0 { return true } else { return false } })
    }

    @Test func sharesStreamingEventsAcrossItemsForSingleBatchCall() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let batchStore = BatchStore(rootDirectory: sandbox.root)
        let runner = EventMockAgentRunner(mode: .batch)
        let coordinator = GenerationCoordinator(batchStore: batchStore, agentRunner: runner)
        let first = FigmaLinkItem(rawInputLine: "one", title: "one", url: "https://www.figma.com/design/FILE1/A?node-id=1-2", fileKey: "FILE1", nodeId: "1:2")
        let second = FigmaLinkItem(rawInputLine: "two", title: "two", url: "https://www.figma.com/design/FILE2/B?node-id=3-4", fileKey: "FILE2", nodeId: "3:4")
        let recorder = AgentEventRecorder()

        _ = try await coordinator.generate(
            agent: .codex,
            promptTemplate: "prompt",
            sourceInputText: "input",
            outputDirectory: sandbox.root,
            mode: .sequential,
            parallelism: 1,
            callStrategy: .singleForBatch,
            items: [first, second],
            itemEvent: { itemID, event in
                await recorder.append(event, for: itemID)
            }
        )

        let firstEvents = try #require(await recorder.events(for: first.id))
        let secondEvents = try #require(await recorder.events(for: second.id))
        #expect(firstEvents == secondEvents)
        #expect(firstEvents.contains { if case .started(_, _, true) = $0 { return true } else { return false } })
        #expect(firstEvents.contains { if case .stdout(let text) = $0 { return text.contains("shared-progress") } else { return false } })
    }
}

private actor MockAgentRunner: AgentRunning {
    let outputs: [String: Result<String, Error>]
    private var calls: [String] = []
    private var prompts: [String] = []

    init(outputs: [String: Result<String, Error>]) {
        self.outputs = outputs
    }

    func run(provider: AgentProvider, prompt: String, item: FigmaLinkItem, eventHandler: (@Sendable (AgentRunEvent) async -> Void)? = nil) async throws -> AgentRunResult {
        let key = "\(item.fileKey)|\(item.nodeId)"
        calls.append(key)
        prompts.append(prompt)
        guard let result = outputs[key] else {
            throw MockFailure()
        }
        return AgentRunResult(output: try result.get(), executablePath: "/mock/\(provider.rawValue)", arguments: [], exitCode: 0, stderr: "")
    }

    func recordedCalls() -> [String] {
        calls
    }

    func recordedPrompts() -> [String] {
        prompts
    }
}

private struct MockFailure: LocalizedError {
    var errorDescription: String? { "mock failure" }
}

private actor RetryingMockAgentRunner: AgentRunning {
    private var attempts: [String: Int] = [:]
    private var calls: [String] = []

    func run(provider: AgentProvider, prompt: String, item: FigmaLinkItem, eventHandler: (@Sendable (AgentRunEvent) async -> Void)? = nil) async throws -> AgentRunResult {
        let key = "\(item.fileKey)|\(item.nodeId)"
        calls.append(key)
        let nextAttempt = (attempts[key] ?? 0) + 1
        attempts[key] = nextAttempt
        if nextAttempt == 1 {
            throw MockFailure()
        }
        return AgentRunResult(output: makeAgentDesignIRJSON(fileKey: item.fileKey, nodeId: item.nodeId, screenName: "retried"), executablePath: "/mock/\(provider.rawValue)", arguments: [], exitCode: 0, stderr: "")
    }

    func recordedCalls() -> [String] {
        calls
    }
}

private actor CancellationThrowingRunner: AgentRunning {
    func run(provider: AgentProvider, prompt: String, item: FigmaLinkItem, eventHandler: (@Sendable (AgentRunEvent) async -> Void)? = nil) async throws -> AgentRunResult {
        throw CancellationError()
    }
}

private actor MockBatchAgentRunner: AgentRunning {
    private let output: String
    private var calls: [String] = []

    init(output: String) {
        self.output = output
    }

    func run(provider: AgentProvider, prompt: String, item: FigmaLinkItem, eventHandler: (@Sendable (AgentRunEvent) async -> Void)? = nil) async throws -> AgentRunResult {
        calls.append("\(item.fileKey)|\(item.nodeId)")
        return AgentRunResult(output: output, executablePath: "/mock/\(provider.rawValue)", arguments: [], exitCode: 0, stderr: "")
    }

    func recordedCalls() -> [String] {
        calls
    }
}

private actor AgentEventRecorder {
    private var values: [UUID: [AgentRunEvent]] = [:]

    func append(_ event: AgentRunEvent, for itemID: UUID) {
        values[itemID, default: []].append(event)
    }

    func events(for itemID: UUID) -> [AgentRunEvent]? {
        values[itemID]
    }
}

private actor EventMockAgentRunner: AgentRunning {
    enum Mode {
        case single
        case batch
    }

    let mode: Mode

    init(mode: Mode) {
        self.mode = mode
    }

    func run(
        provider: AgentProvider,
        prompt: String,
        item: FigmaLinkItem,
        eventHandler: (@Sendable (AgentRunEvent) async -> Void)?
    ) async throws -> AgentRunResult {
        switch mode {
        case .single:
            if let eventHandler {
                await eventHandler(.started(executablePath: "/mock/\(provider.rawValue)", arguments: [], isSharedLog: false))
                await eventHandler(.stdout("progress-1\n"))
                await eventHandler(.stderr("warn-1\n"))
                await eventHandler(.finished(exitCode: 0))
            }
            return AgentRunResult(output: makeAgentDesignIRJSON(fileKey: item.fileKey, nodeId: item.nodeId, screenName: "first"), executablePath: "/mock/\(provider.rawValue)", arguments: [], exitCode: 0, stderr: "warn-1")
        case .batch:
            if let eventHandler {
                await eventHandler(.started(executablePath: "/mock/\(provider.rawValue)", arguments: [], isSharedLog: true))
                await eventHandler(.stdout("shared-progress\n"))
                await eventHandler(.finished(exitCode: 0))
            }
            return AgentRunResult(
                output: """
                <<<FIGBRIDGE_DESIGN_IR_START fileKey=FILE1 nodeId=1:2>>>
                \(makeAgentDesignIRJSON(fileKey: "FILE1", nodeId: "1:2", screenName: "first"))
                <<<FIGBRIDGE_DESIGN_IR_END>>>
                <<<FIGBRIDGE_DESIGN_IR_START fileKey=FILE2 nodeId=3:4>>>
                \(makeAgentDesignIRJSON(fileKey: "FILE2", nodeId: "3:4", screenName: "second"))
                <<<FIGBRIDGE_DESIGN_IR_END>>>
                """,
                executablePath: "/mock/\(provider.rawValue)",
                arguments: [],
                exitCode: 0,
                stderr: ""
            )
        }
    }
}
