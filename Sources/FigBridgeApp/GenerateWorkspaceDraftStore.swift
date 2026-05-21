import Foundation
import FigBridgeCore

struct GenerateWorkspaceDraft: Codable, Equatable {
    var selectedAgentID: String?
    var promptTemplate: String
    var outputDirectoryPath: String
    var mode: GenerationMode
    var parallelism: Int
    var callStrategy: AgentCallStrategy
    var inputText: String
    var items: [FigmaLinkItem]
    var selectedItemID: UUID?
    var currentBatchID: String?
    var currentBatchDirectory: String?

    enum CodingKeys: String, CodingKey {
        case selectedAgentID
        case promptTemplate
        case outputDirectoryPath
        case mode
        case parallelism
        case callStrategy
        case inputText
        case items
        case selectedItemID
        case currentBatchID
        case currentBatchDirectory
    }

    init(
        selectedAgentID: String?,
        promptTemplate: String,
        outputDirectoryPath: String,
        mode: GenerationMode,
        parallelism: Int,
        callStrategy: AgentCallStrategy,
        inputText: String,
        items: [FigmaLinkItem],
        selectedItemID: UUID?,
        currentBatchID: String?,
        currentBatchDirectory: String?
    ) {
        self.selectedAgentID = selectedAgentID
        self.promptTemplate = promptTemplate
        self.outputDirectoryPath = outputDirectoryPath
        self.mode = mode
        self.parallelism = parallelism
        self.callStrategy = callStrategy
        self.inputText = inputText
        self.items = items
        self.selectedItemID = selectedItemID
        self.currentBatchID = currentBatchID
        self.currentBatchDirectory = currentBatchDirectory
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selectedAgentID = try container.decodeIfPresent(String.self, forKey: .selectedAgentID)
        promptTemplate = AppSettings.migratingLegacyPromptIfNeeded(try container.decode(String.self, forKey: .promptTemplate))
        outputDirectoryPath = try container.decode(String.self, forKey: .outputDirectoryPath)
        mode = try container.decode(GenerationMode.self, forKey: .mode)
        parallelism = try container.decode(Int.self, forKey: .parallelism)
        callStrategy = try container.decodeIfPresent(AgentCallStrategy.self, forKey: .callStrategy) ?? .singlePerLink
        inputText = try container.decode(String.self, forKey: .inputText)
        items = try container.decode([FigmaLinkItem].self, forKey: .items)
        selectedItemID = try container.decodeIfPresent(UUID.self, forKey: .selectedItemID)
        currentBatchID = try container.decodeIfPresent(String.self, forKey: .currentBatchID)
        currentBatchDirectory = try container.decodeIfPresent(String.self, forKey: .currentBatchDirectory)
    }
}

final class GenerateWorkspaceDraftStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL) {
        self.fileURL = fileURL
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
    }

    func load() -> GenerateWorkspaceDraft? {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        return try? decoder.decode(GenerateWorkspaceDraft.self, from: data)
    }

    func save(_ draft: GenerateWorkspaceDraft) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(draft)
        try data.write(to: fileURL)
    }

    func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }
        try FileManager.default.removeItem(at: fileURL)
    }
}
