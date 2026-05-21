import Foundation
import Testing
@testable import FigBridgeCore
@testable import FigBridgeApp

@MainActor
struct GenerateViewModelTests {
    @Test func addInputPreloadsResourcesForAllNewItems() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let transport = MockFigmaTransport(responses: [
            MockHTTPResponse(
                path: "/v1/files/FILE1/nodes",
                query: ["ids": "1:2"],
                statusCode: 200,
                body: """
                {
                  "nodes": {
                    "1:2": {
                      "document": {
                        "id": "1:2",
                        "name": "Node 1",
                        "fills": [{ "type": "IMAGE", "imageRef": "img-ref-1" }],
                        "children": []
                      }
                    }
                  }
                }
                """
            ),
            MockHTTPResponse(
                path: "/v1/images/FILE1",
                query: ["ids": "1:2", "format": "png", "scale": "2"],
                statusCode: 200,
                body: #"{"images":{"1:2":"https://cdn.figma.test/preview-1.png"}}"#
            ),
            MockHTTPResponse(
                path: "/v1/files/FILE1/images",
                query: [:],
                statusCode: 200,
                body: #"{"meta":{"images":{"img-ref-1":"https://cdn.figma.test/resource-1.png"}}}"#
            ),
            MockHTTPResponse(
                path: "/v1/files/FILE2/nodes",
                query: ["ids": "3:4"],
                statusCode: 200,
                body: """
                {
                  "nodes": {
                    "3:4": {
                      "document": {
                        "id": "3:4",
                        "name": "Node 2",
                        "fills": [{ "type": "IMAGE", "imageRef": "img-ref-2" }],
                        "children": []
                      }
                    }
                  }
                }
                """
            ),
            MockHTTPResponse(
                path: "/v1/images/FILE2",
                query: ["ids": "3:4", "format": "png", "scale": "2"],
                statusCode: 200,
                body: #"{"images":{"3:4":"https://cdn.figma.test/preview-2.png"}}"#
            ),
            MockHTTPResponse(
                path: "/v1/files/FILE2/images",
                query: [:],
                statusCode: 200,
                body: #"{"meta":{"images":{"img-ref-2":"https://cdn.figma.test/resource-2.png"}}}"#
            ),
            MockHTTPResponse(url: "https://cdn.figma.test/preview-1.png", statusCode: 200, data: Data("PNG1".utf8)),
            MockHTTPResponse(url: "https://cdn.figma.test/resource-1.png", statusCode: 200, data: Data("RES1".utf8)),
            MockHTTPResponse(url: "https://cdn.figma.test/preview-2.png", statusCode: 200, data: Data("PNG2".utf8)),
            MockHTTPResponse(url: "https://cdn.figma.test/resource-2.png", statusCode: 200, data: Data("RES2".utf8)),
        ])
        let harness = try GenerateViewModelHarness(
            rootDirectory: sandbox.root,
            figmaTransport: transport,
            figmaToken: "token"
        )

        harness.viewModel.inputText = """
        首页: @https://www.figma.com/design/FILE1/App?node-id=1-2
        列表: @https://www.figma.com/design/FILE2/App?node-id=3-4
        """
        harness.viewModel.addInput()

        let loaded = await waitUntil {
            harness.viewModel.items.count == 2
            && harness.viewModel.items.allSatisfy { $0.previewStatus == .success && $0.resourceStatus == .success }
        }
        #expect(loaded)

