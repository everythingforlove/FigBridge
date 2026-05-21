import Foundation

public struct BatchPathRebaser: Sendable {
    public init() {}

    public func rebasePathsIfNeeded(in batch: GenerationBatch, from sourceDirectory: URL?, to destinationDirectory: URL) -> GenerationBatch {
        guard let sourceDirectory else {
            return batch
        }

        let sourceBasePath = sourceDirectory.standardizedFileURL.path
        let destinationBasePath = destinationDirectory.standardizedFileURL.path
        guard sourceBasePath != destinationBasePath else {
            return batch
        }

        var rebased = batch
        rebased.outputDirectory = rebasePath(batch.outputDirectory, from: sourceBasePath, to: destinationBasePath) ?? batch.outputDirectory
        rebased.items = batch.items.map { item in
            var updatedItem = item
            updatedItem.previewImagePath = rebasePath(item.previewImagePath, from: sourceBasePath, to: destinationBasePath)
            updatedItem.generatedYAMLPath = rebasePath(item.generatedYAMLPath, from: sourceBasePath, to: destinationBasePath)
            updatedItem.agentOutputPath = rebasePath(item.agentOutputPath, from: sourceBasePath, to: destinationBasePath)
            updatedItem.resourceItems = item.resourceItems.map { resource in
                var updatedResource = resource
                updatedResource.localPath = rebasePath(resource.localPath, from: sourceBasePath, to: destinationBasePath)
                return updatedResource
            }
            return updatedItem
        }
        return rebased
    }

    public func makePersistable(batch: GenerationBatch, batchDirectory: URL) -> GenerationBatch {
        var persisted = batch
        persisted.outputDirectory = relativizePath(batch.outputDirectory, batchDirectory: batchDirectory) ?? BatchStore.exportsDirectoryName
        persisted.items = batch.items.map { makePersistable(item: $0, batchDirectory: batchDirectory) }
        return persisted
    }

    public func makePersistable(item: FigmaLinkItem, batchDirectory: URL) -> FigmaLinkItem {
        var persisted = item
        persisted.previewImagePath = relativizePath(item.previewImagePath, batchDirectory: batchDirectory)
        persisted.generatedYAMLPath = relativizePath(item.generatedYAMLPath, batchDirectory: batchDirectory)
        persisted.agentOutputPath = relativizePath(item.agentOutputPath, batchDirectory: batchDirectory)
        persisted.resourceItems = item.resourceItems.map { resource in
            var updated = resource
            updated.localPath = relativizePath(resource.localPath, batchDirectory: batchDirectory)
            return updated
        }
        return persisted
    }

    public func makeRuntimeBatch(from batch: GenerationBatch, batchDirectory: URL) -> GenerationBatch {
        var runtime = batch
        runtime.outputDirectory = absolutizePath(batch.outputDirectory, batchDirectory: batchDirectory)
            ?? batchDirectory.appendingPathComponent(BatchStore.exportsDirectoryName, isDirectory: true).path
        runtime.items = batch.items.map { makeRuntimeItem(from: $0, batchDirectory: batchDirectory) }
        return runtime
    }

    public func makeRuntimeItem(from item: FigmaLinkItem, batchDirectory: URL) -> FigmaLinkItem {
        var runtime = item
        runtime.previewImagePath = absolutizePath(item.previewImagePath, batchDirectory: batchDirectory)
        runtime.generatedYAMLPath = absolutizePath(item.generatedYAMLPath, batchDirectory: batchDirectory)
        runtime.agentOutputPath = absolutizePath(item.agentOutputPath, batchDirectory: batchDirectory)
        runtime.resourceItems = item.resourceItems.map { resource in
            var updated = resource
            updated.localPath = absolutizePath(resource.localPath, batchDirectory: batchDirectory)
            return updated
        }
        return runtime
    }

    public func relativizePath(_ path: String?, batchDirectory: URL) -> String? {
        guard let path else {
            return nil
        }
        let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        let basePath = batchDirectory.standardizedFileURL.path
        guard standardizedPath == basePath || standardizedPath.hasPrefix(basePath + "/") else {
            return path
        }
        let relative = String(standardizedPath.dropFirst(basePath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return relative.isEmpty ? "." : relative
    }

    public func absolutizePath(_ path: String?, batchDirectory: URL) -> String? {
        guard let path, !path.isEmpty else {
            return nil
        }
        if path == "." {
            return batchDirectory.path
        }
        if path.hasPrefix("/") {
            return path
        }
        return batchDirectory.appendingPathComponent(path).path
    }

    private func rebasePath(_ path: String?, from sourceBasePath: String, to destinationBasePath: String) -> String? {
        guard let path, !path.isEmpty else {
            return path
        }
        let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        if standardizedPath == sourceBasePath {
            return destinationBasePath
        }
        guard standardizedPath.hasPrefix(sourceBasePath + "/") else {
            return path
        }
        let suffix = standardizedPath.dropFirst(sourceBasePath.count)
        return destinationBasePath + suffix
    }
}
