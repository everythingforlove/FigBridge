import Foundation
import Testing
@testable import FigBridgeCore

struct BatchStoreTests {
    @Test func persistedBatchStoresRelativePathsAndReloadsAbsolutePaths() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let store = BatchStore(rootDirectory: sandbox.root)
        let batchDirectory = sandbox.root.appendingPathComponent("batch-1", isDirectory: true)
        let itemDirectory = batchDirectory.appendingPathComponent("items/item-1-1-2", isDirectory: true)
        let yamlDirectory = itemDirectory.appendingPathComponent("yaml", isDirectory: true)
        let assetsDirectory = itemDirectory.appendingPathComponent("assets", isDirectory: true)
        let exportsDirectory = batchDirectory.appendingPathComponent("exports", isDirectory: true)
        try FileManager.default.createDirectory(at: yamlDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: exportsDirectory, withIntermediateDirectories: true)

        let previewURL = assetsDirectory.appendingPathComponent("preview.png")
        let resourceURL = assetsDirectory.appendingPathComponent("1-image.png")
        let yamlURL = yamlDirectory.appendingPathComponent("figma-node-1-2.yaml")
        let outputURL = yamlDirectory.appendingPathComponent("agent-output.txt")
        try Data("preview".utf8).write(to: previewURL)
        try Data("resource".utf8).write(to: resourceURL)
        try "yaml".write(to: yamlURL, atomically: true, encoding: .utf8)
        try "output".write(to: outputURL, atomically: true, encoding: .utf8)

        var item = FigmaLinkItem(
            rawInputLine: "首页",
            title: "首页",
            url: "https://www.figma.com/design/FILE123/App?node-id=1-2",
            fileKey: "FILE123",
            nodeId: "1:2"
        )
        item.previewImagePath = previewURL.path
        item.generatedYAMLPath = yamlURL.path
        item.agentOutputPath = outputURL.path
        item.resourceItems = [
            FigmaResourceItem(name: "image", kind: .image, format: .png, remoteURL: "https://cdn.example/image.png", localPath: resourceURL.path)
        ]

        let batch = GenerationBatch(
            id: "batch-1",
            createdAt: Date(timeIntervalSince1970: 0),
            agent: .codex,
            promptSnapshot: "prompt",
            sourceInputText: "input",
            outputDirectory: exportsDirectory.path,
            mode: .sequential,
            parallelism: 2,
            callStrategy: .singlePerLink,
            items: [item]
        )

        _ = try store.createBatch(batch)

        let batchJSON = try String(contentsOf: batchDirectory.appendingPathComponent("batch.json"), encoding: .utf8)
        #expect(batchJSON.contains("\"outputDirectory\" : \"exports\""))
        #expect(!batchJSON.contains(exportsDirectory.path))
        #expect(batchJSON.contains("items\\/item-1-1-2\\/yaml\\/figma-node-1-2.yaml"))
        #expect(batchJSON.contains("items\\/item-1-1-2\\/assets\\/preview.png"))

