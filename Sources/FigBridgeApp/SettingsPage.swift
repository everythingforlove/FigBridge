import SwiftUI
import FigBridgeCore

struct SettingsPage: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var tokenFieldVisible = false
    @State private var httpAPIKeyVisible = false

    var body: some View {
        Form {
            Section("Provider") {
                Picker("默认 Provider", selection: $viewModel.settings.selectedAgentID) {
                    Text("未选择").tag(String?.none)
                    ForEach(viewModel.settings.providerConfigurations) { provider in
                        Text(provider.displayName).tag(String?.some(provider.id))
                    }
                }
                .pickerStyle(.menu)

                if let index = viewModel.settings.providerConfigurations.firstIndex(where: { $0.kind == .openAICompatibleHTTP }) {
                    let provider = $viewModel.settings.providerConfigurations[index]
                    VStack(alignment: .leading, spacing: 10) {
                        Text("OpenAI-compatible HTTP")
                            .font(.headline)
                        TextField("Base URL，例如 https://api.example.com/v1", text: openAIHTTPStringBinding(provider, keyPath: \.baseURL))
                            .textFieldStyle(.roundedBorder)
                        HStack {
                            Group {
                                if httpAPIKeyVisible {
                                    TextField("API Key", text: openAIHTTPStringBinding(provider, keyPath: \.apiKey))
                                } else {
                                    SecureField("API Key", text: openAIHTTPStringBinding(provider, keyPath: \.apiKey))
                                }
                            }
                            .textFieldStyle(.roundedBorder)
                            .font(.body.monospaced())
                            Button(httpAPIKeyVisible ? "隐藏" : "显示") {
                                httpAPIKeyVisible.toggle()
                            }
                        }
                        TextField("Model", text: openAIHTTPStringBinding(provider, keyPath: \.model))
                            .textFieldStyle(.roundedBorder)
                        HStack {
                            Stepper(
                                "Timeout \(Int(provider.wrappedValue.openAICompatibleHTTP?.timeout ?? 300)) 秒",
                                value: openAIHTTPTimeoutBinding(provider),
                                in: 10...1800,
                                step: 10
                            )
                            Toggle("Streaming", isOn: openAIHTTPBoolBinding(provider, keyPath: \.streaming))
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Figma Token") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 12) {
                        Group {
                            if tokenFieldVisible {
                                TextField("", text: $viewModel.settings.figmaToken)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                SecureField("", text: $viewModel.settings.figmaToken)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                        .font(.body.monospaced())

                        Button(tokenFieldVisible ? "隐藏" : "显示") {
                            tokenFieldVisible.toggle()
                        }

                        Button {
                            Task {
                                await viewModel.testToken()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                if viewModel.isTestingToken {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                                Text(viewModel.isTestingToken ? "测试中..." : "测试 Token")
                            }
                        }
                        .disabled(viewModel.isTestingToken)

                        Button("说明") {
                            viewModel.isShowingTokenHelp = true
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("默认 Prompt")
                            .font(.headline)
                        Spacer()
                        Button("恢复默认 Prompt") {
                            viewModel.restoreDefaultPrompt()
                        }
                    }
                    TextEditor(text: $viewModel.settings.promptTemplate)
                        .font(.body.monospaced())
                        .frame(height: 180)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("预览图片格式")
                            .font(.headline)
                        Picker("", selection: $viewModel.settings.defaultExportFormat) {
                            Text("SVG").tag(ExportFormat.svg)
                            Text("PNG").tag(ExportFormat.png)
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            await viewModel.bootstrap()
        }
        .sheet(isPresented: $viewModel.isShowingTokenHelp) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Figma Token 获取方式")
                        .font(.title3.bold())
                    Spacer()
                    Button("关闭") {
                        viewModel.isShowingTokenHelp = false
                    }
                }
                ForEach(Array(SettingsViewModel.tokenHelpSteps.enumerated()), id: \.offset) { index, step in
                    Text("\(index + 1). \(step)")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Link("打开官方说明", destination: SettingsViewModel.tokenHelpURL)
                Spacer()
            }
            .padding(24)
            .frame(minWidth: 420, minHeight: 240, alignment: .topLeading)
        }
        .overlay(alignment: .bottomTrailing) {
            if !viewModel.toastMessage.isEmpty {
                Text(viewModel.toastMessage)
                    .foregroundStyle(viewModel.isToastError ? .red : .primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding()
            }
        }
    }

    private func openAIHTTPStringBinding(
        _ provider: Binding<AgentProvider>,
        keyPath: WritableKeyPath<OpenAICompatibleHTTPProviderConfig, String>
    ) -> Binding<String> {
        Binding {
            provider.wrappedValue.openAICompatibleHTTP?[keyPath: keyPath] ?? ""
        } set: { newValue in
            var value = provider.wrappedValue
            var config = value.openAICompatibleHTTP ?? OpenAICompatibleHTTPProviderConfig()
            config[keyPath: keyPath] = newValue
            value.openAICompatibleHTTP = config
            provider.wrappedValue = value
        }
    }

    private func openAIHTTPBoolBinding(
        _ provider: Binding<AgentProvider>,
        keyPath: WritableKeyPath<OpenAICompatibleHTTPProviderConfig, Bool>
    ) -> Binding<Bool> {
        Binding {
            provider.wrappedValue.openAICompatibleHTTP?[keyPath: keyPath] ?? false
        } set: { newValue in
            var value = provider.wrappedValue
            var config = value.openAICompatibleHTTP ?? OpenAICompatibleHTTPProviderConfig()
            config[keyPath: keyPath] = newValue
            value.openAICompatibleHTTP = config
            provider.wrappedValue = value
        }
    }

    private func openAIHTTPTimeoutBinding(_ provider: Binding<AgentProvider>) -> Binding<Double> {
        Binding {
            provider.wrappedValue.openAICompatibleHTTP?.timeout ?? 300
        } set: { newValue in
            var value = provider.wrappedValue
            var config = value.openAICompatibleHTTP ?? OpenAICompatibleHTTPProviderConfig()
            config.timeout = newValue
            value.openAICompatibleHTTP = config
            provider.wrappedValue = value
        }
    }
}
