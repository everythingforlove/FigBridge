import Foundation
import FigBridgeCore

@MainActor
final class GenerationSessionController {
    private var generationTask: Task<PersistedBatch, Error>?
    private var activeSessionID: UUID?
    private var cancelledSessionIDs: Set<UUID> = []

    func beginSession() -> UUID {
        let sessionID = UUID()
        activeSessionID = sessionID
        cancelledSessionIDs.remove(sessionID)
        return sessionID
    }

    func setTask(_ task: Task<PersistedBatch, Error>) {
        generationTask = task
    }

    func cancel() {
        if let activeSessionID {
            cancelledSessionIDs.insert(activeSessionID)
        }
        generationTask?.cancel()
    }

    func clear() {
        generationTask = nil
        activeSessionID = nil
        cancelledSessionIDs.removeAll()
    }

    func isActive(_ sessionID: UUID) -> Bool {
        activeSessionID == sessionID
    }

    func wasCancelled(_ sessionID: UUID) -> Bool {
        cancelledSessionIDs.contains(sessionID)
    }

    func finishIfActive(_ sessionID: UUID) {
        if activeSessionID == sessionID {
            generationTask = nil
            activeSessionID = nil
        }
        cancelledSessionIDs.remove(sessionID)
    }
}
