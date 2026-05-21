import Foundation
import FigBridgeCore

@MainActor
final class ResourceLoadController {
    private var tasks: [UUID: Task<Void, Never>] = [:]

    func schedule(
        for itemID: UUID,
        force: Bool,
        item: FigmaLinkItem?,
        load: @escaping @MainActor (UUID) async -> Void
    ) {
        if force {
            cancel(for: itemID)
        } else if tasks[itemID] != nil {
            return
        }

        guard let item else {
            return
        }
        if !force {
            if item.previewStatus == .success || item.resourceStatus == .success {
                return
            }
            if item.previewStatus == .loading || item.resourceStatus == .loading {
                return
            }
        }

        let task = Task {
            await load(itemID)
        }
        tasks[itemID] = task
    }

    func complete(for itemID: UUID) {
        tasks[itemID] = nil
    }

    func cancel(for itemID: UUID) {
        tasks[itemID]?.cancel()
        tasks[itemID] = nil
    }

    func cancelAll() {
        for task in tasks.values {
            task.cancel()
        }
        tasks.removeAll()
    }
}
