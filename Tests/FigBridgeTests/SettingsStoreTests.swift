import Foundation
import Testing
@testable import FigBridgeCore

struct SettingsStoreTests {
    @Test func defaultPromptIncludesFigmaMCPStopRules() {
        let prompt = AppSettings.defaultPrompt.lowercased()

        #expect(prompt.contains("designir"))
        #expect(prompt.contains("json or yaml"))
        #expect(prompt.contains("figma mcp"))
        #expect(prompt.contains("stop immediately"))
        #expect(prompt.contains("do not use fallback"))
        #expect(prompt.contains("do not include markdown"))
    }

    @Test func persistsAndLoadsSettings() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }
        let store = SettingsStore(fileURL: sandbox.root.appendingPathComponent("settings.json"))
        var settings = AppSettings.defaultValue
        settings.selectedAgentID = AgentProvider.codex.id
        settings.promptTemplate = "custom prompt"
        settings.parallelism = 4

        try store.save(settings)
        let loaded = try store.load()

        #expect(loaded.selectedAgentID == AgentProvider.codex.id)
        #expect(loaded.promptTemplate == "custom prompt")
        #expect(loaded.parallelism == 4)
    }

    @Test func fallsBackToDefaultForMissingFile() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }
        let store = SettingsStore(fileURL: sandbox.root.appendingPathComponent("missing.json"))

        let loaded = try store.load()

        #expect(loaded == AppSettings.defaultValue)
        #expect(loaded.defaultExportFormat == .png)
        #expect(loaded.defaultAgentCallStrategy == .singleForBatch)
    }

    @Test func clearsUnavailableSelectedAgent() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }
        let store = SettingsStore(fileURL: sandbox.root.appendingPathComponent("settings.json"))
        var settings = AppSettings.defaultValue
        settings.selectedAgentID = AgentProvider.claude.id
        try store.save(settings)

        let sanitized = try store.loadValidatingSelectedAgent(availableAgents: [.codex])

        #expect(sanitized.selectedAgentID == nil)
    }
}
