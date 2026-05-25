import SwiftUI
import FigBridgeCore

struct ViewerPage: View {
    private enum DetailSection {
        case runLog
        case yaml
    }

    @ObservedObject var viewModel: ViewerViewModel
    @FocusState private var focusedRenamingBatchID: String?
    @FocusState private var focusedRenamingItemID: UUID?
    @State private var expandedSection: DetailSection = .runLog

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("批次")
                        .font(.title3.bold())
                    Spacer()
                    Menu {
                        Button("导入目录", systemImage: "folder.badge.plus") {
                            viewModel.importBatchDirectoryUsingPanel()
                        }
                        Button("导入 Zip", systemImage: "shippingbox") {
                            viewModel.importBatchZipUsingPanel()
                        }
                        Button("打开目录", systemImage: "folder") {
                            viewModel.openSelectedBatchInFinder()
                        }
                        Button("打开导出目录", systemImage: "folder.badge.gearshape") {
                            viewModel.openSelectedBatchExportsDirectoryInFinder()
                        }
                        Divider()
                        Button("重新扫描", systemImage: "arrow.clockwise") {
                            viewModel.reload()
                        }
                    } label: {
                        Label("批次操作", systemImage: "ellipsis.circle")
                            .labelStyle(.titleAndIcon)
                    }
                    .menuStyle(.borderlessButton)
                }
                List(selection: $viewModel.selectedBatchID) {
                    ForEach(viewModel.batches, id: \.summary.id) { batch in
                        VStack(alignment: .leading, spacing: 4) {
                            if viewModel.batchRename.identifier == batch.summary.id {
                                HStack(spacing: 8) {
                                    TextField("", text: $viewModel.batchRename.title)
                                        .textFieldStyle(.roundedBorder)
                                        .focused($focusedRenamingBatchID, equals: batch.summary.id)
                                        .onChange(of: focusedRenamingBatchID) { newValue in
                                            if viewModel.batchRename.identifier == batch.summary.id, newValue != batch.summary.id {
                                                viewModel.finishBatchRenameOnBlur()
                                            }
                                        }
                                    Button("取消编辑") {
                                        viewModel.cancelBatchRename()
                                    }
                                    .buttonStyle(.borderless)
                                }
                            } else {
                                Text(batch.summary.id)
                            }
                            Text("\(batch.summary.agent.displayName) · \(batch.summary.items.count) 项")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(batch.summary.id)
                        .contextMenu {
                            Button("修改批次名") {
                                viewModel.selectedBatchID = batch.summary.id
                                viewModel.beginRenamingBatch(batch.summary.id)
                            }
                            Button("导出批次") {
                                viewModel.selectedBatchID = batch.summary.id
                                viewModel.exportSelectedBatch()
                            }
                            Button("继续编辑") {
                                viewModel.selectedBatchID = batch.summary.id
                                viewModel.continueEditingBatch(batch.summary.id)
                            }
                            Button("打开目录") {
                                viewModel.selectedBatchID = batch.summary.id
                                viewModel.openSelectedBatchInFinder()
                            }
                            Button("打开导出目录") {
                                viewModel.selectedBatchID = batch.summary.id
                                viewModel.openSelectedBatchExportsDirectoryInFinder()
                            }
                            Divider()
                            Button("删除批次", role: .destructive) {
                                viewModel.selectedBatchID = batch.summary.id
                                viewModel.deleteSelectedBatch()
                            }
                        }
                    }
                }
                .onSubmit {
                    if viewModel.batchRename.isActive {
                        viewModel.commitBatchRename()
                    }
                }
                .onChange(of: viewModel.batchRename.identifier) { newValue in
                    focusedRenamingBatchID = newValue
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .frame(width: 280)

            VStack(alignment: .leading, spacing: 12) {
                if let batch = viewModel.selectedBatch {
                    Text("批次详情")
                        .font(.title3.bold())
                    Text("输出目录")
                        .font(.headline)
                    Text(viewModel.selectedBatchExportsDirectory?.path ?? batch.summary.outputDirectory)
                        .font(.caption)
                        .textSelection(.enabled)
                    Text("Prompt")
                        .font(.headline)
                    ScrollView {
                        Text(batch.summary.promptSnapshot)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    Text("条目")
                        .font(.headline)
                    List(batch.summary.items, selection: $viewModel.selectedItemID) { item in
                        HStack {
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
                            }
                            Spacer()
                            if item.generatedYAMLPath != nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                        .tag(item.id)
                        .contextMenu {
                            Button("修改") {
                                viewModel.selectedItemID = item.id
                                viewModel.beginRenamingItem(item.id)
                            }
                        }
                    }
                    .onSubmit {
                        if viewModel.itemRename.isActive {
                            viewModel.commitRename()
                        }
                    }
                    .onChange(of: viewModel.itemRename.identifier) { newValue in
                        focusedRenamingItemID = newValue
                    }
                    Button("Copy Prompt") {
                        viewModel.copyPrompt()
                    }
                    .disabled(!viewModel.canCopyPrompt)
                    Button("继续编辑") {
                        viewModel.continueEditingSelectedBatch()
                    }
                } else {
                    EmptyStateView(title: "暂无批次", systemImage: "archivebox")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .frame(width: 400)

            VStack(alignment: .leading, spacing: 12) {
                Text("条目详情")
                    .font(.title3.bold())
                if let item = viewModel.selectedItem {
                    Text(item.nodeName ?? item.title ?? item.nodeId)
                        .font(.headline)
                    Text("\(item.fileKey) / \(item.nodeId)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let previewImagePath = item.previewImagePath,
                       let image = NSImage(contentsOfFile: previewImagePath) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .onTapGesture(count: 2) {
                                viewModel.openSelectedPreviewImage()
                            }
                    }
                    if !item.resourceItems.isEmpty {
                        Text("资源")
                            .font(.headline)
                        List(item.resourceItems) { resource in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(resource.name)
                                Text(resource.localPath ?? resource.remoteURL ?? "")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        .frame(minHeight: 120, maxHeight: 180)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("", selection: $expandedSection) {
                            Text("运行日志").tag(DetailSection.runLog)
                            Text("DesignIR").tag(DetailSection.yaml)
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
                                                Text("Provider: \(runLog.providerKind.rawValue)")
                                                    .font(.caption2)
                                                if let model = runLog.model, !model.isEmpty {
                                                    Text("Model: \(model)")
                                                        .font(.caption2)
                                                        .textSelection(.enabled)
                                                }
                                                if let requestSummary = runLog.requestSummary, !requestSummary.isEmpty {
                                                    Text("请求: \(requestSummary)")
                                                        .font(.caption2)
                                                        .textSelection(.enabled)
                                                }
                                                if let errorMessage = runLog.errorMessage, !errorMessage.isEmpty {
                                                    Text("错误: \(errorMessage)")
                                                        .font(.caption2)
                                                        .foregroundStyle(.red)
                                                        .textSelection(.enabled)
                                                }
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
                                        Text("未找到 DesignIR")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                } else {
                    EmptyStateView(title: "未选择条目", systemImage: "doc.text")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            harmonyWorkflowColumn
                .frame(width: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            viewModel.reload()
        }
        .overlay(alignment: .bottomTrailing) {
            if !viewModel.message.isEmpty {
                Text(viewModel.message)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding()
            }
        }
    }

    private var harmonyWorkflowColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Harmony / ArkUI")
                .font(.title3.bold())

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Button {
                            viewModel.importDesignPackageDirectoryUsingPanel()
                        } label: {
                            Label("导入设计包目录", systemImage: "folder.badge.plus")
                        }
                        Button {
                            viewModel.importDesignPackageZipUsingPanel()
                        } label: {
                            Label("导入 Zip", systemImage: "shippingbox")
                        }
                    }

                    if let package = viewModel.importedDesignPackage {
                        packageSummary(package)
                        packagePreview
                        designTree
                        designIssues
                        targetProjectControls
                        generationReport
                    } else {
                        EmptyStateView(title: "未导入设计包", systemImage: "shippingbox")
                            .frame(minHeight: 240)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func packageSummary(_ package: PersistedDesignPackage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(package.design.screenName)
                .font(.headline)
            Text(package.manifest.packageID)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("\(package.design.fileKey) / \(package.design.nodeId)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text(package.packageDirectory.path)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var packagePreview: some View {
        if let previewURL = viewModel.importedDesignPackagePreviewURL,
           let image = NSImage(contentsOf: previewURL) {
            VStack(alignment: .leading, spacing: 6) {
                Text("预览")
                    .font(.headline)
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onTapGesture(count: 2) {
                        DesktopSupport.openFile(previewURL)
                    }
            }
        }
    }

    private var designTree: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DesignIR 树")
                .font(.headline)
            if viewModel.designTreeItems.isEmpty {
                Text("暂无节点")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView([.horizontal, .vertical]) {
                    OutlineGroup(viewModel.designTreeItems, children: \.children) { item in
                        HStack(spacing: 6) {
                            Text(item.title)
                            Text(item.subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if item.isNeedsReview {
                                Text("needsReview")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.orange)
                            }
                            if let badge = item.badge {
                                Text(badge)
                                    .font(.caption2.bold())
                                    .foregroundStyle(.red)
                            }
                        }
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 140, maxHeight: 220)
            }
        }
    }

    private var designIssues: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Warnings / Needs Review")
                .font(.headline)
            if viewModel.designIssues.isEmpty {
                Text("无 warnings 或 needsReview")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(viewModel.designIssues) { issue in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(issue.severity.rawValue)
                                .font(.caption2.bold())
                                .foregroundStyle(issue.severity == .needsReview ? .orange : .red)
                            Text(issue.nodePath)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            Text(issue.message)
                                .font(.caption)
                                .textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private var targetProjectControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("目标项目")
                .font(.headline)
            HStack {
                TextField("Harmony 项目目录", text: $viewModel.harmonyProjectPath)
                    .textFieldStyle(.roundedBorder)
                Button {
                    viewModel.selectHarmonyProjectDirectoryUsingPanel()
                } label: {
                    Label("选择目录", systemImage: "folder")
                        .labelStyle(.iconOnly)
                }
                .help("选择目录")
            }
            TextField("页面名", text: $viewModel.harmonyPageName)
                .textFieldStyle(.roundedBorder)
            Toggle("覆盖同名 .ets 和资源文件", isOn: $viewModel.harmonyOverwriteExistingFiles)
            Toggle("目标目录不存在时创建", isOn: $viewModel.harmonyCreateTargetDirectory)
            HStack {
                Button {
                    viewModel.generateHarmonyProject()
                } label: {
                    Label("生成 ArkUI", systemImage: "hammer")
                }
                .disabled(!viewModel.canGenerateHarmonyProject)

                Button {
                    viewModel.openHarmonyProjectInFinder()
                } label: {
                    Label("打开项目", systemImage: "folder")
                }
                .disabled(viewModel.harmonyProjectPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    @ViewBuilder
    private var generationReport: some View {
        if !viewModel.harmonyReportText.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("生成报告")
                        .font(.headline)
                    Spacer()
                    Button {
                        viewModel.openHarmonyReport()
                    } label: {
                        Label("打开报告", systemImage: "doc.text")
                            .labelStyle(.iconOnly)
                    }
                    .disabled(viewModel.harmonyReportPath == nil)
                    .help("打开报告")
                }
                if let reportPath = viewModel.harmonyReportPath {
                    Text(reportPath)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                ScrollView([.horizontal, .vertical]) {
                    Text(viewModel.harmonyReportText)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 160, maxHeight: 260)
            }
        }
    }

    private func viewerActionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .help(title)
        }
        .buttonStyle(.bordered)
    }
}
