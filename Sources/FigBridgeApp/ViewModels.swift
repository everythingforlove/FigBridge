import AppKit
import Foundation
import SwiftUI
import FigBridgeCore

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var settings: AppSettings = .defaultValue {
        didSet {
            guard oldValue != settings else {
                return
            }
            scheduleAutosave()
        }
    }
    @Published var availableAgents: [AgentDescriptor] = []
    @Published var message: String = ""
    @Published var isError: Bool = false
    @Published var isShowingTokenHelp: Bool = false
    @Published var isTestingToken: Bool = false
    @Published var toastMessage: String = ""
    @Published var isToastError: Bool = false

    static let tokenHelpSteps: [String] = [
        "打开 Figma，进入 Settings。",
        "进入 Personal access tokens。",
        "创建新 Token 并复制到这里（建议使用拥有只读权限的 Personal Access Token）。",
    ]
    static let tokenHelpURL = URL(string: "https://help.figma.com/hc/en-us/articles/8085703771159-Manage-personal-access-tokens")!

    private let settingsStore: SettingsStore
    private let agentService: AgentService
    private let figmaService: FigmaService
    private var bootstrapped = false
    private var hasLoadedPersistedSettings = false
    private var autosaveTask: Task<Void, Never>?

    init(settingsStore: SettingsStore, agentService: AgentService, figmaService: FigmaService) {
        self.settingsStore = settingsStore
        self.agentService = agentService
        self.figmaService = figmaService
    }

    func bootstrap() async {
        guard !bootstrapped else {
            return
        }
        bootstrapped = true
        do {
            availableAgents = try await agentService.detectAvailableAgents()
            settings = try settingsStore.loadValidatingSelectedAgent(availableAgents: availableAgents.map(\.provider))
            hasLoadedPersistedSettings = true
        } catch {
            message = error.localizedDescription
            isError = true
        }
    }

    func refreshAgents() async {
        do {
            availableAgents = try await agentService.detectAvailableAgents()
            settings = try settingsStore.loadValidatingSelectedAgent(availableAgents: availableAgents.map(\.provider))
            hasLoadedPersistedSettings = true
            message = ""
            isError = false
        } catch {
            message = error.localizedDescription
            isError = true
        }
    }

    func testToken() async {
        isTestingToken = true
        defer { isTestingToken = false }
        do {
            try await figmaService.validateToken(settings.figmaToken)
            toastMessage = "Token 可用"
            isToastError = false
        } catch {
            toastMessage = error.localizedDescription
            isToastError = true
        }
    }

    func restoreDefaultPrompt() {
        settings.promptTemplate = AppSettings.defaultPrompt
    }

    func scheduleAutosave() {
        guard hasLoadedPersistedSettings else {
            return
        }
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else {
                return
            }
            await MainActor.run {
                self?.persistSettings(showSuccessMessage: false)
            }
        }
    }

    func persistSettings(showSuccessMessage: Bool) {
        do {
            try settingsStore.save(settings)
            if showSuccessMessage {
                message = "设置已保存"
                isError = false
            } else if isError {
                message = ""
                isError = false
            }
        } catch {
            message = error.localizedDescription
            isError = true
        }
    }

    func updateSelectedAgent(_ selectedAgentID: String?) {
        guard settings.selectedAgentID != selectedAgentID else {
            return
        }
        settings.selectedAgentID = selectedAgentID
        persistSettings(showSuccessMessage: false)
    }

    func markPersistedSettingsLoadedForTesting() {
        hasLoadedPersistedSettings = true
    }
}

@MainActor
final class GenerateViewModel: ObservableObject {
    @Published var availableAgents: [AgentDescriptor] = []
    @Published var isRefreshingAgents: Bool = false
    @Published var selectedAgentID: String? {
        didSet {
            guard oldValue != selectedAgentID else {
                return
            }
            persistDraftIfNeeded()
            persistSelectedAgentToSettingsIfNeeded()
        }
    }
    @Published var promptTemplate: String = AppSettings.defaultPrompt {
        didSet { persistDraftIfNeeded() }
    }
    @Published var outputDirectoryPath: String = "" {
        didSet {
            guard !isSynchronizingOutputDirectory else {
                return
            }
            persistDraftIfNeeded()
        }
    }
    @Published var mode: GenerationMode = .sequential {
        didSet { persistDraftIfNeeded() }
    }
    @Published var parallelism: Int = 2 {
        didSet { persistDraftIfNeeded() }
    }
    @Published var callStrategy: AgentCallStrategy = .singlePerLink {
        didSet { persistDraftIfNeeded() }
    }
    @Published var inputText: String = "" {
        didSet { persistDraftIfNeeded() }
    }
    @Published var items: [FigmaLinkItem] = [] {
        didSet {
            if selectedItemID != nil {
                loadSelectedYAML()
            }
            persistDraftIfNeeded()
        }
    }
    @Published var selectedItemID: UUID? {
        didSet {
            guard oldValue != selectedItemID else {
                return
            }
            loadSelectedYAML()
            refreshSelectedRunLog()
            persistDraftIfNeeded()
        }
    }
    @Published var validationMessage: String = ""
    @Published var exportMessage: String = ""
    @Published var isGenerating: Bool = false
    @Published var progressText: String = ""
    @Published var completedCount: Int = 0
    @Published var currentBatchID: String? {
        didSet { persistDraftIfNeeded() }
    }
    @Published var currentBatchDirectory: String? {
        didSet { persistDraftIfNeeded() }
    }
    @Published var selectedYAMLText: String?
    @Published var selectedRunLog: GenerationRunLog?
    @Published var selectedRunLogText: String = ""
    @Published var itemRename = RenameState<UUID>()

