import SwiftUI
import FigBridgeCore

struct GeneratePage: View {
    private enum DetailSection {
        case runLog
        case yaml
    }

    private enum HelpSection: String, CaseIterable, Identifiable {
        case agent
        case figmaMCP
        case figmaToken
        case runtime
        case modeAndStrategy
        case importExport

        var id: String { rawValue }

        var title: String {
            switch self {
            case .agent:
                "1. agent 说明"
            case .figmaMCP:
                "2. figma mcp 说明"
            case .figmaToken:
                "3. figma token 设置说明（结合预览和资源）"
            case .runtime:
                "4. 运行原理说明"
            case .modeAndStrategy:
                "5. 模式、调用策略说明"
            case .importExport:
                "6. 导入导出功能"
            }
        }
    }

    @ObservedObject var viewModel: GenerateViewModel
    @FocusState private var focusedRenamingItemID: UUID?
    @State private var expandedSection: DetailSection = .runLog
    @State private var isShowingHelpSheet: Bool = false
    @State private var expandedHelpSection: HelpSection? = .agent
    @State private var isShowingNewBatchConfirmation: Bool = false

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("工作台")
                        .font(.title2.bold())
                    Spacer()
                    Button("帮助") {
                        isShowingHelpSheet = true
                    }
                }
                HStack(alignment: .center, spacing: 8) {
                    Picker("Agent", selection: $viewModel.selectedAgentID) {
                        Text("未选择").tag(String?.none)
                        ForEach(viewModel.availableAgents) { agent in
                            Text(agent.provider.displayName).tag(String?.some(agent.id))
                        }
                    }
                    Button {
                        Task {
                            await viewModel.refreshAgents()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if viewModel.isRefreshingAgents {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(viewModel.isRefreshingAgents ? "刷新中..." : "刷新")
                        }
                    }
                    .disabled(viewModel.isRefreshingAgents)
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Prompt")
                            .font(.headline)
                        Spacer()
                        Button("同步默认 Prompt") {
                            viewModel.syncPromptFromSettings()
                        }
                        .padding(.trailing, 6)
                    }
                    TextEditor(text: $viewModel.promptTemplate)
                        .font(.body.monospaced())
                        .frame(minHeight: 140)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("输出目录")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(viewModel.outputDirectoryPath)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                Picker("模式", selection: $viewModel.mode) {
                    Text("逐个").tag(GenerationMode.sequential)
                    Text("并发").tag(GenerationMode.parallel)
                }
                Picker("调用策略", selection: $viewModel.callStrategy) {
                    Text(AgentCallStrategy.singlePerLink.displayName).tag(AgentCallStrategy.singlePerLink)
                    Text(AgentCallStrategy.singleForBatch.displayName).tag(AgentCallStrategy.singleForBatch)
                }
                Stepper("并发数 \(viewModel.parallelism)", value: $viewModel.parallelism, in: 1...8)
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $viewModel.inputText)
                        .font(.body.monospaced())
                        .frame(minHeight: 240)
                    if viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("请输入要添加的信息")
                            .font(.body.monospaced())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
                HStack {
                    Button("添加") {
                        viewModel.addInput()
                    }
                    Button("新建批次") {
                        if viewModel.isGenerating {
                            isShowingNewBatchConfirmation = true
                        } else {
                            viewModel.startNewBatch()
                        }
                    }
                    Button("生成") {
                        Task {
                            await viewModel.generate()
                        }
                    }
                    .disabled(!viewModel.canGenerate)
                    if viewModel.isGenerating {
                        Button("取消") {
                            viewModel.cancelGeneration()
                        }
                    }
                }
                if viewModel.isGenerating {
                    ProgressView(value: Double(viewModel.completedCount), total: Double(max(viewModel.pendingItems.count, 1)))
                    Text(viewModel.progressText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !viewModel.validationMessage.isEmpty {
                    Text(viewModel.validationMessage)
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .frame(minWidth: 360)

            VStack(alignment: .leading, spacing: 12) {
                itemSection(title: "待处理链接", items: viewModel.pendingItems, showsGeneratedState: false)
                itemSection(title: "已处理链接", items: viewModel.processedItems, showsGeneratedState: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .frame(minWidth: 320)
            .onSubmit {
                if viewModel.itemRename.isActive {
                    viewModel.commitRename()
                }
            }
            .onChange(of: viewModel.itemRename.identifier) { newValue in
                focusedRenamingItemID = newValue
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("详情")
                    .font(.title3.bold())
                if let item = viewModel.selectedItem {
                    Text(item.nodeName ?? item.title ?? item.nodeId)
                        .font(.headline)
                    Text(item.url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("预览状态: \(item.previewStatus.rawValue)")
                    Text("资源状态: \(viewModel.selectedItemResourceStatusText)")
                        .foregroundStyle(viewModel.shouldHighlightSelectedItemResourceStatus ? .red : .primary)
                    Text("生成状态: \(viewModel.selectedItemGenerationStatusText)")
                        .foregroundStyle(viewModel.shouldHighlightSelectedItemGenerationStatus ? .red : .primary)
                    if let previewImagePath = item.previewImagePath,
                       let image = NSImage(contentsOfFile: previewImagePath) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .onTapGesture(count: 2) {
                                viewModel.openSelectedPreviewImage()
                            }
                    }
                    if let errorMessage = item.errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                    Divider()
                    if !item.resourceItems.isEmpty {
                        List(item.resourceItems) { resource in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(resource.name)
                                    Text(resource.format.rawValue.uppercased())
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("导出") {
                                    viewModel.exportResource(resource)
                                }
                            }
                        }
                        HStack {
                            if item.previewImagePath != nil {
                                Button("导出预览图") {
                                    viewModel.exportPreviewImage()
                                }
                            }
                            Button("导出全部资源") {
                                viewModel.exportAllResources()
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("", selection: $expandedSection) {
                            Text("运行日志").tag(DetailSection.runLog)
                            Text("YAML").tag(DetailSection.yaml)
                        }
                        .pickerStyle(.segmented)
                        Group {
                            if expandedSection == .runLog {
                                if let runLog = viewModel.selectedRunLog {
                                    VStack(alignment: .leading, spacing: 8) {
                                        if runLog.isShared {
                                            Text("批量单次调用共享日志")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        ScrollView([.horizontal, .vertical]) {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text("状态: \(runLog.status.rawValue)")
                                                    .font(.caption)
                                                if let executablePath = runLog.executablePath {
                                                    Text("执行文件: \(executablePath)")
                                                        .font(.caption2)
                                                        .textSelection(.enabled)
                                                }
                                                if !runLog.arguments.isEmpty {
                                                    Text("参数: \(runLog.arguments.joined(separator: " "))")
                                                        .font(.caption2)
                                                        .textSelection(.enabled)
                                                }
                                                if let exitCode = runLog.exitCode {
                                                    Text("退出码: \(exitCode)")
                                                        .font(.caption2)
                                                }
                                            }
                                            .fixedSize(horizontal: true, vertical: false)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .frame(minHeight: 44, maxHeight: 110)
                                        ScrollView([.horizontal, .vertical]) {
                                            Text(viewModel.selectedRunLogText.isEmpty ? "暂无运行日志" : viewModel.selectedRunLogText)
                                                .font(.body.monospaced())
                                                .textSelection(.enabled)
                                                .lineLimit(1_000_000)
                                                .fixedSize(horizontal: true, vertical: true)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                    }
                                } else {
                                    Text("暂无运行日志")
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    if let yamlPath = item.generatedYAMLPath {
                                        Text(yamlPath)
                                            .font(.caption)
                                            .textSelection(.enabled)
                                    }
                                    if let yamlText = viewModel.selectedYAMLText {
                                        ScrollView([.horizontal, .vertical]) {
                                            Text(yamlText)
                                                .font(.body.monospaced())
                                                .textSelection(.enabled)
                                                .lineLimit(1_000_000)
                                                .fixedSize(horizontal: true, vertical: true)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                    } else {
                                        Text("未找到 YAML")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                } else {
                    EmptyStateView(title: "未选择条目", systemImage: "sidebar.right")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .frame(minWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .bottomTrailing) {
            if !viewModel.exportMessage.isEmpty {
                Text(viewModel.exportMessage)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding()
            }
        }
        .task {
            await viewModel.bootstrap()
        }
        .sheet(isPresented: $isShowingHelpSheet) {
            helpSheet
        }
        .alert("当前正在生成", isPresented: $isShowingNewBatchConfirmation) {
            Button("取消生成并新建", role: .destructive) {
                viewModel.startNewBatch()
            }
            Button("继续生成", role: .cancel) {}
        } message: {
            Text("新建批次将取消当前生成任务并清空当前工作区，是否继续？")
        }
    }

    private var helpSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("工作台帮助")
                    .font(.title3.bold())
                Spacer()
                Button("关闭") {
                    isShowingHelpSheet = false
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(HelpSection.allCases) { section in
                        helpSectionCard(section)
                    }
                }
            }
        }
        .padding(24)
        .frame(minWidth: 700, minHeight: 520, alignment: .topLeading)
    }

    @ViewBuilder
    private func helpSectionCard(_ section: HelpSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                expandedHelpSection = expandedHelpSection == section ? nil : section
            } label: {
                HStack {
                    Text(section.title)
                        .font(.headline)
                    Spacer()
                    Image(systemName: expandedHelpSection == section ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expandedHelpSection == section {
                Text(helpContent(for: section))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func helpContent(for section: HelpSection) -> String {
        switch section {
        case .agent:
            """
            工作台会检测本机可用的 Agent（当前支持 Claude / Codex）。你可以在上方 Agent 下拉中切换调用对象，再点击“刷新”重新检测。
            生成前至少需要：选中一个 Agent、有可用 Prompt、并且待处理列表里有链接。
            """
        case .figmaMCP:
            """
            这里的 figma mcp 可以理解为应用访问 Figma 数据与资源的通道：会基于链接中的 fileKey/nodeId 拉取节点信息、预览图与资源地址，再缓存到本地批次。
            选中条目后会触发懒加载，右侧“详情”会显示预览状态、资源状态和具体资源列表。
            """
        case .figmaToken:
            """
            请先到“设置”页填写并测试 Figma Token。Token 可用时，工作台才能稳定拉取节点预览图和资源文件。
            如果 Token 未设置或不可用，详情中的资源状态/生成状态会提示 token 未设置，预览和资源加载会受影响。
            设置页支持“测试 Token”和官方说明入口，建议先测试通过再执行批量生成。
            """
        case .runtime:
            """
            运行链路：
            1) 在工作台输入多行信息并添加，应用会解析 Figma design 链接并按 fileKey + nodeId 去重。
            2) 选中条目时拉取节点预览与资源元数据。
            3) 点击“生成”后由协调器按当前模式和策略调用 Agent 生成 YAML。
            4) 结果写入当前批次目录（含批次元数据、YAML 与相关导出内容），可在“查看”页继续管理。
            """
        case .modeAndStrategy:
            """
            模式：
            - 逐个：按顺序处理待生成条目。
            - 并发：同时处理多个条目，可通过“并发数”控制并行度。

            调用策略：
            - 单链接调用：每个链接单独调用一次 Agent。
            - 多链接单次调用：一个批次内尽量合并为一次调用，条目共享同一运行日志。
            """
        case .importExport:
            """
            工作台支持条目级资源导出：导出预览图、单个资源、全部资源。
            批次级导入导出在“查看”页：可导入目录、导入 Zip、导出批次 Zip，并可打开批次目录或导出目录继续处理。
            """
        }
    }

    @ViewBuilder
    private func itemSection(title: String, items: [FigmaLinkItem], showsGeneratedState: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(title) (\(items.count))")
                    .font(.title3.bold())
                Spacer()
            }
            List(items, selection: $viewModel.selectedItemID) { item in
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        if viewModel.itemRename.identifier == item.id {
                            HStack(spacing: 8) {
                                TextField("", text: $viewModel.itemRename.title)
                                    .textFieldStyle(.roundedBorder)
                                    .focused($focusedRenamingItemID, equals: item.id)
                                    .onChange(of: focusedRenamingItemID) { newValue in
                                        if viewModel.itemRename.identifier == item.id, newValue != item.id {
                                            viewModel.finishRenameOnBlur()
                                        }
                                    }
                                Button("取消编辑") {
                                    viewModel.cancelRename()
                                }
                                .buttonStyle(.borderless)
                            }
                        } else {
                            Text(item.title ?? item.nodeName ?? item.nodeId)
                                .font(.headline)
                        }
                        Text("\(item.fileKey) / \(item.nodeId)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(item.generationStatus.rawValue)
                            .font(.caption)
                        Text("资源: \(viewModel.canRefreshResources(for: item) && item.resourceStatus != .failed ? "token 未设置" : item.resourceStatus.rawValue)")
                            .font(.caption2)
                            .foregroundStyle(viewModel.canRefreshResources(for: item) ? .red : .secondary)
                        if viewModel.canRefreshResources(for: item) {
                            if let errorMessage = item.errorMessage, !errorMessage.isEmpty {
                                Text(errorMessage)
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                                    .lineLimit(2)
                            }
                        }
                        if showsGeneratedState {
                            Text("YAML 已生成")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if let logSummary = item.logSummary {
                            Text(logSummary)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 8) {
                        if viewModel.canRefreshResources(for: item) {
                            itemActionButton(
                                "刷新",
                                systemImage: "arrow.clockwise",
                                role: .none
                            ) {
                                viewModel.reloadResources(for: item.id)
                            }
                        }
                        itemActionButton(
                            "删除",
                            systemImage: "trash",
                            role: .destructive
                        ) {
                            viewModel.deleteItem(id: item.id)
                        }
                    }
                }
                .tag(item.id)
                .contextMenu {
                    Button("修改") {
                        viewModel.selectedItemID = item.id
                        viewModel.beginRenamingItem(item.id)
                    }
                    if viewModel.canRefreshResources(for: item) {
                        Button("刷新资源") {
                            viewModel.selectedItemID = item.id
                            viewModel.reloadResources(for: item.id)
                        }
                    }
                    Divider()
                    Button("删除", role: .destructive) {
                        viewModel.selectedItemID = item.id
                        viewModel.deleteItem(id: item.id)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func itemActionButton(
        _ title: String,
        systemImage: String,
        role: ButtonRole?,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.bold())
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(minWidth: 72)
        }
        .buttonStyle(.plain)
        .foregroundStyle(role == .destructive ? .red : .primary)
        .background(
            role == .destructive
            ? Color.red.opacity(0.10)
            : Color.secondary.opacity(0.10),
            in: Capsule()
        )
        .overlay {
            Capsule()
                .stroke(
                    role == .destructive
                    ? Color.red.opacity(0.22)
                    : Color.secondary.opacity(0.18),
                    lineWidth: 1
                )
        }
    }
}
