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
                    EmptyStateView(title: "未选择条目", systemImage: "doc.text")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    private func viewerActionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .help(title)
        }
        .buttonStyle(.bordered)
    }
}