        let requests = await transport.recordedRequests()
        #expect(requests.contains { $0.path == "/v1/files/FILE1/nodes" })
        #expect(requests.contains { $0.path == "/v1/files/FILE2/nodes" })
    }

    @Test func reloadResourcesRetriesOnlyFailedItem() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let transport = FlakyFileImagesTransport()
        let harness = try GenerateViewModelHarness(
            rootDirectory: sandbox.root,
            figmaTransport: transport,
            figmaToken: "token"
        )

        harness.viewModel.inputText = "首页: @https://www.figma.com/design/FILE1/App?node-id=1-2"
        harness.viewModel.addInput()

        let failed = await waitUntil {
            harness.viewModel.items.first?.resourceStatus == .failed
        }
        #expect(failed)
        let itemID = try #require(harness.viewModel.items.first?.id)

        harness.viewModel.reloadResources(for: itemID)

        let recovered = await waitUntil {
            harness.viewModel.items.first?.resourceStatus == .success
            && harness.viewModel.items.first?.previewStatus == .success
        }
        #expect(recovered)
        #expect(await transport.fileImagesCallCount() == 2)
    }

    @Test func preloadedResourcesAreArchivedIntoBatchDirectoryAfterGeneration() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let transport = MockFigmaTransport(responses: [
            MockHTTPResponse(
                path: "/v1/files/FILE1/nodes",
                query: ["ids": "1:2"],
                statusCode: 200,
                body: """
                {
                  "nodes": {
                    "1:2": {
                      "document": {
                        "id": "1:2",
                        "name": "Node 1",
                        "fills": [{ "type": "IMAGE", "imageRef": "img-ref-1" }],
                        "children": []
                      }
                    }
                  }
                }
                """
            ),
            MockHTTPResponse(
                path: "/v1/images/FILE1",
                query: ["ids": "1:2", "format": "png", "scale": "2"],
                statusCode: 200,
                body: #"{"images":{"1:2":"https://cdn.figma.test/preview-1.png"}}"#
            ),
            MockHTTPResponse(
                path: "/v1/files/FILE1/images",
                query: [:],
                statusCode: 200,
                body: #"{"meta":{"images":{"img-ref-1":"https://cdn.figma.test/resource-1.png"}}}"#
            ),
            MockHTTPResponse(url: "https://cdn.figma.test/preview-1.png", statusCode: 200, data: Data("PNG1".utf8)),
            MockHTTPResponse(url: "https://cdn.figma.test/resource-1.png", statusCode: 200, data: Data("RES1".utf8)),
        ])
        let harness = try GenerateViewModelHarness(
            rootDirectory: sandbox.root,
            figmaTransport: transport,
            figmaToken: "token"
        )

        harness.viewModel.inputText = "首页: @https://www.figma.com/design/FILE1/App?node-id=1-2"
        harness.viewModel.addInput()

        let loaded = await waitUntil {
            harness.viewModel.items.first?.previewStatus == .success
            && harness.viewModel.items.first?.resourceStatus == .success
        }
        #expect(loaded)

        await harness.viewModel.generate()

        let batchID = try #require(harness.viewModel.currentBatchID)
        let persisted = try #require(try harness.batchStore.loadBatch(id: batchID))
        let persistedItem = try #require(persisted.summary.items.first)
        let previewPath = try #require(persistedItem.previewImagePath)
        let resourcePath = try #require(persistedItem.resourceItems.first?.localPath)

        #expect(previewPath.hasPrefix(persisted.batchDirectory.path))
        #expect(resourcePath.hasPrefix(persisted.batchDirectory.path))
        #expect(!previewPath.contains("__workspace__"))
        #expect(!resourcePath.contains("__workspace__"))
        #expect(FileManager.default.fileExists(atPath: previewPath))
        #expect(FileManager.default.fileExists(atPath: resourcePath))
    }

    @Test func multipleGenerationsReuseSameBatchUntilReset() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let harness = try GenerateViewModelHarness(rootDirectory: sandbox.root)
        let first = FigmaLinkItem(rawInputLine: "one", title: "One", url: "https://www.figma.com/design/FILE1/A?node-id=1-2", fileKey: "FILE1", nodeId: "1:2")
        let second = FigmaLinkItem(rawInputLine: "two", title: "Two", url: "https://www.figma.com/design/FILE2/B?node-id=3-4", fileKey: "FILE2", nodeId: "3:4")

        harness.viewModel.items = [first]
        await harness.viewModel.generate()
        let initialBatchID = try #require(harness.viewModel.currentBatchID)

        harness.viewModel.items.append(second)
        await harness.viewModel.generate()

        #expect(harness.viewModel.currentBatchID == initialBatchID)
        let runner = try #require(harness.recordedRunner)
        #expect(await runner.recordedCalls() == ["FILE1|1:2", "FILE2|3:4"])
        #expect(harness.viewModel.processedItems.count == 2)

        harness.viewModel.resetWorkspace()
        #expect(harness.viewModel.currentBatchID == nil)
        #expect(harness.viewModel.currentBatchDirectory == nil)
    }

    @Test func pendingAndProcessedItemsAreDerivedFromYamlPresence() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let harness = try GenerateViewModelHarness(rootDirectory: sandbox.root)
        var processed = FigmaLinkItem(rawInputLine: "done", title: "Done", url: "https://www.figma.com/design/FILE1/A?node-id=1-2", fileKey: "FILE1", nodeId: "1:2")
        processed.generatedYAMLPath = "/tmp/generated.yaml"
        let pending = FigmaLinkItem(rawInputLine: "todo", title: "Todo", url: "https://www.figma.com/design/FILE2/B?node-id=3-4", fileKey: "FILE2", nodeId: "3:4")

        harness.viewModel.items = [processed, pending]

        #expect(harness.viewModel.processedItems.map(\.id) == [processed.id])
        #expect(harness.viewModel.pendingItems.map(\.id) == [pending.id])
        #expect(harness.viewModel.canGenerate)
    }

    @Test func deletingSelectedItemUpdatesSelectionAndGenerationAvailability() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let harness = try GenerateViewModelHarness(rootDirectory: sandbox.root)
        let first = FigmaLinkItem(rawInputLine: "one", title: "One", url: "https://www.figma.com/design/FILE1/A?node-id=1-2", fileKey: "FILE1", nodeId: "1:2")
        let second = FigmaLinkItem(rawInputLine: "two", title: "Two", url: "https://www.figma.com/design/FILE2/B?node-id=3-4", fileKey: "FILE2", nodeId: "3:4")

        harness.viewModel.items = [first, second]
        harness.viewModel.selectedItemID = first.id
        harness.viewModel.deleteItem(id: first.id)

        #expect(harness.viewModel.items.map(\.id) == [second.id])
        #expect(harness.viewModel.selectedItemID == second.id)

        harness.viewModel.deleteItem(id: second.id)

        #expect(harness.viewModel.items.isEmpty)
        #expect(harness.viewModel.selectedItemID == nil)
        #expect(!harness.viewModel.canGenerate)
    }

    @Test func beginRenamingItemUsesProvidedItemID() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let harness = try GenerateViewModelHarness(rootDirectory: sandbox.root)
        let first = FigmaLinkItem(rawInputLine: "one", title: "One", url: "https://www.figma.com/design/FILE1/A?node-id=1-2", fileKey: "FILE1", nodeId: "1:2")
        let second = FigmaLinkItem(rawInputLine: "two", title: "Two", url: "https://www.figma.com/design/FILE2/B?node-id=3-4", fileKey: "FILE2", nodeId: "3:4")

        harness.viewModel.items = [first, second]
        harness.viewModel.selectedItemID = first.id

        harness.viewModel.beginRenamingItem(second.id)

        #expect(harness.viewModel.itemRename.identifier == second.id)
        #expect(harness.viewModel.itemRename.title == "Two")
        #expect(harness.viewModel.itemRename.originalTitle == "Two")
    }

    @Test func addInputShowsHintForEmptyTextAndClearsTextAfterSuccess() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let harness = try GenerateViewModelHarness(rootDirectory: sandbox.root)

        harness.viewModel.inputText = "   \n  "
        harness.viewModel.addInput()

        #expect(harness.viewModel.items.isEmpty)
        #expect(harness.viewModel.validationMessage == "请输入要添加的信息")

        harness.viewModel.inputText = "首页: @https://www.figma.com/design/FILE1/A?node-id=1-2"
        harness.viewModel.addInput()

        #expect(harness.viewModel.items.count == 1)
        #expect(harness.viewModel.inputText.isEmpty)
    }

    @Test func missingTokenShowsTokenNotConfiguredStatusForSelectedItem() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let harness = try GenerateViewModelHarness(rootDirectory: sandbox.root, figmaToken: "")
        let item = FigmaLinkItem(
            rawInputLine: "首页",
            title: "首页",
            url: "https://www.figma.com/design/FILE1/A?node-id=1-2",
            fileKey: "FILE1",
            nodeId: "1:2"
        )
        harness.viewModel.items = [item]
        harness.viewModel.selectedItemID = item.id

        #expect(harness.viewModel.selectedItemResourceStatusText == "token 未设置")
        #expect(harness.viewModel.selectedItemGenerationStatusText == "token 未设置")
        #expect(harness.viewModel.shouldHighlightSelectedItemResourceStatus)
        #expect(harness.viewModel.shouldHighlightSelectedItemGenerationStatus)
    }

    @Test func itemAllowsManualRefreshWhenTokenIsMissing() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let harness = try GenerateViewModelHarness(rootDirectory: sandbox.root, figmaToken: "")
        let item = FigmaLinkItem(
            rawInputLine: "首页",
            title: "首页",
            url: "https://www.figma.com/design/FILE1/A?node-id=1-2",
            fileKey: "FILE1",
            nodeId: "1:2"
        )

        #expect(harness.viewModel.canRefreshResources(for: item))
    }

    @Test func partialResourceDownloadFailureEnablesRefreshAndShowsFailedStatus() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let harness = try GenerateViewModelHarness(
            rootDirectory: sandbox.root,
            figmaTransport: PartiallyFailingResourceTransport(),
            figmaToken: "token"
        )

        harness.viewModel.inputText = "首页: @https://www.figma.com/design/FILE123/App?node-id=1-2"
        harness.viewModel.addInput()

        let failed = await waitUntil {
            guard let item = harness.viewModel.items.first else {
                return false
            }
            return item.previewStatus == .success && item.resourceStatus == .failed
        }
        #expect(failed)

        let item = try #require(harness.viewModel.items.first)
        harness.viewModel.selectedItemID = item.id

        #expect(harness.viewModel.selectedItemResourceStatusText == "failed")
        #expect(harness.viewModel.canRefreshResources(for: item))
    }

    @Test func renameSelectedItemPersistsToCurrentBatchAndLoadsYamlText() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let harness = try GenerateViewModelHarness(rootDirectory: sandbox.root)
        let item = FigmaLinkItem(rawInputLine: "one", title: "Old", url: "https://www.figma.com/design/FILE1/A?node-id=1-2", fileKey: "FILE1", nodeId: "1:2")

        harness.viewModel.items = [item]
        await harness.viewModel.generate()
        let generatedItem = try #require(harness.viewModel.items.first)
        harness.viewModel.selectedItemID = generatedItem.id
        await harness.viewModel.loadSelectedItemPreviewIfNeeded()

        #expect(harness.viewModel.selectedYAMLText?.contains(#""nodeId""#) == true)
        #expect(harness.viewModel.selectedYAMLText?.contains(#""1:2""#) == true)

        harness.viewModel.beginRenamingSelectedItem()
        harness.viewModel.itemRename.title = "Renamed"
        harness.viewModel.commitRename()

        #expect(harness.viewModel.items.first?.title == "Renamed")

        let currentBatchID = try #require(harness.viewModel.currentBatchID)
        let persisted = try #require(try harness.batchStore.loadBatch(id: currentBatchID))
        #expect(persisted.summary.items.first?.title == "Renamed")
    }

    @Test func bootstrapRestoresSavedWorkspaceDraft() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let harness = try GenerateViewModelHarness(rootDirectory: sandbox.root)
        let item = FigmaLinkItem(
            rawInputLine: "首页",
            title: "首页",
            url: "https://www.figma.com/design/FILE1/A?node-id=1-2",
            fileKey: "FILE1",
            nodeId: "1:2"
        )
        let draft = GenerateWorkspaceDraft(
            selectedAgentID: AgentProvider.codex.id,
            promptTemplate: "draft prompt",
            outputDirectoryPath: sandbox.root.appendingPathComponent("exports", isDirectory: true).path,
            mode: .parallel,
            parallelism: 4,
            callStrategy: .singleForBatch,
            inputText: "draft input",
            items: [item],
            selectedItemID: item.id,
            currentBatchID: "batch-draft",
            currentBatchDirectory: sandbox.root.appendingPathComponent("batch-draft", isDirectory: true).path
        )
        try harness.draftStore.save(draft)

        let restoredHarness = try GenerateViewModelHarness(rootDirectory: sandbox.root)
        await restoredHarness.viewModel.bootstrap()

        #expect(restoredHarness.viewModel.selectedAgentID == AgentProvider.codex.id)
        #expect(restoredHarness.viewModel.promptTemplate == "draft prompt")
        #expect(restoredHarness.viewModel.outputDirectoryPath == sandbox.root.appendingPathComponent("batch-draft", isDirectory: true).appendingPathComponent("exports", isDirectory: true).path)
        #expect(restoredHarness.viewModel.mode == .parallel)
        #expect(restoredHarness.viewModel.parallelism == 4)
        #expect(restoredHarness.viewModel.callStrategy == .singleForBatch)
        #expect(restoredHarness.viewModel.inputText == "draft input")
        #expect(restoredHarness.viewModel.items == [item])
        #expect(restoredHarness.viewModel.selectedItemID == item.id)
        #expect(restoredHarness.viewModel.currentBatchID == "batch-draft")
        #expect(restoredHarness.viewModel.currentBatchDirectory == draft.currentBatchDirectory)
    }

    @Test func newBatchClearsWorkspaceAndPersistsEmptyDraft() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let harness = try GenerateViewModelHarness(rootDirectory: sandbox.root)
        harness.viewModel.inputText = "pending input"
        harness.viewModel.items = [
            FigmaLinkItem(rawInputLine: "one", title: "One", url: "https://www.figma.com/design/FILE1/A?node-id=1-2", fileKey: "FILE1", nodeId: "1:2")
        ]
        harness.viewModel.currentBatchID = "batch-1"
        harness.viewModel.currentBatchDirectory = sandbox.root.appendingPathComponent("batch-1", isDirectory: true).path

        harness.viewModel.startNewBatch()

        #expect(harness.viewModel.inputText.isEmpty)
        #expect(harness.viewModel.items.isEmpty)
        #expect(harness.viewModel.selectedItemID == nil)
        #expect(harness.viewModel.currentBatchID == nil)
        #expect(harness.viewModel.currentBatchDirectory == nil)
        #expect(harness.viewModel.outputDirectoryPath == "当前批次/exports")

        let draft = try #require(harness.draftStore.load())
        #expect(draft.inputText.isEmpty)
        #expect(draft.items.isEmpty)
        #expect(draft.currentBatchID == nil)
        #expect(draft.currentBatchDirectory == nil)
        #expect(draft.outputDirectoryPath == "当前批次/exports")
    }

    @Test func loadingExistingBatchIntoWorkspaceRestoresEditableContext() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let harness = try GenerateViewModelHarness(rootDirectory: sandbox.root)
        let item = FigmaLinkItem(
            rawInputLine: "首页",
            title: "首页",
            url: "https://www.figma.com/design/FILE1/A?node-id=1-2",
            fileKey: "FILE1",
            nodeId: "1:2"
        )
        let persisted = try harness.batchStore.createBatch(GenerationBatch(
            id: "batch-1",
            createdAt: Date(timeIntervalSince1970: 0),
            agent: .codex,
            promptSnapshot: "batch prompt",
            sourceInputText: "batch input",
            outputDirectory: sandbox.root.path,
            mode: .parallel,
            parallelism: 5,
            callStrategy: .singlePerLink,
            items: [item]
        ))

        harness.viewModel.loadBatchIntoWorkspace(persisted)

        #expect(harness.viewModel.currentBatchID == "batch-1")
        #expect(harness.viewModel.currentBatchDirectory == persisted.batchDirectory.path)
        #expect(harness.viewModel.outputDirectoryPath == persisted.batchDirectory.appendingPathComponent("exports", isDirectory: true).path)
        #expect(harness.viewModel.promptTemplate == "batch prompt")
        #expect(harness.viewModel.inputText == "batch input")
        #expect(harness.viewModel.mode == .parallel)
        #expect(harness.viewModel.parallelism == 5)
        #expect(harness.viewModel.callStrategy == .singlePerLink)
        #expect(harness.viewModel.items == [item])

        let draft = try #require(harness.draftStore.load())
        #expect(draft.currentBatchID == "batch-1")
        #expect(draft.parallelism == 5)
        #expect(draft.callStrategy == .singlePerLink)
    }

    @Test func handleBatchRenamedSyncsCurrentEditingBatchByIDAndPersistsDraft() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let harness = try GenerateViewModelHarness(rootDirectory: sandbox.root)
        var item = FigmaLinkItem(
            rawInputLine: "首页",
            title: "首页",
            url: "https://www.figma.com/design/FILE1/A?node-id=1-2",
            fileKey: "FILE1",
            nodeId: "1:2"
        )
        let oldBatchDirectory = sandbox.root.appendingPathComponent("batch-1", isDirectory: true)
        let oldItemsDirectory = oldBatchDirectory.appendingPathComponent("items", isDirectory: true)
        let oldItemDirectory = oldItemsDirectory.appendingPathComponent("\(item.id.uuidString.lowercased())-\(item.nodeId.replacingOccurrences(of: ":", with: "-"))", isDirectory: true)
        let oldYamlPath = oldItemDirectory.appendingPathComponent("generated.yaml").path
        item.generatedYAMLPath = oldYamlPath
        let persisted = try harness.batchStore.createBatch(GenerationBatch(
            id: "batch-1",
            createdAt: Date(timeIntervalSince1970: 0),
            agent: .codex,
            promptSnapshot: "batch prompt",
            sourceInputText: "batch input",
            outputDirectory: sandbox.root.path,
            mode: .sequential,
            parallelism: 2,
            callStrategy: .singlePerLink,
            items: [item]
        ))
        try FileManager.default.createDirectory(at: oldItemDirectory, withIntermediateDirectories: true)
        try "name: 1:2".write(toFile: oldYamlPath, atomically: true, encoding: .utf8)
        harness.viewModel.loadBatchIntoWorkspace(persisted)

        let renamed = try harness.batchStore.renameBatch(id: "batch-1", to: "batch-renamed")
        harness.viewModel.handleBatchRenamed(
            oldID: "batch-1",
            oldDirectory: persisted.batchDirectory,
            renamed: renamed
        )

        #expect(harness.viewModel.currentBatchID == "batch-renamed")
        #expect(harness.viewModel.currentBatchDirectory == renamed.batchDirectory.path)
        #expect(harness.viewModel.outputDirectoryPath == renamed.batchDirectory.appendingPathComponent("exports", isDirectory: true).path)
        #expect(harness.viewModel.processedItems.count == 1)
        let renamedItem = try #require(harness.viewModel.items.first)
        let renamedYamlPath = try #require(renamedItem.generatedYAMLPath)
        #expect(!renamedYamlPath.contains("/batch-1/"))
        #expect(renamedYamlPath.contains("/batch-renamed/"))
        #expect(harness.viewModel.selectedYAMLText == "name: 1:2")
        let draft = try #require(harness.draftStore.load())
        #expect(draft.currentBatchID == "batch-renamed")
        #expect(draft.currentBatchDirectory == renamed.batchDirectory.path)
    }

    @Test func handleBatchRenamedDoesNotSyncWhenCurrentBatchDiffers() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let harness = try GenerateViewModelHarness(rootDirectory: sandbox.root)
        let item = FigmaLinkItem(
            rawInputLine: "首页",
            title: "首页",
            url: "https://www.figma.com/design/FILE1/A?node-id=1-2",
            fileKey: "FILE1",
            nodeId: "1:2"
        )
        let target = try harness.batchStore.createBatch(GenerationBatch(
            id: "batch-target",
            createdAt: Date(timeIntervalSince1970: 0),
            agent: .codex,
            promptSnapshot: "target prompt",
            sourceInputText: "target input",
            outputDirectory: sandbox.root.path,
            mode: .sequential,
            parallelism: 2,
            callStrategy: .singlePerLink,
            items: [item]
        ))
        let other = try harness.batchStore.createBatch(GenerationBatch(
            id: "batch-other",
            createdAt: Date(timeIntervalSince1970: 1),
            agent: .codex,
            promptSnapshot: "other prompt",
            sourceInputText: "other input",
            outputDirectory: sandbox.root.path,
            mode: .parallel,
            parallelism: 3,
            callStrategy: .singleForBatch,
            items: [item]
        ))
        harness.viewModel.loadBatchIntoWorkspace(other)
        let previousOutputDirectoryPath = harness.viewModel.outputDirectoryPath

        let renamedTarget = try harness.batchStore.renameBatch(id: "batch-target", to: "batch-target-renamed")
        harness.viewModel.handleBatchRenamed(
            oldID: "batch-target",
            oldDirectory: target.batchDirectory,
            renamed: renamedTarget
        )

        #expect(harness.viewModel.currentBatchID == "batch-other")
        #expect(harness.viewModel.currentBatchDirectory == other.batchDirectory.path)
        #expect(harness.viewModel.outputDirectoryPath == previousOutputDirectoryPath)
    }

    @Test func selectingAgentImmediatelyPersistsToSettingsStore() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let harness = try GenerateViewModelHarness(rootDirectory: sandbox.root)

        harness.viewModel.selectedAgentID = AgentProvider.claude.id

        let settings = try harness.settingsStore.load()
        #expect(settings.selectedAgentID == AgentProvider.claude.id)
    }

    @Test func clearingAgentSelectionPersistsNilToSettingsStore() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let harness = try GenerateViewModelHarness(rootDirectory: sandbox.root)

        harness.viewModel.selectedAgentID = nil

        let settings = try harness.settingsStore.load()
        #expect(settings.selectedAgentID == nil)
    }

    @Test func bootstrapDoesNotOverridePersistedSelectedAgentWithDraftSelection() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let harness = try GenerateViewModelHarness(rootDirectory: sandbox.root)
        let draft = GenerateWorkspaceDraft(
            selectedAgentID: AgentProvider.claude.id,
            promptTemplate: "draft prompt",
            outputDirectoryPath: sandbox.root.path,
            mode: .sequential,
            parallelism: 2,
            callStrategy: .singlePerLink,
            inputText: "draft",
            items: [],
            selectedItemID: nil,
            currentBatchID: nil,
            currentBatchDirectory: nil
        )
        try harness.draftStore.save(draft)

        let restoredHarness = try GenerateViewModelHarness(rootDirectory: sandbox.root)
        await restoredHarness.viewModel.bootstrap()

        let settings = try restoredHarness.settingsStore.load()
        #expect(restoredHarness.viewModel.selectedAgentID == AgentProvider.claude.id)
        #expect(settings.selectedAgentID == AgentProvider.codex.id)
    }

    @Test func generateCapturesRealtimeConsoleLogForSelectedItem() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let harness = try GenerateViewModelHarness(rootDirectory: sandbox.root, runner: StreamingRecordingAgentRunner(mode: .single))
        let item = FigmaLinkItem(rawInputLine: "one", title: "One", url: "https://www.figma.com/design/FILE1/A?node-id=1-2", fileKey: "FILE1", nodeId: "1:2")
        harness.viewModel.items = [item]
        harness.viewModel.selectedItemID = item.id

        await harness.viewModel.generate()

        let log = try #require(harness.viewModel.selectedRunLog)
        #expect(log.isShared == false)
        #expect(log.combinedConsoleText.contains("stdout-line"))
        #expect(log.combinedConsoleText.contains("stderr-line"))
        #expect(log.exitCode == 0)
    }

    @Test func singleBatchStrategySharesRealtimeConsoleLogAcrossItems() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let harness = try GenerateViewModelHarness(rootDirectory: sandbox.root, runner: StreamingRecordingAgentRunner(mode: .batch))
        harness.viewModel.callStrategy = .singleForBatch
        let first = FigmaLinkItem(rawInputLine: "one", title: "One", url: "https://www.figma.com/design/FILE1/A?node-id=1-2", fileKey: "FILE1", nodeId: "1:2")
        let second = FigmaLinkItem(rawInputLine: "two", title: "Two", url: "https://www.figma.com/design/FILE2/B?node-id=3-4", fileKey: "FILE2", nodeId: "3:4")
        harness.viewModel.items = [first, second]

        harness.viewModel.selectedItemID = first.id
        await harness.viewModel.generate()
        let firstLog = try #require(harness.viewModel.selectedRunLog)

        harness.viewModel.selectedItemID = second.id
        let secondLog = try #require(harness.viewModel.selectedRunLog)

        #expect(firstLog.runID == secondLog.runID)
        #expect(firstLog.isShared)
        #expect(secondLog.isShared)
        #expect(secondLog.combinedConsoleText.contains("shared-batch-line"))
    }

    @Test func generatePersistsRunLogIntoBatchAndRestoresWhenLoadingBatch() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let harness = try GenerateViewModelHarness(rootDirectory: sandbox.root, runner: StreamingRecordingAgentRunner(mode: .single))
        let item = FigmaLinkItem(rawInputLine: "one", title: "One", url: "https://www.figma.com/design/FILE1/A?node-id=1-2", fileKey: "FILE1", nodeId: "1:2")
        harness.viewModel.items = [item]
        harness.viewModel.selectedItemID = item.id

        await harness.viewModel.generate()
        let batchID = try #require(harness.viewModel.currentBatchID)
        let persisted = try #require(try harness.batchStore.loadBatch(id: batchID))
        let persistedLog = try #require(persisted.summary.runLogsByItemID[item.id])
        #expect(persistedLog.combinedConsoleText.contains("stdout-line"))

        harness.viewModel.startNewBatch()
        harness.viewModel.loadBatchIntoWorkspace(persisted)
        harness.viewModel.selectedItemID = item.id
        let restoredLog = try #require(harness.viewModel.selectedRunLog)
        #expect(restoredLog.combinedConsoleText.contains("stdout-line"))
    }

    @Test func generateUsesFixedExportsDirectoryInsideBatch() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let harness = try GenerateViewModelHarness(rootDirectory: sandbox.root)
        let item = FigmaLinkItem(rawInputLine: "one", title: "One", url: "https://www.figma.com/design/FILE1/A?node-id=1-2", fileKey: "FILE1", nodeId: "1:2")
        harness.viewModel.items = [item]
        harness.viewModel.outputDirectoryPath = "/tmp/should-not-be-used"

        await harness.viewModel.generate()

        let batchID = try #require(harness.viewModel.currentBatchID)
        let batchDirectory = sandbox.root.appendingPathComponent(batchID, isDirectory: true)
        let exportsDirectory = batchDirectory.appendingPathComponent("exports", isDirectory: true)
        #expect(harness.viewModel.outputDirectoryPath == exportsDirectory.path)

        let persisted = try #require(try harness.batchStore.loadBatch(id: batchID))
        #expect(persisted.summary.outputDirectory == exportsDirectory.path)
        #expect(FileManager.default.fileExists(atPath: batchDirectory.path))
    }

    @Test func cancelledGenerationDoesNotShowCompletedMessage() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let harness = try GenerateViewModelHarness(rootDirectory: sandbox.root, runner: SlowIgnoringCancellationRunner())
        let item = FigmaLinkItem(rawInputLine: "one", title: "One", url: "https://www.figma.com/design/FILE1/A?node-id=1-2", fileKey: "FILE1", nodeId: "1:2")
        harness.viewModel.items = [item]

        let generationTask = Task {
            await harness.viewModel.generate()
        }
        let started = await waitUntil {
            harness.viewModel.isGenerating
        }
        #expect(started)

        harness.viewModel.cancelGeneration()
        await generationTask.value

        #expect(harness.viewModel.validationMessage == "生成已取消")
        #expect(harness.viewModel.validationMessage != "生成完成")
    }

    @Test func startNewBatchDuringGenerationKeepsWorkspaceCleared() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let harness = try GenerateViewModelHarness(rootDirectory: sandbox.root, runner: SlowIgnoringCancellationRunner())
        let item = FigmaLinkItem(rawInputLine: "one", title: "One", url: "https://www.figma.com/design/FILE1/A?node-id=1-2", fileKey: "FILE1", nodeId: "1:2")
        harness.viewModel.inputText = "one"
        harness.viewModel.items = [item]
        harness.viewModel.selectedItemID = item.id

        let generationTask = Task {
            await harness.viewModel.generate()
        }
        let started = await waitUntil {
            harness.viewModel.isGenerating
        }
        #expect(started)

        harness.viewModel.startNewBatch()
        await generationTask.value

        #expect(harness.viewModel.inputText.isEmpty)
        #expect(harness.viewModel.items.isEmpty)
        #expect(harness.viewModel.selectedItemID == nil)
        #expect(harness.viewModel.currentBatchID == nil)
        #expect(harness.viewModel.currentBatchDirectory == nil)
        #expect(harness.viewModel.outputDirectoryPath == "当前批次/exports")
    }

    @Test func syncPromptFromSettingsOverwritesWorkspacePrompt() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let harness = try GenerateViewModelHarness(rootDirectory: sandbox.root)
        harness.viewModel.promptTemplate = "workspace prompt"
        harness.settingsViewModel.settings.promptTemplate = "settings prompt"

        harness.viewModel.syncPromptFromSettings()

        #expect(harness.viewModel.promptTemplate == "settings prompt")
    }

    @Test func refreshingAgentsUsesLatestSettingsViewModelAgents() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let claudePath = sandbox.root.appendingPathComponent("claude")
        try makeExecutable(at: claudePath, body: "#!/bin/sh\nif [ \"$1\" = \"--version\" ]; then\n  echo \"claude 1.0.0\"\nfi\n")

        let harness = try GenerateViewModelHarness(
            rootDirectory: sandbox.root,
            agentShellClient: ShellClient(pathLookupDirectories: [sandbox.root], environment: ["PATH": "/usr/bin:/bin"])
        )
        var settings = try harness.settingsStore.load()
        settings.selectedAgentID = "missing-agent"
        try harness.settingsStore.save(settings)

        let task = Task {
            await harness.viewModel.refreshAgents()
        }
        let loadingStarted = await waitUntil {
            harness.viewModel.isRefreshingAgents
        }
        await task.value

        #expect(loadingStarted)
        #expect(harness.viewModel.isRefreshingAgents == false)
        #expect(harness.viewModel.availableAgents.map(\.provider).contains(.claude))
        #expect(harness.viewModel.selectedAgentID == nil)
    }
}

