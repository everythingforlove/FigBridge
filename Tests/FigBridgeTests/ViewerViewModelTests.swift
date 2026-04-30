import Foundation
import Testing
@testable import FigBridgeCore
@testable import FigBridgeApp

@MainActor
struct ViewerViewModelTests {
    @Test func reloadSelectsFirstBatchAndFirstItemAndLoadsYaml() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let store = BatchStore(rootDirectory: sandbox.root)
        _ = try makePersistedBatch(
            store: store,
            id: "batch-1",
            createdAt: Date(timeIntervalSince1970: 10),
            sourceInputText: "source-1",
            items: [
                makeItem(title: "Item A", nodeId: "1:1", yamlText: "yaml-a"),
                makeItem(title: "Item B", nodeId: "1:2", yamlText: "yaml-b")
            ]
        )

        let viewModel = ViewerViewModel(batchStore: store)

        viewModel.reload()

        #expect(viewModel.selectedBatch?.summary.id == "batch-1")
        #expect(viewModel.selectedItem?.title == "Item A")
        #expect(viewModel.selectedYAMLText == "yaml-a")
        #expect(viewModel.selectedSourceInputText == "source-1")
    }

    @Test func switchingSelectedItemReloadsYamlText() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let store = BatchStore(rootDirectory: sandbox.root)
        let persisted = try makePersistedBatch(
            store: store,
            id: "batch-1",
            createdAt: Date(timeIntervalSince1970: 10),
            sourceInputText: "source-1",
            items: [
                makeItem(title: "Item A", nodeId: "1:1", yamlText: "yaml-a"),
                makeItem(title: "Item B", nodeId: "1:2", yamlText: "yaml-b")
            ]
        )

        let viewModel = ViewerViewModel(batchStore: store)
        viewModel.reload()

        viewModel.selectedItemID = persisted.summary.items[1].id

        #expect(viewModel.selectedItem?.title == "Item B")
        #expect(viewModel.selectedYAMLText == "yaml-b")
        #expect(viewModel.selectedRunLog?.stdout == "stdout-2")
    }

    @Test func selectingItemWithoutRunLogClearsSelectedRunLog() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let store = BatchStore(rootDirectory: sandbox.root)
        let persisted = try makePersistedBatch(
            store: store,
            id: "batch-1",
            createdAt: Date(timeIntervalSince1970: 10),
            sourceInputText: "source-1",
            items: [
                makeItem(title: "Item A", nodeId: "1:1", yamlText: "yaml-a"),
                makeItem(title: "Item B", nodeId: "1:2", yamlText: "yaml-b")
            ],
            runLogsByItemID: [:]
        )

        let viewModel = ViewerViewModel(batchStore: store)
        viewModel.reload()
        #expect(viewModel.selectedRunLog == nil)

        viewModel.selectedItemID = persisted.summary.items[1].id
        #expect(viewModel.selectedRunLog == nil)
    }

    @Test func switchingBatchSelectsFirstItemAndReloadsSourceAndYaml() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let store = BatchStore(rootDirectory: sandbox.root)
        let newer = try makePersistedBatch(
            store: store,
            id: "batch-new",
            createdAt: Date(timeIntervalSince1970: 20),
            sourceInputText: "source-new",
            items: [
                makeItem(title: "New A", nodeId: "2:1", yamlText: "yaml-new-a"),
                makeItem(title: "New B", nodeId: "2:2", yamlText: "yaml-new-b")
            ]
        )
        let older = try makePersistedBatch(
            store: store,
            id: "batch-old",
            createdAt: Date(timeIntervalSince1970: 10),
            sourceInputText: "source-old",
            items: [
                makeItem(title: "Old A", nodeId: "1:1", yamlText: "yaml-old-a")
            ]
        )

        let viewModel = ViewerViewModel(batchStore: store)
        viewModel.reload()

        #expect(viewModel.selectedBatch?.summary.id == newer.summary.id)
        #expect(viewModel.selectedItem?.id == newer.summary.items[0].id)

        viewModel.selectedBatchID = older.summary.id

        #expect(viewModel.selectedBatch?.summary.id == older.summary.id)
        #expect(viewModel.selectedItem?.id == older.summary.items[0].id)
        #expect(viewModel.selectedYAMLText == "yaml-old-a")
        #expect(viewModel.selectedSourceInputText == "source-old")
    }

    @Test func selectingItemWithoutYamlClearsYamlText() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let store = BatchStore(rootDirectory: sandbox.root)
        let persisted = try makePersistedBatch(
            store: store,
            id: "batch-1",
            createdAt: Date(timeIntervalSince1970: 10),
            sourceInputText: "source-1",
            items: [
                makeItem(title: "Item A", nodeId: "1:1", yamlText: "yaml-a"),
                makeItem(title: "Item B", nodeId: "1:2", yamlText: nil)
            ]
        )

        let viewModel = ViewerViewModel(batchStore: store)
        viewModel.reload()

        viewModel.selectedItemID = persisted.summary.items[1].id

        #expect(viewModel.selectedItem?.title == "Item B")
        #expect(viewModel.selectedYAMLText == nil)
    }

    @Test func reloadReadsLatestBatchAfterIncrementalUpdate() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let store = BatchStore(rootDirectory: sandbox.root)
        let initial = try makePersistedBatch(
            store: store,
            id: "batch-1",
            createdAt: Date(timeIntervalSince1970: 10),
            sourceInputText: "source-1",
            items: [
                makeItem(title: "Item A", nodeId: "1:1", yamlText: "yaml-a")
            ]
        )

        let newItem = makeItem(title: "Item B", nodeId: "1:2", yamlText: "yaml-b")
        _ = try store.updateBatch(
            id: initial.summary.id,
            sourceInputText: "source-2",
            agent: initial.summary.agent,
            promptSnapshot: initial.summary.promptSnapshot,
            outputDirectory: URL(fileURLWithPath: initial.summary.outputDirectory, isDirectory: true),
            mode: initial.summary.mode,
            parallelism: initial.summary.parallelism,
            callStrategy: .singlePerLink,
            items: initial.summary.items + [newItem]
        )

        let rescanned = try #require(try store.loadBatch(id: initial.summary.id))
        let newItemDirectory = try #require(rescanned.itemDirectories.last)
        let yamlURL = newItemDirectory.appendingPathComponent("generated.yaml")
        try "yaml-b".write(to: yamlURL, atomically: true, encoding: .utf8)

        var updatedItems = rescanned.summary.items
        updatedItems[1].generatedYAMLPath = yamlURL.path
        _ = try store.updateBatch(
            id: rescanned.summary.id,
            sourceInputText: "source-2",
            agent: rescanned.summary.agent,
            promptSnapshot: rescanned.summary.promptSnapshot,
            outputDirectory: URL(fileURLWithPath: rescanned.summary.outputDirectory, isDirectory: true),
            mode: rescanned.summary.mode,
            parallelism: rescanned.summary.parallelism,
            callStrategy: .singlePerLink,
            items: updatedItems
        )

        let viewModel = ViewerViewModel(batchStore: store)
        viewModel.reload()
        viewModel.selectedItemID = updatedItems[1].id

        #expect(viewModel.selectedBatch?.summary.items.count == 2)
        #expect(viewModel.selectedYAMLText == "yaml-b")
        #expect(viewModel.selectedSourceInputText == "source-2")
    }

    @Test func renameSelectedItemPersistsToBatchStorage() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let store = BatchStore(rootDirectory: sandbox.root)
        let persisted = try makePersistedBatch(
            store: store,
            id: "batch-1",
            createdAt: Date(timeIntervalSince1970: 10),
            sourceInputText: "source-1",
            items: [
                makeItem(title: "Item A", nodeId: "1:1", yamlText: "yaml-a")
            ]
        )

        let viewModel = ViewerViewModel(batchStore: store)
        viewModel.reload()
        viewModel.selectedItemID = persisted.summary.items[0].id
        viewModel.beginRenamingSelectedItem()
        viewModel.itemRename.title = "Renamed A"
        viewModel.commitRename()

        #expect(viewModel.selectedItem?.title == "Renamed A")

        let reloaded = try #require(try store.loadBatch(id: "batch-1"))
        #expect(reloaded.summary.items[0].title == "Renamed A")
    }

    @Test func renameSelectedBatchPersistsToBatchStorageAndKeepsSelection() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let store = BatchStore(rootDirectory: sandbox.root)
        _ = try makePersistedBatch(
            store: store,
            id: "batch-1",
            createdAt: Date(timeIntervalSince1970: 10),
            sourceInputText: "source-1",
            items: [
                makeItem(title: "Item A", nodeId: "1:1", yamlText: "yaml-a")
            ]
        )

        let viewModel = ViewerViewModel(batchStore: store)
        viewModel.reload()
        #expect(viewModel.selectedYAMLText == "yaml-a")
        viewModel.beginRenamingSelectedBatch()
        viewModel.batchRename.title = "batch-renamed"
        viewModel.commitBatchRename()

        #expect(viewModel.selectedBatchID == "batch-renamed")
        #expect(viewModel.selectedBatch?.summary.id == "batch-renamed")
        #expect(viewModel.selectedYAMLText == "yaml-a")

        #expect(try store.loadBatch(id: "batch-1") == nil)
        let reloaded = try #require(try store.loadBatch(id: "batch-renamed"))
        #expect(reloaded.summary.id == "batch-renamed")
    }

    @Test func renameSelectedBatchNotifiesRenameCallbackWithOldAndNewBatchContext() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let store = BatchStore(rootDirectory: sandbox.root)
        _ = try makePersistedBatch(
            store: store,
            id: "batch-1",
            createdAt: Date(timeIntervalSince1970: 10),
            sourceInputText: "source-1",
            items: [
                makeItem(title: "Item A", nodeId: "1:1", yamlText: "yaml-a")
            ]
        )

        var callbackOldID: String?
        var callbackOldDirectoryPath: String?
        var callbackRenamedID: String?
        var callbackRenamedDirectoryPath: String?
        let viewModel = ViewerViewModel(
            batchStore: store,
            batchRenamed: { oldID, oldDirectory, renamed in
                callbackOldID = oldID
                callbackOldDirectoryPath = oldDirectory.standardizedFileURL.path
                callbackRenamedID = renamed.summary.id
                callbackRenamedDirectoryPath = renamed.batchDirectory.standardizedFileURL.path
            }
        )
        viewModel.reload()
        let selectedBeforeRename = try #require(viewModel.selectedBatch)

        viewModel.beginRenamingSelectedBatch()
        viewModel.batchRename.title = "batch-renamed"
        viewModel.commitBatchRename()

        #expect(callbackOldID == "batch-1")
        #expect(callbackOldDirectoryPath == selectedBeforeRename.batchDirectory.standardizedFileURL.path)
        #expect(callbackRenamedID == "batch-renamed")
        #expect(callbackRenamedDirectoryPath == sandbox.root.appendingPathComponent("batch-renamed", isDirectory: true).standardizedFileURL.path)
    }

    @Test func continueEditingSelectedBatchCallsHandlerWithCurrentBatch() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let store = BatchStore(rootDirectory: sandbox.root)
        let persisted = try makePersistedBatch(
            store: store,
            id: "batch-1",
            createdAt: Date(timeIntervalSince1970: 10),
            sourceInputText: "source-1",
            items: [
                makeItem(title: "Item A", nodeId: "1:1", yamlText: "yaml-a")
            ]
        )

        var receivedBatchID: String?
        let viewModel = ViewerViewModel(batchStore: store) { batch in
            receivedBatchID = batch.summary.id
        }
        viewModel.reload()

        viewModel.continueEditingSelectedBatch()

        #expect(receivedBatchID == persisted.summary.id)
    }

    @Test func beginRenamingBatchUsesProvidedBatchID() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let store = BatchStore(rootDirectory: sandbox.root)
        _ = try makePersistedBatch(
            store: store,
            id: "batch-1",
            createdAt: Date(timeIntervalSince1970: 10),
            sourceInputText: "source-1",
            items: [
                makeItem(title: "Item A", nodeId: "1:1", yamlText: "yaml-a")
            ]
        )
        _ = try makePersistedBatch(
            store: store,
            id: "batch-2",
            createdAt: Date(timeIntervalSince1970: 20),
            sourceInputText: "source-2",
            items: [
                makeItem(title: "Item B", nodeId: "2:1", yamlText: "yaml-b")
            ]
        )

        let viewModel = ViewerViewModel(batchStore: store)
        viewModel.reload()
        viewModel.selectedBatchID = "batch-1"

        viewModel.beginRenamingBatch("batch-2")

        #expect(viewModel.batchRename.identifier == "batch-2")
        #expect(viewModel.batchRename.title == "batch-2")
        #expect(viewModel.batchRename.originalTitle == "batch-2")
    }

    @Test func beginRenamingItemUsesProvidedItemID() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let store = BatchStore(rootDirectory: sandbox.root)
        let persisted = try makePersistedBatch(
            store: store,
            id: "batch-1",
            createdAt: Date(timeIntervalSince1970: 10),
            sourceInputText: "source-1",
            items: [
                makeItem(title: "Item A", nodeId: "1:1", yamlText: "yaml-a"),
                makeItem(title: "Item B", nodeId: "1:2", yamlText: "yaml-b")
            ]
        )

        let viewModel = ViewerViewModel(batchStore: store)
        viewModel.reload()
        viewModel.selectedItemID = persisted.summary.items[0].id

        viewModel.beginRenamingItem(persisted.summary.items[1].id)

        #expect(viewModel.itemRename.identifier == persisted.summary.items[1].id)
        #expect(viewModel.itemRename.title == "Item B")
        #expect(viewModel.itemRename.originalTitle == "Item B")
    }

    @Test func continueEditingBatchUsesProvidedBatchID() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let store = BatchStore(rootDirectory: sandbox.root)
        _ = try makePersistedBatch(
            store: store,
            id: "batch-1",
            createdAt: Date(timeIntervalSince1970: 10),
            sourceInputText: "source-1",
            items: [
                makeItem(title: "Item A", nodeId: "1:1", yamlText: "yaml-a")
            ]
        )
        _ = try makePersistedBatch(
            store: store,
            id: "batch-2",
            createdAt: Date(timeIntervalSince1970: 20),
            sourceInputText: "source-2",
            items: [
                makeItem(title: "Item B", nodeId: "2:1", yamlText: "yaml-b")
            ]
        )

        var receivedBatchID: String?
        let viewModel = ViewerViewModel(batchStore: store) { batch in
            receivedBatchID = batch.summary.id
        }
        viewModel.reload()
        viewModel.selectedBatchID = "batch-1"

        viewModel.continueEditingBatch("batch-2")

        #expect(receivedBatchID == "batch-2")
    }

    @Test func selectedBatchExportsDirectoryUsesFixedBatchSubdirectory() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let store = BatchStore(rootDirectory: sandbox.root)
        _ = try makePersistedBatch(
            store: store,
            id: "batch-1",
            createdAt: Date(timeIntervalSince1970: 10),
            sourceInputText: "source-1",
            items: [
                makeItem(title: "Item A", nodeId: "1:1", yamlText: "yaml-a")
            ]
        )

        let viewModel = ViewerViewModel(batchStore: store)
        viewModel.reload()

        let exportsDirectory = try #require(viewModel.selectedBatchExportsDirectory)
        let expectedDirectory = sandbox.root.appendingPathComponent("batch-1", isDirectory: true).appendingPathComponent("exports", isDirectory: true)
        #expect(exportsDirectory.standardizedFileURL.path == expectedDirectory.standardizedFileURL.path)
    }

    @Test func exportMessageIncludesMissingAssetCount() {
        let archiveURL = URL(fileURLWithPath: "/tmp/batch-1.zip")
        let result = BatchExportResult(
            archiveURL: archiveURL,
            missingPreviewPaths: [],
            missingResourcePaths: ["/tmp/a.png"]
        )

        let message = ViewerViewModel.makeExportMessage(for: result)

        #expect(message.contains("已导出到 \(archiveURL.path)"))
        #expect(message.contains("1 个图片资源缺失"))
    }

    private func makePersistedBatch(
        store: BatchStore,
        id: String,
        createdAt: Date,
        sourceInputText: String,
        items: [FigmaLinkItem],
        runLogsByItemID: [UUID: GenerationRunLog]? = nil
    ) throws -> PersistedBatch {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let batch = GenerationBatch(
            id: id,
            createdAt: createdAt,
            agent: .codex,
            promptSnapshot: "prompt",
            sourceInputText: sourceInputText,
            outputDirectory: store.rootDirectory.path,
            mode: .sequential,
            parallelism: 2,
            callStrategy: .singlePerLink,
            items: items,
            runLogsByItemID: runLogsByItemID ?? Dictionary(uniqueKeysWithValues: items.enumerated().map { index, item in
                (item.id, GenerationRunLog(
                    id: "run-\(index + 1)",
                    isShared: false,
                    provider: .codex,
                    status: .finished,
                    stdout: "stdout-\(index + 1)",
                    stderr: ""
                ))
            })
        )
        var persisted = try store.createBatch(batch)
        var updatedItems = persisted.summary.items

        for (index, itemDirectory) in persisted.itemDirectories.enumerated() {
            guard let yamlText = items[index].generatedYAMLPath else {
                continue
            }
            let yamlURL = itemDirectory.appendingPathComponent("generated.yaml")
            try yamlText.write(to: yamlURL, atomically: true, encoding: .utf8)
            updatedItems[index].generatedYAMLPath = yamlURL.path

            let metaURL = itemDirectory.appendingPathComponent("meta.json")
            try encoder.encode(updatedItems[index]).write(to: metaURL)
        }

        let updatedBatch = GenerationBatch(
            id: persisted.summary.id,
            createdAt: persisted.summary.createdAt,
            agent: persisted.summary.agent,
            promptSnapshot: persisted.summary.promptSnapshot,
            sourceInputText: persisted.summary.sourceInputText,
            outputDirectory: persisted.summary.outputDirectory,
            mode: persisted.summary.mode,
            parallelism: persisted.summary.parallelism,
            callStrategy: .singlePerLink,
            items: updatedItems,
            runLogsByItemID: persisted.summary.runLogsByItemID
        )
        let batchURL = persisted.batchDirectory.appendingPathComponent("batch.json")
        try encoder.encode(updatedBatch).write(to: batchURL)

        persisted = try #require(store.scanBatches().first(where: { $0.summary.id == id }))
        return persisted
    }

    private func makeItem(title: String, nodeId: String, yamlText: String?) -> FigmaLinkItem {
        let nodeIDForURL = nodeId.replacingOccurrences(of: ":", with: "-")
        var item = FigmaLinkItem(
            rawInputLine: title,
            title: title,
            url: "https://www.figma.com/design/FILE123/App?node-id=\(nodeIDForURL)",
            fileKey: "FILE123",
            nodeId: nodeId
        )
        item.generatedYAMLPath = yamlText
        return item
    }
}
