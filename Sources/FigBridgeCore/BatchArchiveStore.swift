import Foundation

public final class BatchArchiveStore: Sendable {
    public let rootDirectory: URL

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let pathRebaser: BatchPathRebaser
    private let assetArchiver: BatchAssetArchiver

    public init(
        rootDirectory: URL,
        pathRebaser: BatchPathRebaser = BatchPathRebaser(),
        assetArchiver: BatchAssetArchiver = BatchAssetArchiver()
    ) {
        self.rootDirectory = rootDirectory
        self.pathRebaser = pathRebaser
        self.assetArchiver = assetArchiver
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public func createBatch(_ batch: GenerationBatch) throws -> PersistedBatch {
        try ensureRootDirectoryExists()
        let batchDirectory = rootDirectory.appendingPathComponent(batch.id, isDirectory: true)
        try FileManager.default.createDirectory(at: batchDirectory, withIntermediateDirectories: true)
        return try writeBatch(batch, into: batchDirectory)
    }

    public func loadBatch(id: String) throws -> PersistedBatch? {
        let batchDirectory = batchDirectory(for: id)
        guard FileManager.default.fileExists(atPath: batchDirectory.appendingPathComponent("batch.json").path) else {
            return nil
        }
        return try loadBatch(at: batchDirectory)
    }

    public func loadBatch(at directory: URL) throws -> PersistedBatch {
        let batchURL = directory.appendingPathComponent("batch.json")
        let data = try Data(contentsOf: batchURL)
        let batch = reconcileGeneratedArtifactsIfNeeded(
            in: pathRebaser.makeRuntimeBatch(from: try decoder.decode(GenerationBatch.self, from: data), batchDirectory: directory),
            batchDirectory: directory
        )
        let itemDirectories = batch.items.compactMap { itemDirectory(in: directory, itemID: $0.id) }
        return PersistedBatch(summary: batch, batchDirectory: directory, itemDirectories: itemDirectories)
    }

    public func updateBatch(
        id: String,
        sourceInputText: String,
        agent: AgentProvider,
        promptSnapshot: String,
        outputDirectory: URL,
        mode: GenerationMode,
        parallelism: Int,
        callStrategy: AgentCallStrategy,
        items: [FigmaLinkItem],
        runLogsByItemID: [UUID: GenerationRunLog]? = nil
    ) throws -> PersistedBatch {
        let batchDirectory = batchDirectory(for: id)
        guard FileManager.default.fileExists(atPath: batchDirectory.appendingPathComponent("batch.json").path) else {
            throw BatchStoreError.invalidBatchDirectory
        }
        let existing = try loadBatch(at: batchDirectory)
        return try writeUpdatedBatch(
            existing: existing,
            sourceInputText: sourceInputText,
            agent: agent,
            promptSnapshot: promptSnapshot,
            outputDirectory: outputDirectory,
            mode: mode,
            parallelism: parallelism,
            callStrategy: callStrategy,
            items: items,
            runLogsByItemID: runLogsByItemID
        )
    }

    public func deleteBatchItem(batchID: String, itemID: UUID) throws {
        guard let persisted = try loadBatch(id: batchID) else {
            throw BatchStoreError.invalidBatchDirectory
        }
        let updatedItems = persisted.summary.items.filter { $0.id != itemID }
        guard updatedItems.count != persisted.summary.items.count else {
            return
        }

        if let itemDirectory = itemDirectory(in: persisted.batchDirectory, itemID: itemID),
           FileManager.default.fileExists(atPath: itemDirectory.path) {
            try FileManager.default.removeItem(at: itemDirectory)
        }

        _ = try writeUpdatedBatch(
            existing: persisted,
            sourceInputText: persisted.summary.sourceInputText,
            agent: persisted.summary.agent,
            promptSnapshot: persisted.summary.promptSnapshot,
            outputDirectory: URL(fileURLWithPath: persisted.summary.outputDirectory, isDirectory: true),
            mode: persisted.summary.mode,
            parallelism: persisted.summary.parallelism,
            callStrategy: persisted.summary.callStrategy,
            items: updatedItems,
            runLogsByItemID: persisted.summary.runLogsByItemID
        )
    }

    public func updateBatchItem(batchID: String, item: FigmaLinkItem) throws -> PersistedBatch {
        guard let persisted = try loadBatch(id: batchID) else {
            throw BatchStoreError.invalidBatchDirectory
        }
        var updatedItems = persisted.summary.items
        guard let index = updatedItems.firstIndex(where: { $0.id == item.id }) else {
            return persisted
        }
        updatedItems[index] = item
        return try writeUpdatedBatch(
            existing: persisted,
            sourceInputText: persisted.summary.sourceInputText,
            agent: persisted.summary.agent,
            promptSnapshot: persisted.summary.promptSnapshot,
            outputDirectory: URL(fileURLWithPath: persisted.summary.outputDirectory, isDirectory: true),
            mode: persisted.summary.mode,
            parallelism: persisted.summary.parallelism,
            callStrategy: persisted.summary.callStrategy,
            items: updatedItems,
            runLogsByItemID: persisted.summary.runLogsByItemID
        )
    }

    public func renameBatch(id: String, to newID: String) throws -> PersistedBatch {
        guard let persisted = try loadBatch(id: id) else {
            throw BatchStoreError.invalidBatchDirectory
        }

        let trimmedID = newID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            throw BatchStoreError.invalidBatchName
        }
        guard trimmedID != id else {
            return persisted
        }

        try ensureRootDirectoryExists()
        let destinationDirectory = rootDirectory.appendingPathComponent(trimmedID, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: destinationDirectory.path) else {
            throw BatchStoreError.batchAlreadyExists
        }

        try FileManager.default.moveItem(at: persisted.batchDirectory, to: destinationDirectory)
        return try rewriteBatchID(
            at: destinationDirectory,
            to: trimmedID,
            originalDirectory: persisted.batchDirectory
        )
    }

