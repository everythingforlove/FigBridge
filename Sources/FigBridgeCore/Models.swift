import Foundation

public enum AgentProviderKind: String, Codable, CaseIterable, Sendable {
    case claudeCLI
    case codexCLI
    case openAICompatibleHTTP

    public var displayName: String {
        switch self {
        case .claudeCLI:
            "Claude CLI"
        case .codexCLI:
            "Codex CLI"
        case .openAICompatibleHTTP:
            "OpenAI-compatible HTTP"
        }
    }
}

public struct CLIProviderConfig: Codable, Equatable, Sendable {
    public var executableName: String

    public init(executableName: String) {
        self.executableName = executableName
    }
}

public struct OpenAICompatibleHTTPProviderConfig: Codable, Equatable, Sendable {
    public var baseURL: String
    public var apiKey: String
    public var model: String
    public var timeout: TimeInterval
    public var streaming: Bool

    public init(
        baseURL: String = "",
        apiKey: String = "",
        model: String = "",
        timeout: TimeInterval = 300,
        streaming: Bool = false
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.timeout = timeout
        self.streaming = streaming
    }

    public var isConfigured: Bool {
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public struct AgentProvider: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var kind: AgentProviderKind
    public var displayNameOverride: String?
    public var cli: CLIProviderConfig?
    public var openAICompatibleHTTP: OpenAICompatibleHTTPProviderConfig?

    public init(
        id: String,
        kind: AgentProviderKind,
        displayNameOverride: String? = nil,
        cli: CLIProviderConfig? = nil,
        openAICompatibleHTTP: OpenAICompatibleHTTPProviderConfig? = nil
    ) {
        self.id = id
        self.kind = kind
        self.displayNameOverride = displayNameOverride
        self.cli = cli
        self.openAICompatibleHTTP = openAICompatibleHTTP
    }

    public static let claude = AgentProvider(
        id: "claude",
        kind: .claudeCLI,
        displayNameOverride: "Claude",
        cli: CLIProviderConfig(executableName: "claude")
    )

    public static let codex = AgentProvider(
        id: "codex",
        kind: .codexCLI,
        displayNameOverride: "Codex",
        cli: CLIProviderConfig(executableName: "codex")
    )

    public static let defaultOpenAICompatibleHTTP = AgentProvider(
        id: "openai-compatible-http",
        kind: .openAICompatibleHTTP,
        displayNameOverride: "OpenAI-compatible HTTP",
        openAICompatibleHTTP: OpenAICompatibleHTTPProviderConfig()
    )

    public static let allCases: [AgentProvider] = [.claude, .codex]

    public var rawValue: String {
        switch kind {
        case .claudeCLI, .codexCLI:
            cli?.executableName ?? id
        case .openAICompatibleHTTP:
            id
        }
    }

    public var displayName: String {
        displayNameOverride ?? kind.displayName
    }

    public var modelName: String? {
        openAICompatibleHTTP?.model.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    public var requestTargetDescription: String {
        switch kind {
        case .claudeCLI, .codexCLI:
            rawValue
        case .openAICompatibleHTTP:
            openAICompatibleHTTP?.baseURL.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
    }

    public init(from decoder: any Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let legacyValue = try? container.decode(String.self) {
            switch legacyValue {
            case "claude", "claudeCLI":
                self = .claude
            case "codex", "codexCLI":
                self = .codex
            case "openAICompatibleHTTP", "openai-compatible-http":
                self = .defaultOpenAICompatibleHTTP
            default:
                self = AgentProvider(id: legacyValue, kind: .openAICompatibleHTTP, displayNameOverride: legacyValue, openAICompatibleHTTP: OpenAICompatibleHTTPProviderConfig())
            }
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = try container.decode(AgentProviderKind.self, forKey: .kind)
        displayNameOverride = try container.decodeIfPresent(String.self, forKey: .displayNameOverride)
        cli = try container.decodeIfPresent(CLIProviderConfig.self, forKey: .cli)
        openAICompatibleHTTP = try container.decodeIfPresent(OpenAICompatibleHTTPProviderConfig.self, forKey: .openAICompatibleHTTP)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case displayNameOverride
        case cli
        case openAICompatibleHTTP
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

public enum GenerationMode: String, Codable, CaseIterable, Sendable {
    case sequential
    case parallel

    public var displayName: String {
        switch self {
        case .sequential:
            "逐个"
        case .parallel:
            "并发"
        }
    }
}

public enum AgentCallStrategy: String, Codable, CaseIterable, Sendable {
    case singlePerLink
    case singleForBatch

    public var displayName: String {
        switch self {
        case .singlePerLink:
            "单链接调用"
        case .singleForBatch:
            "多链接单次调用"
        }
    }
}

public enum ExportFormat: String, Codable, CaseIterable, Sendable {
    case png
    case svg
}

public enum PreviewStatus: String, Codable, Sendable {
    case idle
    case loading
    case success
    case failed
}

public enum GenerationStatus: String, Codable, Sendable {
    case idle
    case queued
    case running
    case success
    case failed
    case cancelled
}

public enum AgentRunLogStatus: String, Codable, Sendable {
    case running
    case finished
    case failed
    case cancelled
}

public enum AgentRunEvent: Equatable, Sendable {
    case metadata(providerKind: AgentProviderKind, model: String?, requestSummary: String)
    case started(executablePath: String, arguments: [String], isSharedLog: Bool)
    case stdout(String)
    case stderr(String)
    case finished(exitCode: Int32)
    case failed(message: String)
    case cancelled
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var selectedAgentID: String?
    public var providerConfigurations: [AgentProvider]
    public var promptTemplate: String
    public var outputDirectoryPath: String?
    public var figmaToken: String
    public var defaultExportFormat: ExportFormat
    public var defaultGenerationMode: GenerationMode
    public var parallelism: Int
    public var defaultAgentCallStrategy: AgentCallStrategy

    enum CodingKeys: String, CodingKey {
        case selectedAgentID
        case providerConfigurations
        case promptTemplate
        case outputDirectoryPath
        case figmaToken
        case defaultExportFormat
        case defaultGenerationMode
        case parallelism
        case defaultAgentCallStrategy
    }

    public init(
        selectedAgentID: String? = nil,
        providerConfigurations: [AgentProvider] = AgentProvider.allCases + [.defaultOpenAICompatibleHTTP],
        promptTemplate: String,
        outputDirectoryPath: String? = nil,
        figmaToken: String,
        defaultExportFormat: ExportFormat,
        defaultGenerationMode: GenerationMode,
        parallelism: Int,
        defaultAgentCallStrategy: AgentCallStrategy = .singleForBatch
    ) {
        self.selectedAgentID = selectedAgentID
        self.providerConfigurations = providerConfigurations
        self.promptTemplate = promptTemplate
        self.outputDirectoryPath = outputDirectoryPath
        self.figmaToken = figmaToken
        self.defaultExportFormat = defaultExportFormat
        self.defaultGenerationMode = defaultGenerationMode
        self.parallelism = parallelism
        self.defaultAgentCallStrategy = defaultAgentCallStrategy
    }

    public static let defaultPrompt = """
    Generate a strict DesignIR JSON or YAML object for this Figma node.
    Include layout, typography, colors, spacing, assets, and visible interaction notes in the DesignIR fields.
    You must call figma mcp to retrieve Figma data.
    If calling figma mcp fails, stop immediately and report the failure.
    Do not use fallback or alternative methods.
    Return DesignIR only. Do not include Markdown, code fences, prose, or extra keys outside the DesignIR schema.
    """

    public static let defaultValue = AppSettings(
        promptTemplate: AppSettings.defaultPrompt,
        figmaToken: "",
        defaultExportFormat: .png,
        defaultGenerationMode: .sequential,
        parallelism: 2,
        defaultAgentCallStrategy: .singleForBatch
    )

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selectedAgentID = try container.decodeIfPresent(String.self, forKey: .selectedAgentID)
        providerConfigurations = try container.decodeIfPresent([AgentProvider].self, forKey: .providerConfigurations) ?? AgentProvider.allCases + [.defaultOpenAICompatibleHTTP]
        promptTemplate = try container.decode(String.self, forKey: .promptTemplate)
        outputDirectoryPath = try container.decodeIfPresent(String.self, forKey: .outputDirectoryPath)
        figmaToken = try container.decode(String.self, forKey: .figmaToken)
        defaultExportFormat = try container.decode(ExportFormat.self, forKey: .defaultExportFormat)
        defaultGenerationMode = try container.decode(GenerationMode.self, forKey: .defaultGenerationMode)
        parallelism = try container.decodeIfPresent(Int.self, forKey: .parallelism) ?? AppSettings.defaultValue.parallelism
        defaultAgentCallStrategy = try container.decodeIfPresent(AgentCallStrategy.self, forKey: .defaultAgentCallStrategy) ?? .singleForBatch
    }
}

public struct AgentDescriptor: Codable, Equatable, Identifiable, Sendable {
    public let provider: AgentProvider
    public let path: String
    public let version: String

    public init(provider: AgentProvider, path: String, version: String) {
        self.provider = provider
        self.path = path
        self.version = version
    }

    public var id: String {
        provider.id
    }
}

public struct FigmaResourceItem: Codable, Equatable, Identifiable, Sendable {
    public enum ResourceKind: String, Codable, Sendable {
        case image
        case icon
        case export
    }

    public let id: UUID
    public var name: String
    public var kind: ResourceKind
    public var format: ExportFormat
    public var remoteURL: String?
    public var localPath: String?

    public init(
        id: UUID = UUID(),
        name: String,
        kind: ResourceKind,
        format: ExportFormat,
        remoteURL: String? = nil,
        localPath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.format = format
        self.remoteURL = remoteURL
        self.localPath = localPath
    }
}

public struct FigmaLinkItem: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var rawInputLine: String
    public var title: String?
    public var url: String
    public var fileKey: String
    public var nodeId: String
    public var previewStatus: PreviewStatus
    public var resourceStatus: PreviewStatus
    public var previewImagePath: String?
    public var resourceItems: [FigmaResourceItem]
    public var generationStatus: GenerationStatus
    public var generatedYAMLPath: String?
    public var errorMessage: String?
    public var nodeName: String?
    public var agentOutputPath: String?
    public var logSummary: String?

    public init(
        id: UUID = UUID(),
        rawInputLine: String,
        title: String?,
        url: String,
        fileKey: String,
        nodeId: String,
        previewStatus: PreviewStatus = .idle,
        resourceStatus: PreviewStatus = .idle,
        previewImagePath: String? = nil,
        resourceItems: [FigmaResourceItem] = [],
        generationStatus: GenerationStatus = .idle,
        generatedYAMLPath: String? = nil,
        errorMessage: String? = nil,
        nodeName: String? = nil,
        agentOutputPath: String? = nil,
        logSummary: String? = nil
    ) {
        self.id = id
        self.rawInputLine = rawInputLine
        self.title = title
        self.url = url
        self.fileKey = fileKey
        self.nodeId = nodeId
        self.previewStatus = previewStatus
        self.resourceStatus = resourceStatus
        self.previewImagePath = previewImagePath
        self.resourceItems = resourceItems
        self.generationStatus = generationStatus
        self.generatedYAMLPath = generatedYAMLPath
        self.errorMessage = errorMessage
        self.nodeName = nodeName
        self.agentOutputPath = agentOutputPath
        self.logSummary = logSummary
    }
}

public struct GenerationRunLog: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public var runID: String { id }
    public var isShared: Bool
    public var provider: AgentProvider
    public var providerKind: AgentProviderKind
    public var model: String?
    public var requestSummary: String?
    public var errorMessage: String?
    public var executablePath: String?
    public var arguments: [String]
    public var startedAt: Date?
    public var endedAt: Date?
    public var exitCode: Int32?
    public var status: AgentRunLogStatus
    public var stdout: String
    public var stderr: String

    enum CodingKeys: String, CodingKey {
        case id
        case isShared
        case provider
        case providerKind
        case model
        case requestSummary
        case errorMessage
        case executablePath
        case arguments
        case startedAt
        case endedAt
        case exitCode
        case status
        case stdout
        case stderr
    }

    public var combinedConsoleText: String {
        stdout + stderr
    }

    public init(
        id: String,
        isShared: Bool,
        provider: AgentProvider,
        providerKind: AgentProviderKind? = nil,
        model: String? = nil,
        requestSummary: String? = nil,
        errorMessage: String? = nil,
        executablePath: String? = nil,
        arguments: [String] = [],
        startedAt: Date? = nil,
        endedAt: Date? = nil,
        exitCode: Int32? = nil,
        status: AgentRunLogStatus = .running,
        stdout: String = "",
        stderr: String = ""
    ) {
        self.id = id
        self.isShared = isShared
        self.provider = provider
        self.providerKind = providerKind ?? provider.kind
        self.model = model
        self.requestSummary = requestSummary
        self.errorMessage = errorMessage
        self.executablePath = executablePath
        self.arguments = arguments
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.exitCode = exitCode
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        isShared = try container.decode(Bool.self, forKey: .isShared)
        provider = try container.decode(AgentProvider.self, forKey: .provider)
        providerKind = try container.decodeIfPresent(AgentProviderKind.self, forKey: .providerKind) ?? provider.kind
        model = try container.decodeIfPresent(String.self, forKey: .model)
        requestSummary = try container.decodeIfPresent(String.self, forKey: .requestSummary)
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        executablePath = try container.decodeIfPresent(String.self, forKey: .executablePath)
        arguments = try container.decodeIfPresent([String].self, forKey: .arguments) ?? []
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        exitCode = try container.decodeIfPresent(Int32.self, forKey: .exitCode)
        status = try container.decodeIfPresent(AgentRunLogStatus.self, forKey: .status) ?? .running
        stdout = try container.decodeIfPresent(String.self, forKey: .stdout) ?? ""
        stderr = try container.decodeIfPresent(String.self, forKey: .stderr) ?? ""
    }
}

public struct BatchExportResult: Equatable, Sendable {
    public var archiveURL: URL
    public var missingPreviewPaths: [String]
    public var missingResourcePaths: [String]

    public init(
        archiveURL: URL,
        missingPreviewPaths: [String] = [],
        missingResourcePaths: [String] = []
    ) {
        self.archiveURL = archiveURL
        self.missingPreviewPaths = missingPreviewPaths
        self.missingResourcePaths = missingResourcePaths
    }

    public var missingImageCount: Int {
        missingPreviewPaths.count + missingResourcePaths.count
    }
}

public struct GenerationBatch: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var createdAt: Date
    public var agent: AgentProvider
    public var promptSnapshot: String
    public var sourceInputText: String
    public var outputDirectory: String
    public var mode: GenerationMode
    public var parallelism: Int
    public var callStrategy: AgentCallStrategy
    public var items: [FigmaLinkItem]
    public var runLogsByItemID: [UUID: GenerationRunLog]

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case agent
        case promptSnapshot
        case sourceInputText
        case outputDirectory
        case mode
        case parallelism
        case callStrategy
        case items
        case runLogsByItemID
    }

    public init(
        id: String,
        createdAt: Date,
        agent: AgentProvider,
        promptSnapshot: String,
        sourceInputText: String,
        outputDirectory: String,
        mode: GenerationMode,
        parallelism: Int,
        callStrategy: AgentCallStrategy = .singlePerLink,
        items: [FigmaLinkItem],
        runLogsByItemID: [UUID: GenerationRunLog] = [:]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.agent = agent
        self.promptSnapshot = promptSnapshot
        self.sourceInputText = sourceInputText
        self.outputDirectory = outputDirectory
        self.mode = mode
        self.parallelism = parallelism
        self.callStrategy = callStrategy
        self.items = items
        self.runLogsByItemID = runLogsByItemID
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        agent = try container.decode(AgentProvider.self, forKey: .agent)
        promptSnapshot = try container.decode(String.self, forKey: .promptSnapshot)
        sourceInputText = try container.decode(String.self, forKey: .sourceInputText)
        outputDirectory = try container.decode(String.self, forKey: .outputDirectory)
        mode = try container.decode(GenerationMode.self, forKey: .mode)
        parallelism = try container.decodeIfPresent(Int.self, forKey: .parallelism) ?? AppSettings.defaultValue.parallelism
        callStrategy = try container.decodeIfPresent(AgentCallStrategy.self, forKey: .callStrategy) ?? .singlePerLink
        items = try container.decode([FigmaLinkItem].self, forKey: .items)
        runLogsByItemID = try container.decodeIfPresent([UUID: GenerationRunLog].self, forKey: .runLogsByItemID) ?? [:]
    }
}

public struct ParsedLinkResult: Sendable {
    public let items: [FigmaLinkItem]
    public let errors: [String]

    public init(items: [FigmaLinkItem], errors: [String]) {
        self.items = items
        self.errors = errors
    }
}

public struct PersistedBatch: Sendable {
    public let summary: GenerationBatch
    public let batchDirectory: URL
    public let itemDirectories: [URL]

    public init(summary: GenerationBatch, batchDirectory: URL, itemDirectories: [URL]) {
        self.summary = summary
        self.batchDirectory = batchDirectory
        self.itemDirectories = itemDirectories
    }
}

public struct FigmaNodePayload: Sendable, Equatable {
    public var name: String
    public var previewURL: String?
    public var resources: [FigmaResourceItem]
    public var document: FigmaDocumentNode?

    public init(name: String, previewURL: String?, resources: [FigmaResourceItem], document: FigmaDocumentNode? = nil) {
        self.name = name
        self.previewURL = previewURL
        self.resources = resources
        self.document = document
    }
}
