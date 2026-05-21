import Foundation

public final class SettingsStore: Sendable {
    public let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) {
        self.fileURL = fileURL
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
    }

    public func load() throws -> AppSettings {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .defaultValue
        }
        let data = try Data(contentsOf: fileURL)
        var settings = try decoder.decode(AppSettings.self, from: data)
        settings.promptTemplate = AppSettings.migratingLegacyPromptIfNeeded(settings.promptTemplate)
        return settings
    }

    public func save(_ settings: AppSettings) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(settings)
        try data.write(to: fileURL)
    }

    public func loadValidatingSelectedAgent(availableAgents: [AgentProvider]) throws -> AppSettings {
        var settings = try load()
        if let selectedAgentID = settings.selectedAgentID,
           !availableAgents.map(\.id).contains(selectedAgentID) {
            settings.selectedAgentID = nil
        }
        return settings
    }
}