        let loaded = try #require(try store.loadBatch(id: "batch-1"))
        let loadedItem = try #require(loaded.summary.items.first)
        #expect(loaded.summary.outputDirectory == exportsDirectory.path)
        #expect(loadedItem.previewImagePath == previewURL.path)
        #expect(loadedItem.generatedYAMLPath == yamlURL.path)
        #expect(loadedItem.agentOutputPath == outputURL.path)
        #expect(loadedItem.resourceItems.first?.localPath == resourceURL.path)
    }

    @Test func createsBatchStructureAndCanRescan() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let store = BatchStore(rootDirectory: sandbox.root)
        let item = FigmaLinkItem(
            rawInputLine: "首页",
            title: "首页",
            url: "https://www.figma.com/design/FILE123/App?node-id=1-2",
            fileKey: "FILE123",
            nodeId: "1:2"
        )
        let batch = GenerationBatch(
            id: "batch-1",
            createdAt: Date(timeIntervalSince1970: 0),
            agent: .codex,
            promptSnapshot: "prompt",
            sourceInputText: "input",
            outputDirectory: sandbox.root.path,
            mode: .sequential,
            parallelism: 2,
            callStrategy: .singlePerLink,
            items: [item]
        )

        let persisted = try store.createBatch(batch)
        let scanned = try store.scanBatches()

        #expect(FileManager.default.fileExists(atPath: persisted.batchDirectory.appendingPathComponent("batch.json").path))
        #expect(FileManager.default.fileExists(atPath: persisted.itemDirectories[0].appendingPathComponent("meta.json").path))
        #expect(scanned.count == 1)
        #expect(scanned[0].summary.items.count == 1)
        #expect(scanned[0].summary.parallelism == 2)
    }

    @Test func copiesPromptFromExistingYamlOnly() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let store = BatchStore(rootDirectory: sandbox.root)
        var item = FigmaLinkItem(
            rawInputLine: "首页",
            title: "首页",
            url: "https://www.figma.com/design/FILE123/App?node-id=1-2",
            fileKey: "FILE123",
            nodeId: "1:2"
        )
        item.generatedYAMLPath = "/tmp/a.yaml"
        let prompt = store.makeCopyPrompt(for: [item])

        #expect(prompt.contains("Implement this design from DesignIR files."))
        #expect(prompt.contains("BASE: /tmp"))
        #expect(prompt.contains("- 首页：a.yaml"))
    }

    @Test func copyPromptFallsBackToAbsolutePathWhenNoUsableBase() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let store = BatchStore(rootDirectory: sandbox.root)
        var itemA = FigmaLinkItem(
            rawInputLine: "A",
            title: "A",
            url: "https://www.figma.com/design/FILE123/App?node-id=1-2",
            fileKey: "FILE123",
            nodeId: "1:2"
        )
        var itemB = FigmaLinkItem(
            rawInputLine: "B",
            title: "B",
            url: "https://www.figma.com/design/FILE456/App?node-id=2-3",
            fileKey: "FILE456",
            nodeId: "2:3"
        )
        itemA.generatedYAMLPath = "/tmp/a.yaml"
        itemB.generatedYAMLPath = "/var/tmp/b.yaml"

        let prompt = store.makeCopyPrompt(for: [itemA, itemB])

        #expect(!prompt.contains("BASE:"))
        #expect(prompt.contains("- A：/tmp/a.yaml"))
        #expect(prompt.contains("- B：/var/tmp/b.yaml"))
    }

    @Test func loadsLegacyBatchWithoutParallelismUsingDefaultValue() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let store = BatchStore(rootDirectory: sandbox.root)
        let batchDirectory = sandbox.root.appendingPathComponent("legacy-batch", isDirectory: true)
        try FileManager.default.createDirectory(at: batchDirectory, withIntermediateDirectories: true)

        let legacyJSON = """
        {
          "agent" : "codex",
          "createdAt" : "1970-01-01T00:00:00Z",
          "id" : "legacy-batch",
          "items" : [ ],
          "mode" : "sequential",
          "outputDirectory" : "\(sandbox.root.path)",
          "promptSnapshot" : "prompt",
          "sourceInputText" : "input"
        }
        """
        try legacyJSON.write(to: batchDirectory.appendingPathComponent("batch.json"), atomically: true, encoding: .utf8)

        let loaded = try #require(try store.loadBatch(id: "legacy-batch"))
        #expect(loaded.summary.parallelism == AppSettings.defaultValue.parallelism)
        #expect(loaded.summary.runLogsByItemID.isEmpty)
    }

    @Test func persistsAndReloadsRunLogsByItemID() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let store = BatchStore(rootDirectory: sandbox.root)
        let item = FigmaLinkItem(
            rawInputLine: "首页",
            title: "首页",
            url: "https://www.figma.com/design/FILE123/App?node-id=1-2",
            fileKey: "FILE123",
            nodeId: "1:2"
        )
        let log = GenerationRunLog(
            id: "run-1",
            isShared: false,
            provider: .codex,
            executablePath: "/usr/bin/env",
            arguments: ["codex"],
            startedAt: Date(timeIntervalSince1970: 1),
            endedAt: Date(timeIntervalSince1970: 2),
            exitCode: 0,
            status: .finished,
            stdout: "ok",
            stderr: ""
        )
        let batch = GenerationBatch(
            id: "batch-with-log",
            createdAt: Date(timeIntervalSince1970: 0),
            agent: .codex,
            promptSnapshot: "prompt",
            sourceInputText: "input",
            outputDirectory: sandbox.root.path,
            mode: .sequential,
            parallelism: 2,
            callStrategy: .singlePerLink,
            items: [item],
            runLogsByItemID: [item.id: log]
        )

        _ = try store.createBatch(batch)
        let loaded = try #require(try store.loadBatch(id: "batch-with-log"))
        #expect(loaded.summary.runLogsByItemID[item.id] == log)
    }

    @Test func createBatchArchivesExternalImageAssetsIntoBatchDirectory() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let store = BatchStore(rootDirectory: sandbox.root.appendingPathComponent("batches"))
        let workspaceAssetsDirectory = sandbox.root
            .appendingPathComponent("__workspace__", isDirectory: true)
            .appendingPathComponent("items/item-1", isDirectory: true)
            .appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceAssetsDirectory, withIntermediateDirectories: true)

        let previewURL = workspaceAssetsDirectory.appendingPathComponent("preview.png")
        let resourceURL = workspaceAssetsDirectory.appendingPathComponent("1-image.png")
        try Data("preview".utf8).write(to: previewURL)
        try Data("resource".utf8).write(to: resourceURL)

        var item = FigmaLinkItem(
            rawInputLine: "首页",
            title: "首页",
            url: "https://www.figma.com/design/FILE123/App?node-id=1-2",
            fileKey: "FILE123",
            nodeId: "1:2"
        )
        item.previewImagePath = previewURL.path
        item.resourceItems = [
            FigmaResourceItem(
                name: "image",
                kind: .image,
                format: .png,
                remoteURL: "https://cdn.example/image.png",
                localPath: resourceURL.path
            )
        ]

        let batch = GenerationBatch(
            id: "batch-archive-assets",
            createdAt: Date(timeIntervalSince1970: 0),
            agent: .codex,
            promptSnapshot: "prompt",
            sourceInputText: "input",
            outputDirectory: sandbox.root.path,
            mode: .sequential,
            parallelism: 2,
            callStrategy: .singlePerLink,
            items: [item]
        )

        let persisted = try store.createBatch(batch)
        let persistedItem = try #require(persisted.summary.items.first)
        let archivedPreviewPath = try #require(persistedItem.previewImagePath)
        let archivedResourcePath = try #require(persistedItem.resourceItems.first?.localPath)

        #expect(archivedPreviewPath.hasPrefix(persisted.batchDirectory.path))
        #expect(archivedResourcePath.hasPrefix(persisted.batchDirectory.path))
        #expect(FileManager.default.fileExists(atPath: archivedPreviewPath))
        #expect(FileManager.default.fileExists(atPath: archivedResourcePath))

        let batchJSON = try String(contentsOf: persisted.batchDirectory.appendingPathComponent("batch.json"), encoding: .utf8)
        #expect(batchJSON.contains("items\\/"))
        #expect(!batchJSON.contains("__workspace__"))
    }

    @Test func renameBatchRewritesItemPathsUsingDestinationDirectoryContext() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let store = BatchStore(rootDirectory: sandbox.root)
        let item = FigmaLinkItem(
            rawInputLine: "首页",
            title: "首页",
            url: "https://www.figma.com/design/FILE123/App?node-id=1-2",
            fileKey: "FILE123",
            nodeId: "1:2"
        )
        let batch = GenerationBatch(
            id: "batch-1",
            createdAt: Date(timeIntervalSince1970: 0),
            agent: .codex,
            promptSnapshot: "prompt",
            sourceInputText: "input",
            outputDirectory: sandbox.root.path,
            mode: .sequential,
            parallelism: 2,
            callStrategy: .singlePerLink,
            items: [item]
        )

        let persisted = try store.createBatch(batch)
        let itemDirectory = try #require(persisted.itemDirectories.first)
        let assetsDirectory = itemDirectory.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)

        let yamlURL = itemDirectory.appendingPathComponent("generated.yaml")
        let previewURL = assetsDirectory.appendingPathComponent("preview.png")
        try "yaml-renamed".write(to: yamlURL, atomically: true, encoding: .utf8)
        try Data("preview-renamed".utf8).write(to: previewURL)

        var updatedItem = try #require(persisted.summary.items.first)
        updatedItem.generatedYAMLPath = yamlURL.path
        updatedItem.previewImagePath = previewURL.path

        _ = try store.updateBatch(
            id: persisted.summary.id,
            sourceInputText: persisted.summary.sourceInputText,
            agent: persisted.summary.agent,
            promptSnapshot: persisted.summary.promptSnapshot,
            outputDirectory: URL(fileURLWithPath: persisted.summary.outputDirectory, isDirectory: true),
            mode: persisted.summary.mode,
            parallelism: persisted.summary.parallelism,
            callStrategy: persisted.summary.callStrategy,
            items: [updatedItem]
        )

        let renamed = try store.renameBatch(id: "batch-1", to: "batch-renamed")
        let renamedItem = try #require(renamed.summary.items.first)
        let renamedYamlPath = try #require(renamedItem.generatedYAMLPath)
        let renamedPreviewPath = try #require(renamedItem.previewImagePath)

        #expect(renamedYamlPath.hasPrefix(renamed.batchDirectory.path))
        #expect(renamedPreviewPath.hasPrefix(renamed.batchDirectory.path))
        #expect(!renamedYamlPath.contains("/batch-1/"))
        #expect(!renamedPreviewPath.contains("/batch-1/"))
        #expect(try String(contentsOfFile: renamedYamlPath, encoding: .utf8) == "yaml-renamed")
        #expect(FileManager.default.fileExists(atPath: renamedPreviewPath))
    }
}
