import Foundation

public final class BatchStore: Sendable {
    public let rootDirectory: URL

    private let archiveStore: BatchArchiveStore
    private let importerExporter: BatchImporterExporter

    public static let exportsDirectoryName = "exports"
    public static let itemsDirectoryName = "items"

    /// 把字符串里的 `:` 替换为 `-`，让它能直接作为路径片段。Figma 的 nodeId / node name 都可能含 `:`。
    public static func pathSafe(_ component: String) -> String {
        component.replacingOccurrences(of: ":", with: "-")
    }

    /// 条目落盘目录名：`<uuid-小写>-<pathSafe(nodeId)>`。所有写盘/读盘路径都基于此构造。
    public static func itemDirectoryName(for item: FigmaLinkItem) -> String {
        "\(item.id.uuidString.lowercased())-\(pathSafe(item.nodeId))"
    }

    /// 条目所在目录绝对路径：`<batchDirectory>/items/<itemDirectoryName>/`。
    public static func itemDirectory(in batchDirectory: URL, item: FigmaLinkItem) -> URL {
        batchDirectory
            .appendingPathComponent(itemsDirectoryName, isDirectory: true)
            .appendingPathComponent(itemDirectoryName(for: item), isDirectory: true)
    }

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
        let archiveStore = BatchArchiveStore(rootDirectory: rootDirectory)
        self.archiveStore = archiveStore
        importerExporter = BatchImporterExporter(rootDirectory: rootDirectory, archiveStore: archiveStore)
    }

    public func createBatch(_ batch: GenerationBatch) throws -> PersistedBatch {
        try archiveStore.createBatch(batch)
    }

    public func batchDirectory(for id: String) -> URL {
        archiveStore.batchDirectory(for: id)
    }

    public func exportsDirectory(forBatchID id: String) -> URL {
        archiveStore.exportsDirectory(forBatchID: id)
    }

    public func exportsDirectory(for batchDirectory: URL) -> URL {
        archiveStore.exportsDirectory(for: batchDirectory)
    }

    public func loadBatch(id: String) throws -> PersistedBatch? {
        try archiveStore.loadBatch(id: id)
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
        try archiveStore.updateBatch(
            id: id,
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
        try archiveStore.deleteBatchItem(batchID: batchID, itemID: itemID)
    }

    public func updateBatchItem(batchID: String, item: FigmaLinkItem) throws -> PersistedBatch {
        try archiveStore.updateBatchItem(batchID: batchID, item: item)
    }

    public func renameBatch(id: String, to newID: String) throws -> PersistedBatch {
        try archiveStore.renameBatch(id: id, to: newID)
    }

    public func scanBatches() throws -> [PersistedBatch] {
        try archiveStore.scanBatches()
    }

    public func makeCopyPrompt(for items: [FigmaLinkItem]) -> String {
        importerExporter.makeCopyPrompt(for: items)
    }

    public func exportBatch(at batchDirectory: URL, to destinationURL: URL) throws -> BatchExportResult {
        try importerExporter.exportBatch(at: batchDirectory, to: destinationURL)
    }

    public func importBatchDirectory(from sourceDirectory: URL) throws -> URL {
        try importerExporter.importBatchDirectory(from: sourceDirectory)
    }

    public func importBatchArchive(from archiveURL: URL) throws -> URL {
        try importerExporter.importBatchArchive(from: archiveURL)
    }

    public func deleteBatch(at batchDirectory: URL) throws {
        try archiveStore.deleteBatch(at: batchDirectory)
    }

    public func copyFileToDirectory(_ sourceURL: URL, destinationDirectory: URL, preferredName: String? = nil) throws -> URL {
        try importerExporter.copyFileToDirectory(sourceURL, destinationDirectory: destinationDirectory, preferredName: preferredName)
    }
}

public enum BatchStoreError: LocalizedError {
    case invalidBatchDirectory
    case invalidBatchName
    case batchAlreadyExists
    case exportFailed
    case importFailed
    case sourceFileMissing

    public var errorDescription: String? {
        switch self {
        case .invalidBatchDirectory:
            "批次目录缺少 batch.json"
        case .invalidBatchName:
            "批次名称不能为空"
        case .batchAlreadyExists:
            "批次名称已存在"
        case .exportFailed:
            "导出批次失败"
        case .importFailed:
            "导入批次失败"
        case .sourceFileMissing:
            "源文件不存在"
        }
    }
}