    private let settingsViewModel: SettingsViewModel
    private let batchStore: BatchStore
    private let generationCoordinator: GenerationCoordinator
    private let figmaService: FigmaService
    private let draftStore: GenerateWorkspaceDraftStore
    private let parser = FigmaLinkParser()
    private var bootstrapped = false
    private var generationTask: Task<PersistedBatch, Error>?
    private var isRestoringWorkspace = false
    private var isSynchronizingOutputDirectory = false
    private var resourceLoadTasks: [UUID: Task<Void, Never>] = [:]
    private var runLogsByItemID: [UUID: GenerationRunLog] = [:]
    private var sharedRunLogIDByBatchKey: [String: String] = [:]
    private var activeGenerationSessionID: UUID?
    private var cancelledGenerationSessionIDs: Set<UUID> = []

    init(settingsViewModel: SettingsViewModel, batchStore: BatchStore, generationCoordinator: GenerationCoordinator, figmaService: FigmaService, draftStore: GenerateWorkspaceDraftStore) {
        self.settingsViewModel = settingsViewModel
        self.batchStore = batchStore
        self.generationCoordinator = generationCoordinator
        self.figmaService = figmaService
        self.draftStore = draftStore
    }

    var selectedItem: FigmaLinkItem? {
        guard let selectedItemID else {
            return nil
        }
        return items.first(where: { $0.id == selectedItemID })
    }

    var selectedItemResourceStatusText: String {
        guard let item = selectedItem else {
            return ""
        }
        if isTokenMissing {
            return "token 未设置"
        }
        return item.resourceStatus.rawValue
    }

    var selectedItemGenerationStatusText: String {
        guard let item = selectedItem else {
            return ""
        }
        if isTokenMissing {
            return "token 未设置"
        }
        return item.generationStatus.rawValue
    }

    var shouldHighlightSelectedItemResourceStatus: Bool {
        isTokenMissing || selectedItem?.resourceStatus == .failed
    }

    var shouldHighlightSelectedItemGenerationStatus: Bool {
        isTokenMissing || selectedItem?.generationStatus == .failed
    }

    var pendingItems: [FigmaLinkItem] {
        items.filter { $0.generatedYAMLPath == nil }
    }

    var processedItems: [FigmaLinkItem] {
        items.filter { $0.generatedYAMLPath != nil }
    }

    var canGenerate: Bool {
        !isGenerating
        && selectedAgentID != nil
        && !promptTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !pendingItems.isEmpty
    }

    func bootstrap() async {
        guard !bootstrapped else {
            return
        }
        bootstrapped = true
        await settingsViewModel.bootstrap()
        availableAgents = settingsViewModel.availableAgents
        isRestoringWorkspace = true
        applyDefaultWorkspaceSettings()
        if let draft = draftStore.load() {
            applyWorkspaceDraft(draft)
        }
        isRestoringWorkspace = false
        preloadResourcesForAllItemsIfNeeded()
    }

    func addInput() {
        let trimmedInput = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else {
            validationMessage = "请输入要添加的信息"
            return
        }

        let result = parser.parse(inputText)
        validationMessage = result.errors.joined(separator: "\n")
        let existing = Set(items.map { "\($0.fileKey)|\($0.nodeId)" })
        let newItems = result.items.filter { !existing.contains("\($0.fileKey)|\($0.nodeId)") }
        items.append(contentsOf: newItems)
        if !newItems.isEmpty {
            inputText = ""
        }
        if selectedItemID == nil {
            selectedItemID = items.first?.id
        }
        preloadResourcesForAllItemsIfNeeded()
    }

    func resetWorkspace() {
        startNewBatch()
    }

    func startNewBatch() {
        cancelGeneration()
        isGenerating = false
        generationTask = nil
        activeGenerationSessionID = nil
        cancelAllResourceLoads()
        currentBatchID = nil
        currentBatchDirectory = nil
        isRestoringWorkspace = true
        applyDefaultWorkspaceSettings()
        inputText = ""
        items = []
        selectedItemID = nil
        validationMessage = ""
        exportMessage = ""
        progressText = ""
        completedCount = 0
        selectedYAMLText = nil
        runLogsByItemID.removeAll()
        selectedRunLog = nil
        selectedRunLogText = ""
        isRestoringWorkspace = false
        persistDraft(force: true)
    }