    public func scanBatches() throws -> [PersistedBatch] {
        guard FileManager.default.fileExists(atPath: rootDirectory.path) else {
            return []
        }
        let directories = try FileManager.default.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        return try directories.compactMap { url in
            let batchURL = url.appendingPathComponent("batch.json")
            guard FileManager.default.fileExists(atPath: batchURL.path) else {
                return nil
            }
            return try loadBatch(at: url)
        }
        .sorted { $0.summary.createdAt > $1.summary.createdAt }
    }

    public func deleteBatch(at batchDirectory: URL) throws {
        guard FileManager.default.fileExists(atPath: batchDirectory.appendingPathComponent("batch.json").path) else {
            throw BatchStoreError.invalidBatchDirectory
        }
        try FileManager.default.removeItem(at: batchDirectory)
    }

    public func rewriteBatchID(at batchDirectory: URL, to batchID: String, originalDirectory: URL? = nil) throws -> PersistedBatch {
        let persisted = try loadBatch(at: batchDirectory)
        let normalizedBatch = pathRebaser.rebasePathsIfNeeded(
            in: persisted.summary,
            from: originalDirectory,
            to: batchDirectory
        )
        let updatedBatch = GenerationBatch(
            id: batchID,
            createdAt: normalizedBatch.createdAt,
            agent: normalizedBatch.agent,
            promptSnapshot: normalizedBatch.promptSnapshot,
            sourceInputText: normalizedBatch.sourceInputText,
            outputDirectory: normalizedBatch.outputDirectory,
            mode: normalizedBatch.mode,
            parallelism: normalizedBatch.parallelism,
            callStrategy: normalizedBatch.callStrategy,
            items: normalizedBatch.items,
            runLogsByItemID: normalizedBatch.runLogsByItemID
        )
        return try writeBatch(updatedBatch, into: batchDirectory)
    }

    public func batchDirectory(for id: String) -> URL {
        rootDirectory.appendingPathComponent(id, isDirectory: true)
    }

    public func exportsDirectory(forBatchID id: String) -> URL {
        exportsDirectory(for: batchDirectory(for: id))
    }

    public func exportsDirectory(for batchDirectory: URL) -> URL {
        batchDirectory.appendingPathComponent(BatchStore.exportsDirectoryName, isDirectory: true)
    }

    private func writeUpdatedBatch(
        existing: PersistedBatch,
        sourceInputText: String,
        agent: AgentProvider,
        promptSnapshot: String,
        outputDirectory: URL,
        mode: GenerationMode,
        parallelism: Int,
        callStrategy: AgentCallStrategy,
        items: [FigmaLinkItem],
        runLogsByItemID: [UUID: GenerationRunLog]?
    ) throws -> PersistedBatch {
        let batch = GenerationBatch(
            id: existing.summary.id,
            createdAt: existing.summary.createdAt,
            agent: agent,
            promptSnapshot: promptSnapshot,
            sourceInputText: sourceInputText,
            outputDirectory: outputDirectory.path,
            mode: mode,
            parallelism: parallelism,
            callStrategy: callStrategy,
            items: items,
            runLogsByItemID: runLogsByItemID ?? existing.summary.runLogsByItemID
        )
        return try writeBatch(batch, into: existing.batchDirectory)
    }

