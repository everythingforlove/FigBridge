import Foundation

public struct BatchAssetArchiver: Sendable {
    public init() {}

    public func archiveBatchAssetsIfNeeded(_ batch: GenerationBatch, batchDirectory: URL, itemsDirectory: URL) throws -> GenerationBatch {
        var archivedBatch = batch
        archivedBatch.items = try batch.items.map { item in
            let itemDirectory = itemsDirectory.appendingPathComponent(BatchStore.itemDirectoryName(for: item), isDirectory: true)
            return try archiveItemAssetsIfNeeded(item, batchDirectory: batchDirectory, itemDirectory: itemDirectory)
        }
        return archivedBatch
    }

    private func archiveItemAssetsIfNeeded(_ item: FigmaLinkItem, batchDirectory: URL, itemDirectory: URL) throws -> FigmaLinkItem {
        var archivedItem = item
        let assetsDirectory = itemDirectory.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)

        archivedItem.previewImagePath = try archiveLocalAssetIfNeeded(
            item.previewImagePath,
            batchDirectory: batchDirectory,
            destinationDirectory: assetsDirectory,
            preferredName: "preview.png"
        )

        archivedItem.resourceItems = try item.resourceItems.map { resource in
            var updated = resource
            let fallbackName = resource.localPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "\(resource.name).\(resource.format.rawValue)"
            updated.localPath = try archiveLocalAssetIfNeeded(
                resource.localPath,
                batchDirectory: batchDirectory,
                destinationDirectory: assetsDirectory,
                preferredName: fallbackName
            )
            return updated
        }

        return archivedItem
    }

    private func archiveLocalAssetIfNeeded(
        _ path: String?,
        batchDirectory: URL,
        destinationDirectory: URL,
        preferredName: String
    ) throws -> String? {
        guard let path, !path.isEmpty else {
            return nil
        }

        let sourceURL = URL(fileURLWithPath: path).standardizedFileURL
        let batchPath = batchDirectory.standardizedFileURL.path
        let sourcePath = sourceURL.path
        guard FileManager.default.fileExists(atPath: sourcePath) else {
            return path
        }

        if sourcePath == batchPath || sourcePath.hasPrefix(batchPath + "/") {
            return sourcePath
        }

        let destinationURL = destinationDirectory.appendingPathComponent(preferredName).standardizedFileURL
        if sourcePath == destinationURL.path {
            return destinationURL.path
        }

        let resolvedDestinationURL: URL
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            if FileManager.default.contentsEqual(atPath: sourceURL.path, andPath: destinationURL.path) {
                resolvedDestinationURL = destinationURL
            } else {
                resolvedDestinationURL = BatchFileNaming.uniqueFileURL(in: destinationDirectory, preferredName: preferredName)
            }
        } else {
            resolvedDestinationURL = destinationURL
        }

        if !FileManager.default.fileExists(atPath: resolvedDestinationURL.path) {
            try FileManager.default.copyItem(at: sourceURL, to: resolvedDestinationURL)
        }
        return resolvedDestinationURL.path
    }
}

enum BatchFileNaming {
    static func uniqueFileURL(in directory: URL, preferredName: String) -> URL {
        let candidate = directory.appendingPathComponent(preferredName)
        guard !FileManager.default.fileExists(atPath: candidate.path) else {
            let stem = candidate.deletingPathExtension().lastPathComponent
            let ext = candidate.pathExtension
            var index = 2
            while true {
                let filename = ext.isEmpty ? "\(stem)-\(index)" : "\(stem)-\(index).\(ext)"
                let next = directory.appendingPathComponent(filename)
                if !FileManager.default.fileExists(atPath: next.path) {
                    return next
                }
                index += 1
            }
        }
        return candidate
    }
}