    func generate() async {
        guard canGenerate else {
            validationMessage = "请先完成 agent、prompt 和链接校验"
            return
        }
        guard let selectedAgentID,
              let provider = AgentProvider.allCases.first(where: { $0.id == selectedAgentID }) else {
            validationMessage = "未选择 agent"
            return
        }

        let sessionID = UUID()
        activeGenerationSessionID = sessionID
        cancelledGenerationSessionIDs.remove(sessionID)
        isGenerating = true
        completedCount = 0
        let pendingItemIDs = Set(pendingItems.map(\.id))
        let pendingTotal = pendingItemIDs.count
        progressText = "准备生成 \(pendingTotal) 项"
        validationMessage = ""
        for index in items.indices {
            guard pendingItemIDs.contains(items[index].id) else {
                continue
            }
            items[index].generationStatus = .queued
            items[index].logSummary = "等待执行"
            items[index].errorMessage = nil
        }

        let task = Task<PersistedBatch, Error> {
            let resolvedOutputDirectory = await MainActor.run { self.resolvedOutputDirectoryForGeneration() }
            return try await generationCoordinator.generate(
                agent: provider,
                promptTemplate: promptTemplate,
                sourceInputText: inputText,
                outputDirectory: resolvedOutputDirectory,
                mode: mode,
                parallelism: parallelism,
                callStrategy: callStrategy,
                existingBatchID: currentBatchID,
                items: items,
                itemStarted: { [weak self] item in
                    await MainActor.run {
                        guard let self,
                              self.isGenerationSessionActive(sessionID),
                              let index = self.items.firstIndex(where: { $0.id == item.id }) else {
                            return
                        }
                        self.items[index] = item
                    }
                },
                progress: { [weak self] completed, total, item in
                    await MainActor.run {
                        guard let self, self.isGenerationSessionActive(sessionID) else {
                            return
                        }
                        self.completedCount = completed
                        self.progressText = "已完成 \(completed)/\(total)：\(item.title ?? item.nodeName ?? item.nodeId)"
                        if let index = self.items.firstIndex(where: { $0.id == item.id }) {
                            self.items[index] = item
                        }
                    }
                },
                itemEvent: { [weak self] itemID, event in
                    await MainActor.run {
                        guard let self, self.isGenerationSessionActive(sessionID) else {
                            return
                        }
                        self.applyRunEvent(event, for: itemID, provider: provider)
                    }
                }
            )
        }
        generationTask = task
        var shouldFinishAsCancelled = false

        do {
            let persisted = try await task.value
            guard isGenerationSessionActive(sessionID) else {
                shouldFinishAsCancelled = cancelledGenerationSessionIDs.contains(sessionID)
                throw CancellationError()
            }
            if cancelledGenerationSessionIDs.contains(sessionID) {
                shouldFinishAsCancelled = true
                throw CancellationError()
            }
            let latestRunLogsByItemID = runLogsByItemID
            items = persisted.summary.items
            currentBatchID = persisted.summary.id
            currentBatchDirectory = persisted.batchDirectory.path
            syncOutputDirectoryPath()
            let updatedPersisted = try batchStore.updateBatch(
                id: persisted.summary.id,
                sourceInputText: persisted.summary.sourceInputText,
                agent: persisted.summary.agent,
                promptSnapshot: persisted.summary.promptSnapshot,
                outputDirectory: URL(fileURLWithPath: persisted.summary.outputDirectory, isDirectory: true),
                mode: persisted.summary.mode,
                parallelism: persisted.summary.parallelism,
                callStrategy: persisted.summary.callStrategy,
                items: persisted.summary.items,
                runLogsByItemID: latestRunLogsByItemID
            )
            runLogsByItemID = updatedPersisted.summary.runLogsByItemID
            loadSelectedYAML()
            refreshSelectedRunLog()
            validationMessage = "生成完成"
            persistDraftIfNeeded()
        } catch is CancellationError {
            if shouldFinishAsCancelled || isGenerationSessionActive(sessionID) || cancelledGenerationSessionIDs.contains(sessionID) {
                validationMessage = "生成已取消"
            }
        } catch {
            if cancelledGenerationSessionIDs.contains(sessionID) {
                validationMessage = "生成已取消"
            } else if isGenerationSessionActive(sessionID) {
                validationMessage = error.localizedDescription
            }
        }

        if activeGenerationSessionID == sessionID {
            isGenerating = false
            generationTask = nil
            activeGenerationSessionID = nil
        }
        cancelledGenerationSessionIDs.remove(sessionID)
    }

    func cancelGeneration() {
        if let activeGenerationSessionID {
            cancelledGenerationSessionIDs.insert(activeGenerationSessionID)
        }
        generationTask?.cancel()
    }

    private func isGenerationSessionActive(_ sessionID: UUID) -> Bool {
        activeGenerationSessionID == sessionID
    }

    func refreshAgents() async {
        isRefreshingAgents = true
        defer { isRefreshingAgents = false }
        await settingsViewModel.refreshAgents()
        availableAgents = settingsViewModel.availableAgents
        selectedAgentID = settingsViewModel.settings.selectedAgentID
    }

    func syncPromptFromSettings() {
        promptTemplate = settingsViewModel.settings.promptTemplate
    }

    func deleteItem(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return
        }
        cancelResourceLoad(for: id)
        let removedItem = items.remove(at: index)