    private func writeBatch(_ batch: GenerationBatch, into batchDirectory: URL) throws -> PersistedBatch {
        let sourceInputURL = batchDirectory.appendingPathComponent("source-input.txt")
        try batch.sourceInputText.write(to: sourceInputURL, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: exportsDirectory(for: batchDirectory), withIntermediateDirectories: true)

        let itemsDirectory = batchDirectory.appendingPathComponent(BatchStore.itemsDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: itemsDirectory, withIntermediateDirectories: true)

        let archivedBatch = try assetArchiver.archiveBatchAssetsIfNeeded(batch, batchDirectory: batchDirectory, itemsDirectory: itemsDirectory)
        let existingDirectories = existingItemDirectoryMap(in: itemsDirectory)
        let validDirectoryNames = Set(archivedBatch.items.map { BatchStore.itemDirectoryName(for: $0) })

        for (name, url) in existingDirectories where !validDirectoryNames.contains(name) {
            try? FileManager.default.removeItem(at: url)
        }

        var itemDirectories: [URL] = []
        for item in archivedBatch.items {
            let itemDirectory = itemsDirectory.appendingPathComponent(BatchStore.itemDirectoryName(for: item), isDirectory: true)
            try FileManager.default.createDirectory(at: itemDirectory, withIntermediateDirectories: true)
            let metaURL = itemDirectory.appendingPathComponent("meta.json")
            let data = try encoder.encode(pathRebaser.makePersistable(item: item, batchDirectory: batchDirectory))
            try data.write(to: metaURL)
            itemDirectories.append(itemDirectory)
        }

        let batchURL = batchDirectory.appendingPathComponent("batch.json")
        let batchData = try encoder.encode(pathRebaser.makePersistable(batch: archivedBatch, batchDirectory: batchDirectory))
        try batchData.write(to: batchURL)

        return PersistedBatch(
            summary: pathRebaser.makeRuntimeBatch(from: archivedBatch, batchDirectory: batchDirectory),
            batchDirectory: batchDirectory,
            itemDirectories: itemDirectories
        )
    }

    private func existingItemDirectoryMap(in itemsDirectory: URL) -> [String: URL] {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: itemsDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: entries.map { ($0.lastPathComponent, $0) })
    }

    private func itemDirectory(in batchDirectory: URL, itemID: UUID) -> URL? {
        let itemsDirectory = batchDirectory.appendingPathComponent(BatchStore.itemsDirectoryName, isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(at: itemsDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return nil
        }
        let prefix = itemID.uuidString.lowercased()
        return entries.first(where: { $0.lastPathComponent.hasPrefix(prefix) })
    }

    private func reconcileGeneratedArtifactsIfNeeded(in batch: GenerationBatch, batchDirectory: URL) -> GenerationBatch {
        var reconciled = batch
        reconciled.items = batch.items.map { item in
            guard let itemDirectory = itemDirectory(in: batchDirectory, itemID: item.id) else {
                return item
            }

            var updated = item
            let designDirectory = itemDirectory.appendingPathComponent("design-ir", isDirectory: true)
            let designURL = designDirectory.appendingPathComponent(DesignPackageStore.designFilename)
            if updated.generatedYAMLPath == nil,
               designFileCanBeLoaded(at: designURL) {
                updated.generatedYAMLPath = designURL.path
                updated.generationStatus = .success
                updated.errorMessage = nil
                updated.logSummary = "已恢复 DesignIR"
            }

            let rawOutputURL = designDirectory.appendingPathComponent("agent-output.txt")
            if updated.agentOutputPath == nil,
               FileManager.default.fileExists(atPath: rawOutputURL.path) {
                updated.agentOutputPath = rawOutputURL.path
            }

            return updated
        }
        return reconciled
    }

    private func designFileCanBeLoaded(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              !data.isEmpty else {
            return false
        }
        return (try? JSONDecoder().decode(DesignIR.self, from: data)) != nil
    }

    private func ensureRootDirectoryExists() throws {
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    }
}
