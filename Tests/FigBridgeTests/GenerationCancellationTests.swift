import Foundation
import Testing
@testable import FigBridgeCore

struct GenerationCancellationTests {
    @Test func marksPendingItemsCancelledWhenTaskIsCancelled() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let batchStore = BatchStore(rootDirectory: sandbox.root)
        let runner = SlowMockAgentRunner()
        let coordinator = GenerationCoordinator(batchStore: batchStore, agentRunner: runner)
        let items = [
            FigmaLinkItem(rawInputLine: "one", title: "one", url: "https://www.figma.com/design/FILE1/A?node-id=1-2", fileKey: "FILE1", nodeId: "1:2"),
            FigmaLinkItem(rawInputLine: "two", title: "two", url: "https://www.figma.com/design/FILE2/B?node-id=3-4", fileKey: "FILE2", nodeId: "3:4"),
        ]

        let progressRecorder = CancellationProgressRecorder()
        let task = Task {
            try await coordinator.generate(
                agent: .codex,
                promptTemplate: "prompt",
                sourceInputText: "input",
                outputDirectory: sandbox.root,
                mode: .sequential,
                parallelism: 1,
                callStrategy: .singlePerLink,
                items: items,
                progress: { _, _, item in
                    await progressRecorder.record(item)
                }
            )
        }

        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("expected cancellation")
        } catch {
            #expect(error is CancellationError)
        }
        let statuses = await progressRecorder.statuses()
        #expect(statuses.contains(.cancelled))
    }
}

private actor SlowMockAgentRunner: AgentRunning {
    func run(provider: AgentProvider, prompt: String, item: FigmaLinkItem, eventHandler: (@Sendable (AgentRunEvent) async -> Void)? = nil) async throws -> AgentRunResult {
        try await Task.sleep(nanoseconds: 2_000_000_000)
        return AgentRunResult(
            output: makeAgentDesignIRJSON(fileKey: item.fileKey, nodeId: item.nodeId, screenName: "slow"),
            executablePath: "/mock/\(provider.rawValue)",
            arguments: [],
            exitCode: 0,
            stderr: ""
        )
    }
}

private actor CancellationProgressRecorder {
    private var items: [FigmaLinkItem] = []

    func record(_ item: FigmaLinkItem) {
        items.append(item)
    }

    func statuses() -> [GenerationStatus] {
        items.map(\.generationStatus)
    }
}
