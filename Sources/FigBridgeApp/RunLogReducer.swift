import Foundation
import FigBridgeCore

@MainActor
final class RunLogReducer {
    private var sharedRunLogIDByBatchKey: [String: String] = [:]

    func reset() {
        sharedRunLogIDByBatchKey.removeAll()
    }

    func apply(
        _ event: AgentRunEvent,
        for itemID: UUID,
        provider: AgentProvider,
        batchKey: String,
        pendingItemIDs: [UUID],
        runLogsByItemID: inout [UUID: GenerationRunLog]
    ) -> GenerationRunLog {
        let existingLog = runLogsByItemID[itemID]
        var log = existingLog ?? GenerationRunLog(id: UUID().uuidString.lowercased(), isShared: false, provider: provider)
        switch event {
        case .metadata(let providerKind, let model, let requestSummary):
            log.providerKind = providerKind
            log.model = model
            log.requestSummary = requestSummary
        case .started(let executablePath, let arguments, let isSharedLog):
            if isSharedLog {
                let sharedID = sharedRunLogIDByBatchKey[batchKey] ?? log.id
                sharedRunLogIDByBatchKey[batchKey] = sharedID
                if let sharedLog = runLogsByItemID.values.first(where: { $0.id == sharedID }) {
                    log = sharedLog
                } else {
                    log = GenerationRunLog(id: sharedID, isShared: true, provider: provider)
                }
            }
            log.isShared = isSharedLog
            log.executablePath = executablePath
            log.arguments = arguments
            log.startedAt = log.startedAt ?? Date()
            log.status = .running
        case .stdout(let text):
            log.stdout += text
        case .stderr(let text):
            log.stderr += text
        case .finished(let exitCode):
            log.exitCode = exitCode
            log.endedAt = Date()
            log.status = exitCode == 0 ? .finished : .failed
        case .failed(let message):
            log.errorMessage = message
            log.endedAt = Date()
            log.status = .failed
        case .cancelled:
            log.endedAt = Date()
            log.status = .cancelled
        }

        runLogsByItemID[itemID] = log
        if log.isShared {
            for otherItemID in pendingItemIDs {
                runLogsByItemID[otherItemID] = log
            }
        }
        return log
    }
}