@MainActor
private struct GenerateViewModelHarness {
    let viewModel: GenerateViewModel
    let settingsViewModel: SettingsViewModel
    let runner: any AgentRunning
    let recordedRunner: RecordingAgentRunner?
    let batchStore: BatchStore
    let draftStore: GenerateWorkspaceDraftStore
    let settingsStore: SettingsStore

    init(
        rootDirectory: URL,
        figmaTransport: (any FigmaHTTPTransport)? = nil,
        figmaToken: String = "",
        runner: (any AgentRunning)? = nil,
        agentShellClient: ShellClient? = nil
    ) throws {
        let settingsStore = SettingsStore(fileURL: rootDirectory.appendingPathComponent("settings.json"))
        try settingsStore.save(AppSettings(
            selectedAgentID: AgentProvider.codex.id,
            promptTemplate: "prompt",
            outputDirectoryPath: rootDirectory.path,
            figmaToken: figmaToken,
            defaultExportFormat: .png,
            defaultGenerationMode: .sequential,
            parallelism: 2,
            defaultAgentCallStrategy: .singlePerLink
        ))
        let agentService = AgentService(shellClient: agentShellClient ?? ShellClient(environment: ["PATH": "/usr/bin:/bin"]))
        let figmaService: FigmaService
        if let figmaTransport {
            figmaService = FigmaService(baseDirectory: rootDirectory, transport: figmaTransport)
        } else {
            figmaService = FigmaService(baseDirectory: rootDirectory)
        }
        let settingsViewModel = SettingsViewModel(settingsStore: settingsStore, agentService: agentService, figmaService: figmaService)
        settingsViewModel.settings = try settingsStore.load()
        let batchStore = BatchStore(rootDirectory: rootDirectory)
        let draftStore = GenerateWorkspaceDraftStore(fileURL: rootDirectory.appendingPathComponent("generate-workspace-draft.json"))
        let resolvedRunner = runner ?? RecordingAgentRunner()
        let coordinator = GenerationCoordinator(batchStore: batchStore, agentRunner: resolvedRunner)
        let viewModel = GenerateViewModel(
            settingsViewModel: settingsViewModel,
            batchStore: batchStore,
            generationCoordinator: coordinator,
            figmaService: figmaService,
            draftStore: draftStore
        )

        self.viewModel = viewModel
        self.settingsViewModel = settingsViewModel
        self.runner = resolvedRunner
        self.recordedRunner = resolvedRunner as? RecordingAgentRunner
        self.batchStore = batchStore
        self.draftStore = draftStore
        self.settingsStore = settingsStore

        viewModel.availableAgents = [AgentDescriptor(provider: .codex, path: "/mock/codex", version: "1.0")]
        viewModel.selectedAgentID = AgentProvider.codex.id
        viewModel.promptTemplate = "prompt"
        viewModel.outputDirectoryPath = rootDirectory.path
        viewModel.mode = GenerationMode.sequential
        viewModel.parallelism = 2
        viewModel.callStrategy = .singlePerLink
    }
}

