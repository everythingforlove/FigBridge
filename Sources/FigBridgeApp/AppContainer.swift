import Foundation
import SwiftUI
import FigBridgeCore

enum AppTab: Hashable {
    case generate
    case viewer
    case settings
}

@MainActor
final class TabSelectionCoordinator {
    var onEditBatch: ((PersistedBatch) -> Void)?
}

@MainActor
final class AppContainer: ObservableObject {
    @Published var selectedTab: AppTab = .generate
    @Published var settingsViewModel: SettingsViewModel
    @Published var generateViewModel: GenerateViewModel
    @Published var viewerViewModel: ViewerViewModel

    init() {
        let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("FigBridge", isDirectory: true) ?? FileManager.default.temporaryDirectory.appendingPathComponent("FigBridge", isDirectory: true)
        let batchesDirectory = baseDirectory.appendingPathComponent("Batches", isDirectory: true)
        let designPackagesDirectory = baseDirectory.appendingPathComponent("DesignPackages", isDirectory: true)
        let settingsURL = baseDirectory.appendingPathComponent("settings.json")
        let draftURL = baseDirectory.appendingPathComponent("generate-workspace-draft.json")
        let settingsStore = SettingsStore(fileURL: settingsURL)
        let batchStore = BatchStore(rootDirectory: batchesDirectory)
        let designPackageStore = DesignPackageStore(rootDirectory: designPackagesDirectory)
        let agentService = AgentService()
        let figmaService = FigmaService(baseDirectory: baseDirectory)
        let generationCoordinator = GenerationCoordinator(batchStore: batchStore, agentRunner: agentService)
        let draftStore = GenerateWorkspaceDraftStore(fileURL: draftURL)
        let tabSelectionCoordinator = TabSelectionCoordinator()

        let settingsViewModel = SettingsViewModel(settingsStore: settingsStore, agentService: agentService, figmaService: figmaService)
        let generateViewModel = GenerateViewModel(
            settingsViewModel: settingsViewModel,
            batchStore: batchStore,
            generationCoordinator: generationCoordinator,
            figmaService: figmaService,
            draftStore: draftStore
        )
        let viewerViewModel = ViewerViewModel(
            batchStore: batchStore,
            designPackageStore: designPackageStore,
            continueEditing: { batch in
                tabSelectionCoordinator.onEditBatch?(batch)
            },
            batchRenamed: { [weak generateViewModel] oldID, oldDirectory, renamed in
                generateViewModel?.handleBatchRenamed(oldID: oldID, oldDirectory: oldDirectory, renamed: renamed)
            }
        )

        self.settingsViewModel = settingsViewModel
        self.generateViewModel = generateViewModel
        self.viewerViewModel = viewerViewModel
        tabSelectionCoordinator.onEditBatch = { [weak self, weak generateViewModel] batch in
            generateViewModel?.loadBatchIntoWorkspace(batch)
            self?.selectedTab = .generate
        }
    }
}
