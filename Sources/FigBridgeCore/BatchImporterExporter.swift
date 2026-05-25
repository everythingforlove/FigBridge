import Foundation

public struct BatchImporterExporter: Sendable {
    public let rootDirectory: URL
    private let archiveStore: BatchArchiveStore

    public init(rootDirectory: URL, archiveStore: BatchArchiveStore) {
        self.rootDirectory = rootDirectory
        self.archiveStore = archiveStore
    }

    public func exportBatch(at batchDirectory: URL, to destinationURL: URL) throws -> BatchExportResult {
        guard FileManager.default.fileExists(atPath: batchDirectory.appendingPathComponent("batch.json").path) else {
            throw BatchStoreError.invalidBatchDirectory
        }
        let persisted = try archiveStore.loadBatch(at: batchDirectory)
        let missingPaths = collectMissingImagePaths(in: persisted.summary)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-qr", destinationURL.path, batchDirectory.lastPathComponent]
        process.currentDirectoryURL = batchDirectory.deletingLastPathComponent()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw BatchStoreError.exportFailed
        }
        return BatchExportResult(
            archiveURL: destinationURL,
            missingPreviewPaths: missingPaths.previews,
            missingResourcePaths: missingPaths.resources
        )
    }

    public func importBatchDirectory(from sourceDirectory: URL) throws -> URL {
        guard FileManager.default.fileExists(atPath: sourceDirectory.appendingPathComponent("batch.json").path) else {
            throw BatchStoreError.invalidBatchDirectory
        }
        try ensureRootDirectoryExists()
        let destinationURL = uniqueImportedDirectoryName(for: sourceDirectory.lastPathComponent)
        try FileManager.default.copyItem(at: sourceDirectory, to: destinationURL)
        _ = try archiveStore.rewriteBatchID(
            at: destinationURL,
            to: destinationURL.lastPathComponent,
            originalDirectory: sourceDirectory
        )
        return destinationURL
    }

    public func importBatchArchive(from archiveURL: URL) throws -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", archiveURL.path, "-d", tempDirectory.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw BatchStoreError.importFailed
        }

        let entries = try FileManager.default.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        guard let batchDirectory = entries.first(where: {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent("batch.json").path)
        }) else {
            throw BatchStoreError.invalidBatchDirectory
        }

        try ensureRootDirectoryExists()
        let destinationURL = uniqueImportedDirectoryName(for: batchDirectory.lastPathComponent)
        try FileManager.default.copyItem(at: batchDirectory, to: destinationURL)
        _ = try archiveStore.rewriteBatchID(
            at: destinationURL,
            to: destinationURL.lastPathComponent,
            originalDirectory: batchDirectory
        )
        return destinationURL
    }

    public func copyFileToDirectory(_ sourceURL: URL, destinationDirectory: URL, preferredName: String? = nil) throws -> URL {
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw BatchStoreError.sourceFileMissing
        }
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let baseName = preferredName ?? sourceURL.lastPathComponent
        let destinationURL = BatchFileNaming.uniqueFileURL(in: destinationDirectory, preferredName: baseName)
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    public func makeCopyPrompt(for items: [FigmaLinkItem]) -> String {
        let resolvedEntries: [(title: String, path: String)] = items.compactMap { item in
            guard let yamlPath = item.generatedYAMLPath else {
                return nil
            }
            let title = item.title ?? item.nodeName ?? item.nodeId
            return (title: title, path: yamlPath)
        }
        guard !resolvedEntries.isEmpty else {
            return "Implement this design from DesignIR files."
        }

        let allPathComponents = resolvedEntries.map { entry in
            URL(fileURLWithPath: entry.path).standardizedFileURL.deletingLastPathComponent().pathComponents
        }
        let sharedPrefixComponents = longestSharedPathPrefix(in: allPathComponents)
        let basePath = normalizedPath(from: sharedPrefixComponents)

        var lines: [String] = ["Implement this design from DesignIR files."]
        if let basePath, !basePath.isEmpty {
            lines.append("BASE: \(basePath)")
            for entry in resolvedEntries {
                let absolutePath = URL(fileURLWithPath: entry.path).standardizedFileURL.path
                if let relativePath = makeRelativePath(absolutePath: absolutePath, basePath: basePath) {
                    lines.append("- \(entry.title)：\(relativePath)")
                } else {
                    lines.append("- \(entry.title)：\(absolutePath)")
                }
            }
        } else {
            for entry in resolvedEntries {
                let absolutePath = URL(fileURLWithPath: entry.path).standardizedFileURL.path
                lines.append("- \(entry.title)：\(absolutePath)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func uniqueImportedDirectoryName(for baseName: String) -> URL {
        let primaryCandidate = rootDirectory.appendingPathComponent(baseName, isDirectory: true)
        guard FileManager.default.fileExists(atPath: primaryCandidate.path) else {
            return primaryCandidate
        }

        var index = 2
        while true {
            let candidate = rootDirectory.appendingPathComponent("\(baseName)(\(index))", isDirectory: true)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }

    private func ensureRootDirectoryExists() throws {
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    }

    private func longestSharedPathPrefix(in paths: [[String]]) -> [String] {
        guard var prefix = paths.first, !prefix.isEmpty else {
            return []
        }
        for path in paths.dropFirst() {
            var index = 0
            let limit = min(prefix.count, path.count)
            while index < limit, prefix[index] == path[index] {
                index += 1
            }
            prefix = Array(prefix.prefix(index))
            if prefix.isEmpty {
                break
            }
        }
        return prefix
    }

    private func normalizedPath(from components: [String]) -> String? {
        guard !components.isEmpty else {
            return nil
        }
        let path = NSString.path(withComponents: components)
        guard path != "/", !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private func makeRelativePath(absolutePath: String, basePath: String) -> String? {
        guard absolutePath.hasPrefix(basePath) else {
            return nil
        }
        let candidate = String(absolutePath.dropFirst(basePath.count))
        if candidate.isEmpty {
            return nil
        }
        if candidate.hasPrefix("/") {
            return String(candidate.dropFirst())
        }
        return candidate
    }

    private func collectMissingImagePaths(in batch: GenerationBatch) -> (previews: [String], resources: [String]) {
        let missingPreviews = batch.items.compactMap { item -> String? in
            guard let path = item.previewImagePath else {
                return nil
            }
            return FileManager.default.fileExists(atPath: path) ? nil : path
        }

        let missingResources = batch.items.flatMap { item in
            item.resourceItems.compactMap { resource -> String? in
                guard let path = resource.localPath else {
                    return nil
                }
                return FileManager.default.fileExists(atPath: path) ? nil : path
            }
        }

        return (missingPreviews, missingResources)
    }
}
