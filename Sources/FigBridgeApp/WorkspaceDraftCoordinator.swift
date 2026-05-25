import Foundation
import FigBridgeCore

@MainActor
final class WorkspaceDraftCoordinator {
    private let draftStore: GenerateWorkspaceDraftStore
    private(set) var isRestoringWorkspace = false

    init(draftStore: GenerateWorkspaceDraftStore) {
        self.draftStore = draftStore
    }

    func beginRestoring() {
        isRestoringWorkspace = true
    }

    func endRestoring() {
        isRestoringWorkspace = false
    }

    func load() -> GenerateWorkspaceDraft? {
        draftStore.load()
    }

    func persistIfNeeded(
        currentBatchID: String?,
        items: [FigmaLinkItem],
        inputText: String,
        draft: @autoclosure () -> GenerateWorkspaceDraft
    ) throws {
        guard !isRestoringWorkspace else {
            return
        }
        let hasMeaningfulWorkspaceState = currentBatchID != nil
            || !items.isEmpty
            || !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasMeaningfulWorkspaceState else {
            return
        }
        try persist(draft(), force: false)
    }

    func persist(_ draft: GenerateWorkspaceDraft, force: Bool) throws {
        guard !isRestoringWorkspace || force else {
            return
        }
        try draftStore.save(draft)
    }
}