func waitUntil(
    timeoutNanoseconds: UInt64 = 2_000_000_000,
    intervalNanoseconds: UInt64 = 20_000_000,
    condition: @escaping @MainActor () -> Bool
) async -> Bool {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    while DispatchTime.now().uptimeNanoseconds < deadline {
        if await MainActor.run(body: condition) {
            return true
        }
        try? await Task.sleep(nanoseconds: intervalNanoseconds)
    }
    return await MainActor.run(body: condition)
}

private actor FlakyFileImagesTransport: FigmaHTTPTransport {
    private var fileImagesCalls = 0

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url else {
            throw URLError(.badURL)
        }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []
        let query = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value ?? "") })
        let path = url.path

        switch path {
        case "/v1/files/FILE1/nodes":
            return response(
                url: url,
                status: 200,
                body: """
                {
                  "nodes": {
                    "1:2": {
                      "document": {
                        "id": "1:2",
                        "name": "Node 1",
                        "fills": [{ "type": "IMAGE", "imageRef": "img-ref-1" }],
                        "children": []
                      }
                    }
                  }
                }
                """
            )
        case "/v1/images/FILE1":
            if query["ids"] == "1:2" {
                return response(url: url, status: 200, body: #"{"images":{"1:2":"https://cdn.figma.test/preview.png"}}"#)
            }
        case "/v1/files/FILE1/images":
            fileImagesCalls += 1
            if fileImagesCalls == 1 {
                return response(url: url, status: 500, body: #"{"err":"temporary"}"#)
            }
            return response(url: url, status: 200, body: #"{"meta":{"images":{"img-ref-1":"https://cdn.figma.test/resource.png"}}}"#)
        default:
            break
        }

        if url.absoluteString == "https://cdn.figma.test/preview.png" {
            return response(url: url, status: 200, data: Data("PNG".utf8))
        }
        if url.absoluteString == "https://cdn.figma.test/resource.png" {
            return response(url: url, status: 200, data: Data("RES".utf8))
        }
        throw URLError(.badServerResponse)
    }

    func fileImagesCallCount() -> Int {
        fileImagesCalls
    }

    private func response(url: URL, status: Int, body: String) -> (Data, HTTPURLResponse) {
        let data = Data(body.utf8)
        let http = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (data, http)
    }

    private func response(url: URL, status: Int, data: Data) -> (Data, HTTPURLResponse) {
        let http = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (data, http)
    }
}

private actor RecordingAgentRunner: AgentRunning {
    private var calls: [String] = []

    func run(
        provider: AgentProvider,
        prompt: String,
        item: FigmaLinkItem,
        eventHandler: (@Sendable (AgentRunEvent) async -> Void)? = nil
    ) async throws -> AgentRunResult {
        calls.append("\(item.fileKey)|\(item.nodeId)")
        if prompt.contains("Links to process:") {
            return AgentRunResult(
                output: """
                <<<FIGBRIDGE_DESIGN_IR_START fileKey=FILE1 nodeId=1:2>>>
                \(makeAgentDesignIRJSON(fileKey: "FILE1", nodeId: "1:2", screenName: "Node 1"))
                <<<FIGBRIDGE_DESIGN_IR_END>>>
                <<<FIGBRIDGE_DESIGN_IR_START fileKey=FILE2 nodeId=3:4>>>
                \(makeAgentDesignIRJSON(fileKey: "FILE2", nodeId: "3:4", screenName: "Node 2"))
                <<<FIGBRIDGE_DESIGN_IR_END>>>
                """,
                executablePath: "/mock/\(provider.rawValue)",
                arguments: [],
                exitCode: 0,
                stderr: ""
            )
        }
        return AgentRunResult(
            output: makeAgentDesignIRJSON(fileKey: item.fileKey, nodeId: item.nodeId, screenName: "Node \(item.nodeId)"),
            executablePath: "/mock/\(provider.rawValue)",
            arguments: [],
            exitCode: 0,
            stderr: ""
        )
    }

    func recordedCalls() -> [String] {
        calls
    }
}

private actor StreamingRecordingAgentRunner: AgentRunning {
    enum Mode {
        case single
        case batch
    }

    let mode: Mode

    init(mode: Mode) {
        self.mode = mode
    }

    func run(
        provider: AgentProvider,
        prompt: String,
        item: FigmaLinkItem,
        eventHandler: (@Sendable (AgentRunEvent) async -> Void)?
    ) async throws -> AgentRunResult {
        switch mode {
        case .single:
            if let eventHandler {
                await eventHandler(.started(executablePath: "/mock/\(provider.rawValue)", arguments: [], isSharedLog: false))
                await eventHandler(.stdout("stdout-line\n"))
                await eventHandler(.stderr("stderr-line\n"))
                await eventHandler(.finished(exitCode: 0))
            }
            return AgentRunResult(
                output: makeAgentDesignIRJSON(fileKey: item.fileKey, nodeId: item.nodeId, screenName: "Node \(item.nodeId)"),
                executablePath: "/mock/\(provider.rawValue)",
                arguments: [],
                exitCode: 0,
                stderr: "stderr-line"
            )
        case .batch:
            if let eventHandler {
                await eventHandler(.started(executablePath: "/mock/\(provider.rawValue)", arguments: [], isSharedLog: true))
                await eventHandler(.stdout("shared-batch-line\n"))
                await eventHandler(.finished(exitCode: 0))
            }
            return AgentRunResult(
                output: """
                <<<FIGBRIDGE_DESIGN_IR_START fileKey=FILE1 nodeId=1:2>>>
                \(makeAgentDesignIRJSON(fileKey: "FILE1", nodeId: "1:2", screenName: "Node 1"))
                <<<FIGBRIDGE_DESIGN_IR_END>>>
                <<<FIGBRIDGE_DESIGN_IR_START fileKey=FILE2 nodeId=3:4>>>
                \(makeAgentDesignIRJSON(fileKey: "FILE2", nodeId: "3:4", screenName: "Node 2"))
                <<<FIGBRIDGE_DESIGN_IR_END>>>
                """,
                executablePath: "/mock/\(provider.rawValue)",
                arguments: [],
                exitCode: 0,
                stderr: ""
            )
        }
    }
}

private actor SlowIgnoringCancellationRunner: AgentRunning {
    func run(
        provider: AgentProvider,
        prompt: String,
        item: FigmaLinkItem,
        eventHandler: (@Sendable (AgentRunEvent) async -> Void)?
    ) async throws -> AgentRunResult {
        try? await Task.sleep(nanoseconds: 300_000_000)
        return AgentRunResult(
            output: makeAgentDesignIRJSON(fileKey: item.fileKey, nodeId: item.nodeId, screenName: "Node \(item.nodeId)"),
            executablePath: "/mock/\(provider.rawValue)",
            arguments: [],
            exitCode: 0,
            stderr: ""
        )
    }
}

extension GenerateViewModelTests {
    @Test func singleBatchStrategyCallsRunnerOnlyOnceForMultipleItems() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let harness = try GenerateViewModelHarness(rootDirectory: sandbox.root)
        harness.viewModel.callStrategy = .singleForBatch
        let first = FigmaLinkItem(rawInputLine: "one", title: "One", url: "https://www.figma.com/design/FILE1/A?node-id=1-2", fileKey: "FILE1", nodeId: "1:2")
        let second = FigmaLinkItem(rawInputLine: "two", title: "Two", url: "https://www.figma.com/design/FILE2/B?node-id=3-4", fileKey: "FILE2", nodeId: "3:4")
        harness.viewModel.items = [first, second]

        await harness.viewModel.generate()

        let runner = try #require(harness.recordedRunner)
        #expect(await runner.recordedCalls() == ["FILE1|1:2"])
        #expect(harness.viewModel.items.allSatisfy { $0.generatedYAMLPath != nil })
    }
}
