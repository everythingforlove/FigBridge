import Foundation
import Testing
@testable import FigBridgeCore
@testable import FigBridgeApp

@MainActor
struct SettingsViewModelTests {
    @Test func restoringDefaultPromptAutoSavesSettings() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }
        let harness = try SettingsViewModelHarness(rootDirectory: sandbox.root)

        harness.viewModel.settings.promptTemplate = "custom prompt"
        harness.viewModel.restoreDefaultPrompt()
        let saved = await waitUntil {
            (try? harness.settingsStore.load().promptTemplate) == AppSettings.defaultPrompt
        }

        #expect(saved)
        #expect(try harness.settingsStore.load().promptTemplate == AppSettings.defaultPrompt)
    }

    @Test func autoSavePersistsLatestSettingsAfterDebounce() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }
        let harness = try SettingsViewModelHarness(rootDirectory: sandbox.root)

        harness.viewModel.settings.figmaToken = "token-1"
        harness.viewModel.settings.figmaToken = "token-2"
        harness.viewModel.settings.defaultGenerationMode = .parallel
        harness.viewModel.settings.parallelism = 6

        let saved = await waitUntil {
            let settings = try? harness.settingsStore.load()
            return settings?.figmaToken == "token-2"
                && settings?.defaultGenerationMode == .parallel
                && settings?.parallelism == 6
        }

        #expect(saved)
    }

    @Test func refreshAgentsReloadsAvailableAgentsAndSanitizesSelection() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let claudePath = sandbox.root.appendingPathComponent("claude")
        try makeExecutable(at: claudePath, body: "#!/bin/sh\nif [ \"$1\" = \"--version\" ]; then\n  echo \"claude 1.0.0\"\nfi\n")

        let shell = ShellClient(pathLookupDirectories: [sandbox.root], environment: ["PATH": "/usr/bin:/bin"])
        let settingsStore = SettingsStore(fileURL: sandbox.root.appendingPathComponent("settings.json"))
        try settingsStore.save(AppSettings(
            selectedAgentID: "missing-agent",
            promptTemplate: "prompt",
            outputDirectoryPath: nil,
            figmaToken: "",
            defaultExportFormat: .png,
            defaultGenerationMode: .sequential,
            parallelism: 2,
            defaultAgentCallStrategy: .singlePerLink
        ))
        let viewModel = SettingsViewModel(
            settingsStore: settingsStore,
            agentService: AgentService(shellClient: shell),
            figmaService: FigmaService(baseDirectory: sandbox.root, transport: MockFigmaTransport(responses: []))
        )

        await viewModel.refreshAgents()

        #expect(viewModel.availableAgents.map(\.provider).contains(.claude))
        #expect(viewModel.settings.selectedAgentID == nil)
        #expect(viewModel.message.isEmpty)
    }

    @Test func configuredHTTPProviderIsAvailableWithoutCLIDetection() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }
        let provider = AgentProvider(
            id: "internal-http",
            kind: .openAICompatibleHTTP,
            displayNameOverride: "Internal HTTP",
            openAICompatibleHTTP: OpenAICompatibleHTTPProviderConfig(
                baseURL: "https://internal.example/v1",
                apiKey: "key",
                model: "internal-model",
                timeout: 120,
                streaming: false
            )
        )
        let settingsStore = SettingsStore(fileURL: sandbox.root.appendingPathComponent("settings.json"))
        try settingsStore.save(AppSettings(
            selectedAgentID: provider.id,
            providerConfigurations: [.claude, .codex, provider],
            promptTemplate: "prompt",
            outputDirectoryPath: nil,
            figmaToken: "",
            defaultExportFormat: .png,
            defaultGenerationMode: .sequential,
            parallelism: 2,
            defaultAgentCallStrategy: .singlePerLink
        ))
        let viewModel = SettingsViewModel(
            settingsStore: settingsStore,
            agentService: AgentService(shellClient: ShellClient(pathLookupDirectories: [], environment: ["PATH": "/usr/bin:/bin"])),
            figmaService: FigmaService(baseDirectory: sandbox.root, transport: MockFigmaTransport(responses: []))
        )

        await viewModel.bootstrap()

        #expect(viewModel.availableAgents.map(\.provider).contains(provider))
        #expect(viewModel.settings.selectedAgentID == provider.id)
        #expect(viewModel.provider(for: provider.id) == provider)
    }

    @Test func testTokenReportsSuccessMessage() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let transport = MockFigmaTransport(responses: [
            MockHTTPResponse(
                path: "/v1/me",
                query: [:],
                statusCode: 200,
                body: #"{"id":"me"}"#
            )
        ])
        let harness = try SettingsViewModelHarness(rootDirectory: sandbox.root, figmaTransport: transport)
        harness.viewModel.settings.figmaToken = "token"

        let task = Task {
            await harness.viewModel.testToken()
        }
        let loadingStarted = await waitUntil {
            harness.viewModel.isTestingToken
        }
        await task.value

        #expect(loadingStarted)
        #expect(harness.viewModel.isTestingToken == false)
        #expect(harness.viewModel.toastMessage == "Token 可用")
        #expect(harness.viewModel.isToastError == false)
    }
}

@MainActor
private struct SettingsViewModelHarness {
    let viewModel: SettingsViewModel
    let settingsStore: SettingsStore

    init(rootDirectory: URL, figmaTransport: (any FigmaHTTPTransport)? = nil) throws {
        let settingsStore = SettingsStore(fileURL: rootDirectory.appendingPathComponent("settings.json"))
        try settingsStore.save(AppSettings(
            selectedAgentID: AgentProvider.codex.id,
            promptTemplate: "prompt",
            outputDirectoryPath: nil,
            figmaToken: "",
            defaultExportFormat: .png,
            defaultGenerationMode: .sequential,
            parallelism: 2,
            defaultAgentCallStrategy: .singlePerLink
        ))
        let shell = ShellClient(environment: ["PATH": "/usr/bin:/bin"])
        let agentService = AgentService(shellClient: shell)
        let figmaService = FigmaService(
            baseDirectory: rootDirectory,
            transport: figmaTransport ?? MockFigmaTransport(responses: [])
        )
        let viewModel = SettingsViewModel(
            settingsStore: settingsStore,
            agentService: agentService,
            figmaService: figmaService
        )
        viewModel.settings = try settingsStore.load()
        viewModel.markPersistedSettingsLoadedForTesting()

        self.viewModel = viewModel
        self.settingsStore = settingsStore
    }
}