        if let currentBatchID {
            do {
                try batchStore.deleteBatchItem(batchID: currentBatchID, itemID: removedItem.id)
            } catch {
                validationMessage = error.localizedDescription
            }
        }

        if selectedItemID == removedItem.id {
            let nextSelection = items.indices.contains(index) ? items[index].id : items.last?.id
            selectedItemID = nextSelection
        }
        runLogsByItemID.removeValue(forKey: id)
        loadSelectedYAML()
        refreshSelectedRunLog()
        persistDraftIfNeeded()
    }

    func loadSelectedItemPreviewIfNeeded() async {
        loadSelectedYAML()
        guard let selectedItemID else {
            return
        }
        scheduleResourceLoad(for: selectedItemID, force: false)
    }

    func preloadResourcesForAllItemsIfNeeded() {
        for item in items {
            scheduleResourceLoad(for: item.id, force: false)
        }
    }

    func reloadResources(for itemID: UUID) {
        scheduleResourceLoad(for: itemID, force: true)
    }

    func canRefreshResources(for item: FigmaLinkItem) -> Bool {
        isTokenMissing || item.resourceStatus == .failed
    }

    func beginRenamingSelectedItem() {
        guard let item = selectedItem else {
            return
        }
        beginRenamingItem(item.id)
    }

    func beginRenamingItem(_ itemID: UUID) {
        guard let item = items.first(where: { $0.id == itemID }) else {
            return
        }
        itemRename.begin(item.id, originalTitle: item.title ?? item.nodeName ?? item.nodeId)
    }

    func commitRename() {
        guard let renamingItemID = itemRename.identifier,
              let index = items.firstIndex(where: { $0.id == renamingItemID }) else {
            cancelRename()
            return
        }

        let trimmedTitle = itemRename.trimmedTitle
        items[index].title = trimmedTitle.isEmpty ? nil : trimmedTitle

        if let currentBatchID {
            do {
                let persisted = try batchStore.updateBatchItem(batchID: currentBatchID, item: items[index])
                items = persisted.summary.items
                currentBatchDirectory = persisted.batchDirectory.path
            } catch {
                validationMessage = error.localizedDescription
            }
        }

        cancelRename()
        persistDraftIfNeeded()
    }

    func cancelRename() {
        itemRename.cancel()
    }

    func finishRenameOnBlur() {
        guard itemRename.isActive else {
            return
        }
        if itemRename.shouldCommitOnBlur {
            commitRename()
        } else {
            cancelRename()
        }
    }

    private func loadSelectedYAML() {
        guard let yamlPath = selectedItem?.generatedYAMLPath else {
            selectedYAMLText = nil
            refreshSelectedRunLog()
            return
        }
        selectedYAMLText = try? String(contentsOf: URL(fileURLWithPath: yamlPath), encoding: .utf8)
        refreshSelectedRunLog()
    }

    func exportPreviewImage() {
        guard let item = selectedItem,
              let previewPath = item.previewImagePath else {
            return
        }
        let previewURL = URL(fileURLWithPath: previewPath)
        let ext = previewURL.pathExtension.isEmpty ? "png" : previewURL.pathExtension
        exportLocalFile(at: previewURL, preferredName: "\(BatchStore.pathSafe(item.nodeId))-preview.\(ext)")
    }

    func openSelectedPreviewImage() {
        guard let previewPath = selectedItem?.previewImagePath else {
            return
        }
        let previewURL = URL(fileURLWithPath: previewPath)
        guard FileManager.default.fileExists(atPath: previewURL.path) else {
            exportMessage = "原图不存在: \(previewURL.lastPathComponent)"
            return
        }
        DesktopSupport.openFile(previewURL)
    }

    func exportResource(_ resource: FigmaResourceItem) {
        guard let localPath = resource.localPath else {
            return
        }
        exportLocalFile(at: URL(fileURLWithPath: localPath), preferredName: "\(resource.name).\(resource.format.rawValue)")
    }

    func exportAllResources() {
        guard let item = selectedItem,
              let destinationDirectory = DesktopSupport.chooseDirectory(canCreateDirectories: true) else {
            return
        }
        do {
            for resource in item.resourceItems {
                guard let localPath = resource.localPath else {
                    continue
                }
                let sourceURL = URL(fileURLWithPath: localPath)
                _ = try batchStore.copyFileToDirectory(sourceURL, destinationDirectory: destinationDirectory, preferredName: "\(resource.name).\(resource.format.rawValue)")
            }
            exportMessage = "资源已导出到 \(destinationDirectory.path)"
        } catch {
            exportMessage = error.localizedDescription
        }
    }

    private func exportLocalFile(at sourceURL: URL, preferredName: String) {
        guard let destinationDirectory = DesktopSupport.chooseDirectory(canCreateDirectories: true) else {
            return
        }
        do {
            let copiedURL = try batchStore.copyFileToDirectory(sourceURL, destinationDirectory: destinationDirectory, preferredName: preferredName)
            exportMessage = "已导出 \(copiedURL.lastPathComponent)"
        } catch {
            exportMessage = error.localizedDescription
        }
    }

    func loadBatchIntoWorkspace(_ persisted: PersistedBatch) {
        cancelAllResourceLoads()
        isRestoringWorkspace = true
        selectedAgentID = persisted.summary.agent.id
        promptTemplate = persisted.summary.promptSnapshot
        mode = persisted.summary.mode
        parallelism = persisted.summary.parallelism
        callStrategy = persisted.summary.callStrategy
        inputText = persisted.summary.sourceInputText
        items = persisted.summary.items
        selectedItemID = persisted.summary.items.first?.id
        currentBatchID = persisted.summary.id
        currentBatchDirectory = persisted.batchDirectory.path
        syncOutputDirectoryPath()
        validationMessage = ""
        exportMessage = ""
        progressText = ""
        completedCount = 0
        selectedYAMLText = nil
        runLogsByItemID = persisted.summary.runLogsByItemID
        selectedRunLog = nil
        selectedRunLogText = ""
        itemRename.cancel()
        isRestoringWorkspace = false
        loadSelectedYAML()
        persistDraftIfNeeded()
        preloadResourcesForAllItemsIfNeeded()
    }

    func handleBatchRenamed(oldID: String, oldDirectory: URL, renamed: PersistedBatch) {
        let matchesByID = currentBatchID == oldID
        let matchesByDirectory = currentBatchDirectory.map {
            URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL.path == oldDirectory.standardizedFileURL.path
        } ?? false
        guard matchesByID || matchesByDirectory else {
            return
        }

        let previousSelectedItemID = selectedItemID
        items = renamed.summary.items
        if let previousSelectedItemID,
           renamed.summary.items.contains(where: { $0.id == previousSelectedItemID }) {
            selectedItemID = previousSelectedItemID
        } else {
            selectedItemID = renamed.summary.items.first?.id
        }
        currentBatchID = renamed.summary.id
        currentBatchDirectory = renamed.batchDirectory.path
        syncOutputDirectoryPath()
        loadSelectedYAML()
    }

    private func refreshSelectedRunLog() {
        guard let selectedItemID else {
            selectedRunLog = nil
            selectedRunLogText = ""
            return
        }
        let log = runLogsByItemID[selectedItemID]
        selectedRunLog = log
        selectedRunLogText = log?.combinedConsoleText ?? ""
    }

    private func applyRunEvent(_ event: AgentRunEvent, for itemID: UUID, provider: AgentProvider) {
        let batchKey = currentBatchID ?? "workspace"
        let existingLog = runLogsByItemID[itemID]
        var log = existingLog ?? GenerationRunLog(id: UUID().uuidString.lowercased(), isShared: false, provider: provider)
        switch event {
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
        case .failed:
            log.endedAt = Date()
            log.status = .failed
        case .cancelled:
            log.endedAt = Date()
            log.status = .cancelled
        }
        runLogsByItemID[itemID] = log
        if log.isShared {
            for otherItemID in pendingItems.map(\.id) {
                runLogsByItemID[otherItemID] = log
            }
        }
        if selectedItemID == itemID {
            selectedRunLog = log
            selectedRunLogText = log.combinedConsoleText
        }
    }

    private func applyDefaultWorkspaceSettings() {
        selectedAgentID = settingsViewModel.settings.selectedAgentID
        promptTemplate = settingsViewModel.settings.promptTemplate
        mode = settingsViewModel.settings.defaultGenerationMode
        parallelism = settingsViewModel.settings.parallelism
        callStrategy = settingsViewModel.settings.defaultAgentCallStrategy
        syncOutputDirectoryPath()
    }

    private func applyWorkspaceDraft(_ draft: GenerateWorkspaceDraft) {
        selectedAgentID = draft.selectedAgentID
        promptTemplate = draft.promptTemplate
        mode = draft.mode
        parallelism = draft.parallelism
        callStrategy = draft.callStrategy
        inputText = draft.inputText
        items = draft.items
        selectedItemID = draft.selectedItemID
        currentBatchID = draft.currentBatchID
        currentBatchDirectory = draft.currentBatchDirectory
        syncOutputDirectoryPath()
        if let draftBatchID = draft.currentBatchID,
           let persisted = try? batchStore.loadBatch(id: draftBatchID) {
            runLogsByItemID = persisted.summary.runLogsByItemID
        } else {
            runLogsByItemID.removeAll()
        }
        loadSelectedYAML()
    }

    private func persistDraftIfNeeded() {
        guard !isRestoringWorkspace else {
            return
        }
        let hasMeaningfulWorkspaceState = currentBatchID != nil
            || !items.isEmpty
            || !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasMeaningfulWorkspaceState else {
            return
        }
        persistDraft(force: false)
    }

    private func persistDraft(force: Bool) {
        guard !isRestoringWorkspace || force else {
            return
        }
        let draft = GenerateWorkspaceDraft(
            selectedAgentID: selectedAgentID,
            promptTemplate: promptTemplate,
            outputDirectoryPath: outputDirectoryPath,
            mode: mode,
            parallelism: parallelism,
            callStrategy: callStrategy,
            inputText: inputText,
            items: items,
            selectedItemID: selectedItemID,
            currentBatchID: currentBatchID,
            currentBatchDirectory: currentBatchDirectory
        )
        do {
            try draftStore.save(draft)
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private func persistSelectedAgentToSettingsIfNeeded() {
        guard !isRestoringWorkspace else {
            return
        }
        settingsViewModel.updateSelectedAgent(selectedAgentID)
    }

    private func scheduleResourceLoad(for itemID: UUID, force: Bool) {
        if force {
            cancelResourceLoad(for: itemID)
        } else if resourceLoadTasks[itemID] != nil {
            return
        }

        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            return
        }
        let item = items[index]
        if !force {
            if item.previewStatus == .success || item.resourceStatus == .success {
                return
            }
            if item.previewStatus == .loading || item.resourceStatus == .loading {
                return
            }
        }

        let task = Task { [weak self] in
            guard let self else {
                return
            }
            await self.loadResources(for: itemID)
        }
        resourceLoadTasks[itemID] = task
    }

    private func loadResources(for itemID: UUID) async {
        defer { resourceLoadTasks[itemID] = nil }
        guard !Task.isCancelled else {
            return
        }
        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            return
        }
        let token = settingsViewModel.settings.figmaToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            return
        }

        items[index].previewStatus = .loading
        items[index].resourceStatus = .loading
        items[index].errorMessage = nil

        do {
            let itemDirectory = resolvedItemDirectory(for: items[index])
            let previewFormat = settingsViewModel.settings.defaultExportFormat
            let resolved = try await figmaService.loadPreviewAndResources(
                for: items[index],
                itemDirectory: itemDirectory,
                token: token,
                previewFormat: previewFormat
            )
            guard !Task.isCancelled else {
                return
            }
            guard let refreshedIndex = items.firstIndex(where: { $0.id == itemID }) else {
                return
            }
            var persistedItem = resolved
            if let currentBatchID {
                let persisted = try batchStore.updateBatchItem(batchID: currentBatchID, item: resolved)
                currentBatchDirectory = persisted.batchDirectory.path
                if let updated = persisted.summary.items.first(where: { $0.id == itemID }) {
                    persistedItem = updated
                }
            }
            items[refreshedIndex] = persistedItem
        } catch {
            guard !Task.isCancelled else {
                return
            }
            guard let refreshedIndex = items.firstIndex(where: { $0.id == itemID }) else {
                return
            }
            items[refreshedIndex].previewStatus = .failed
            items[refreshedIndex].resourceStatus = .failed
            items[refreshedIndex].errorMessage = error.localizedDescription
        }
    }

    private func cancelResourceLoad(for itemID: UUID) {
        resourceLoadTasks[itemID]?.cancel()
        resourceLoadTasks[itemID] = nil
    }

    private func cancelAllResourceLoads() {
        for task in resourceLoadTasks.values {
            task.cancel()
        }
        resourceLoadTasks.removeAll()
    }

    private func resolvedOutputDirectoryForGeneration() -> URL {
        if let currentBatchID {
            return batchStore.exportsDirectory(forBatchID: currentBatchID)
        }
        return batchStore.rootDirectory
    }

    private func syncOutputDirectoryPath() {
        isSynchronizingOutputDirectory = true
        if let currentBatchDirectory {
            outputDirectoryPath = batchStore.exportsDirectory(for: URL(fileURLWithPath: currentBatchDirectory, isDirectory: true)).path
        } else if let currentBatchID {
            outputDirectoryPath = batchStore.exportsDirectory(forBatchID: currentBatchID).path
        } else {
            outputDirectoryPath = "当前批次/exports"
        }
        isSynchronizingOutputDirectory = false
    }

    private func resolvedItemDirectory(for item: FigmaLinkItem) -> URL {
        let batchDirectory: URL
        if let currentBatchDirectory {
            batchDirectory = URL(fileURLWithPath: currentBatchDirectory, isDirectory: true)
        } else if let currentBatchID {
            batchDirectory = batchStore.batchDirectory(for: currentBatchID)
        } else {
            batchDirectory = batchStore.rootDirectory.appendingPathComponent("__workspace__", isDirectory: true)
        }
        return BatchStore.itemDirectory(in: batchDirectory, item: item)
    }

    private var isTokenMissing: Bool {
        settingsViewModel.settings.figmaToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

@MainActor
final class ViewerViewModel: ObservableObject {
    @Published var batches: [PersistedBatch] = []
    @Published var selectedBatchID: String? {
        didSet {
            guard !isSynchronizingSelection, oldValue != selectedBatchID else {
                return
            }
            synchronizeSelectionForCurrentBatch(resetItemSelection: true)
        }
    }
    @Published var selectedItemID: UUID? {
        didSet {
            guard !isSynchronizingSelection, oldValue != selectedItemID else {
                return
            }
            synchronizeSelectedItem()
        }
    }
    @Published var selectedYAMLText: String?
    @Published var selectedRunLog: GenerationRunLog?
    @Published var selectedRunLogText: String = ""
    @Published var selectedSourceInputText: String?
    @Published var message: String = ""
    @Published var batchRename = RenameState<String>()
    @Published var itemRename = RenameState<UUID>()

    private let batchStore: BatchStore
    private let continueEditing: (PersistedBatch) -> Void
    private let batchRenamed: (_ oldID: String, _ oldDirectory: URL, _ renamed: PersistedBatch) -> Void
    private var isSynchronizingSelection = false

    init(
        batchStore: BatchStore,
        continueEditing: @escaping (PersistedBatch) -> Void = { _ in },
        batchRenamed: @escaping (_ oldID: String, _ oldDirectory: URL, _ renamed: PersistedBatch) -> Void = { _, _, _ in }
    ) {
        self.batchStore = batchStore
        self.continueEditing = continueEditing
        self.batchRenamed = batchRenamed
    }

    var selectedBatch: PersistedBatch? {
        guard let selectedBatchID else {
            return nil
        }
        return batches.first(where: { $0.summary.id == selectedBatchID })
    }

    var selectedItem: FigmaLinkItem? {
        guard let selectedItemID else {
            return nil
        }
        return selectedBatch?.summary.items.first(where: { $0.id == selectedItemID })
    }

    var canCopyPrompt: Bool {
        guard let batch = selectedBatch else {
            return false
        }
        return batch.summary.items.contains { $0.generatedYAMLPath != nil }
    }

    var selectedBatchExportsDirectory: URL? {
        guard let batch = selectedBatch else {
            return nil
        }
        return batch.batchDirectory.appendingPathComponent(BatchStore.exportsDirectoryName, isDirectory: true)
    }

    func reload() {
        do {
            batches = try batchStore.scanBatches()
            synchronizeSelectionForCurrentBatch(resetItemSelection: false)
            message = ""
        } catch {
            batches = []
            message = error.localizedDescription
        }
    }

    func copyPrompt() {
        guard let batch = selectedBatch else {
            return
        }
        let prompt = batchStore.makeCopyPrompt(for: batch.summary.items.filter { $0.generatedYAMLPath != nil })
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        message = "Prompt 已复制"
    }

    func exportSelectedBatch() {
        guard let batch = selectedBatch else {
            return
        }
        let baseDirectory = DesktopSupport.chooseDirectory(canCreateDirectories: true) ?? batch.batchDirectory.deletingLastPathComponent()
        let destinationURL = baseDirectory.appendingPathComponent("\(batch.summary.id).zip")
        do {
            let result = try batchStore.exportBatch(at: batch.batchDirectory, to: destinationURL)
            message = Self.makeExportMessage(for: result)
        } catch {
            message = error.localizedDescription
        }
    }

    func importBatchZipUsingPanel() {
        guard let zipURL = DesktopSupport.chooseZipArchive() else {
            return
        }
        do {
            _ = try batchStore.importBatchArchive(from: zipURL)
            reload()
            message = "已导入 \(zipURL.lastPathComponent)"
        } catch {
            message = error.localizedDescription
        }
    }

    func importBatchDirectoryUsingPanel() {
        guard let directoryURL = DesktopSupport.chooseDirectory() else {
            return
        }
        do {
            _ = try batchStore.importBatchDirectory(from: directoryURL)
            reload()
            message = "已导入 \(directoryURL.lastPathComponent)"
        } catch {
            message = error.localizedDescription
        }
    }

    func openSelectedBatchInFinder() {
        guard let batch = selectedBatch else {
            return
        }
        DesktopSupport.openInFinder(batch.batchDirectory)
    }

    func openSelectedBatchExportsDirectoryInFinder() {
        guard let exportsDirectory = selectedBatchExportsDirectory else {
            return
        }
        try? FileManager.default.createDirectory(at: exportsDirectory, withIntermediateDirectories: true)
        DesktopSupport.openInFinder(exportsDirectory)
    }

    func deleteSelectedBatch() {
        guard let batch = selectedBatch else {
            return
        }
        do {
            try batchStore.deleteBatch(at: batch.batchDirectory)
            selectedBatchID = nil
            selectedItemID = nil
            reload()
            message = "已删除 \(batch.summary.id)"
        } catch {
            message = error.localizedDescription
        }
    }

    static func makeExportMessage(for result: BatchExportResult) -> String {
        let baseMessage = "已导出到 \(result.archiveURL.path)"
        guard result.missingImageCount > 0 else {
            return baseMessage
        }
        return "\(baseMessage)，但有 \(result.missingImageCount) 个图片资源缺失"
    }

    func continueEditingSelectedBatch() {
        guard let batch = selectedBatch else {
            return
        }
        continueEditing(batch)
    }

    func continueEditingBatch(_ batchID: String) {
        guard let batch = batches.first(where: { $0.summary.id == batchID }) else {
            return
        }
        continueEditing(batch)
    }

    func openSelectedPreviewImage() {
        guard let previewPath = selectedItem?.previewImagePath else {
            return
        }
        let previewURL = URL(fileURLWithPath: previewPath)
        guard FileManager.default.fileExists(atPath: previewURL.path) else {
            message = "原图不存在: \(previewURL.lastPathComponent)"
            return
        }
        DesktopSupport.openFile(previewURL)
    }

    func beginRenamingSelectedBatch() {
        guard let batch = selectedBatch else {
            return
        }
        beginRenamingBatch(batch.summary.id)
    }

    func beginRenamingBatch(_ batchID: String) {
        guard batches.contains(where: { $0.summary.id == batchID }) else {
            return
        }
        batchRename.begin(batchID, originalTitle: batchID)
    }

    func commitBatchRename() {
        guard let batch = selectedBatch else {
            cancelBatchRename()
            return
        }

        let trimmedTitle = batchRename.trimmedTitle
        do {
            let oldBatchID = batch.summary.id
            let oldBatchDirectory = batch.batchDirectory
            let persisted = try batchStore.renameBatch(id: batch.summary.id, to: trimmedTitle)
            if let index = batches.firstIndex(where: { $0.summary.id == batch.summary.id }) {
                batches[index] = persisted
            }
            selectedBatchID = persisted.summary.id
            synchronizeSelectionForCurrentBatch(resetItemSelection: false)
            batchRenamed(oldBatchID, oldBatchDirectory, persisted)
            message = "名称已更新"
        } catch {
            message = error.localizedDescription
        }

        cancelBatchRename()
    }

    func cancelBatchRename() {
        batchRename.cancel()
    }

    func finishBatchRenameOnBlur() {
        guard batchRename.isActive else {
            return
        }
        if batchRename.shouldCommitOnBlur {
            commitBatchRename()
        } else {
            cancelBatchRename()
        }
    }

    func beginRenamingSelectedItem() {
        guard let item = selectedItem else {
            return
        }
        beginRenamingItem(item.id)
    }

    func beginRenamingItem(_ itemID: UUID) {
        guard let item = selectedBatch?.summary.items.first(where: { $0.id == itemID }) else {
            return
        }
        itemRename.begin(item.id, originalTitle: item.title ?? item.nodeName ?? item.nodeId)
    }

    func commitRename() {
        guard let batch = selectedBatch,
              let item = selectedItem else {
            cancelRename()
            return
        }

        let trimmedTitle = itemRename.trimmedTitle
        var updatedItem = item
        updatedItem.title = trimmedTitle.isEmpty ? nil : trimmedTitle

        do {
            let persisted = try batchStore.updateBatchItem(batchID: batch.summary.id, item: updatedItem)
            if let index = batches.firstIndex(where: { $0.summary.id == persisted.summary.id }) {
                batches[index] = persisted
            }
            synchronizeSelectionForCurrentBatch(resetItemSelection: false)
            message = "名称已更新"
        } catch {
            message = error.localizedDescription
        }

        cancelRename()
    }

    func cancelRename() {
        itemRename.cancel()
    }

    func finishRenameOnBlur() {
        guard itemRename.isActive else {
            return
        }
        if itemRename.shouldCommitOnBlur {
            commitRename()
        } else {
            cancelRename()
        }
    }

    private func loadSelectedYAML() {
        guard let yamlPath = selectedItem?.generatedYAMLPath else {
            selectedYAMLText = nil
            loadSelectedRunLog()
            return
        }
        selectedYAMLText = try? String(contentsOf: URL(fileURLWithPath: yamlPath), encoding: .utf8)
        loadSelectedRunLog()
    }

    private func loadSelectedRunLog() {
        guard let batch = selectedBatch,
              let selectedItemID else {
            selectedRunLog = nil
            selectedRunLogText = ""
            return
        }
        let log = batch.summary.runLogsByItemID[selectedItemID]
        selectedRunLog = log
        selectedRunLogText = log?.combinedConsoleText ?? ""
    }

    private func loadSelectedSourceInput() {
        guard let batch = selectedBatch else {
            selectedSourceInputText = nil
            return
        }
        let sourceInputURL = batch.batchDirectory.appendingPathComponent("source-input.txt")
        selectedSourceInputText = try? String(contentsOf: sourceInputURL, encoding: .utf8)
    }

    private func synchronizeSelectionForCurrentBatch(resetItemSelection: Bool) {
        isSynchronizingSelection = true
        defer { isSynchronizingSelection = false }

        let availableBatchIDs = Set(batches.map(\.summary.id))
        if let selectedBatchID, !availableBatchIDs.contains(selectedBatchID) {
            self.selectedBatchID = nil
        }
        if self.selectedBatchID == nil {
            self.selectedBatchID = batches.first?.summary.id
        }

        loadSelectedSourceInput()

        guard let batch = selectedBatch else {
            selectedItemID = nil
            selectedYAMLText = nil
            selectedRunLog = nil
            selectedRunLogText = ""
            return
        }

        let availableItemIDs = Set(batch.summary.items.map(\.id))
        if resetItemSelection || selectedItemID == nil || !availableItemIDs.contains(selectedItemID!) {
            selectedItemID = batch.summary.items.first?.id
        }

        loadSelectedYAML()
    }

    private func synchronizeSelectedItem() {
        guard let batch = selectedBatch else {
            selectedYAMLText = nil
            return
        }

        if let currentSelectedItemID = selectedItemID, !batch.summary.items.contains(where: { $0.id == currentSelectedItemID }) {
            isSynchronizingSelection = true
            self.selectedItemID = batch.summary.items.first?.id
            isSynchronizingSelection = false
        }

        loadSelectedYAML()
    }
}
