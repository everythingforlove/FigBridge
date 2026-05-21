import Foundation

public enum AgentServiceError: LocalizedError {
    case executableNotFound(String)
    case executionFailed(String)
    case emptyOutput
    case executionTimedOut(TimeInterval)
    case invalidProviderConfiguration(String)
    case invalidHTTPResponse(Int, String)

    public var errorDescription: String? {
        switch self {
        case .executableNotFound(let name):
            "未找到可执行 agent: \(name)"
        case .executionFailed(let message):
            message
        case .emptyOutput:
            "agent 输出为空"
        case .executionTimedOut(let seconds):
            "agent 执行超时（\(Int(seconds)) 秒）"
        case .invalidProviderConfiguration(let message):
            message
        case .invalidHTTPResponse(let status, let body):
            "HTTP provider 请求失败（\(status)）：\(body)"
        }
    }
}

public struct AgentRunResult: Sendable {
    public let output: String
    public let executablePath: String
    public let arguments: [String]
    public let exitCode: Int32
    public let stderr: String
    public let providerKind: AgentProviderKind
    public let model: String?
    public let requestSummary: String

    public init(
        output: String,
        executablePath: String,
        arguments: [String],
        exitCode: Int32 = 0,
        stderr: String = "",
        providerKind: AgentProviderKind = .claudeCLI,
        model: String? = nil,
        requestSummary: String = ""
    ) {
        self.output = output
        self.executablePath = executablePath
        self.arguments = arguments
        self.exitCode = exitCode
        self.stderr = stderr
        self.providerKind = providerKind
        self.model = model
        self.requestSummary = requestSummary
    }
}

public protocol AgentHTTPTransport: Sendable {
    func data(for request: URLRequest, timeout: TimeInterval) async throws -> (Data, HTTPURLResponse)
    func bytes(for request: URLRequest, timeout: TimeInterval) async throws -> (URLSession.AsyncBytes, URLResponse)
}

public struct URLSessionAgentHTTPTransport: AgentHTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest, timeout: TimeInterval) async throws -> (Data, HTTPURLResponse) {
        var request = request
        request.timeoutInterval = timeout
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AgentServiceError.executionFailed("HTTP provider 未返回有效响应")
        }
        return (data, httpResponse)
    }

    public func bytes(for request: URLRequest, timeout: TimeInterval) async throws -> (URLSession.AsyncBytes, URLResponse) {
        var request = request
        request.timeoutInterval = timeout
        return try await session.bytes(for: request)
    }
}

public struct AgentService: Sendable {
    public let shellClient: ShellClient
    public let executionTimeout: TimeInterval
    public let httpTransport: any AgentHTTPTransport

    public init(
        shellClient: ShellClient = ShellClient(),
        executionTimeout: TimeInterval = 300,
        httpTransport: any AgentHTTPTransport = URLSessionAgentHTTPTransport()
    ) {
        self.shellClient = shellClient
        self.executionTimeout = executionTimeout
        self.httpTransport = httpTransport
    }

    public func detectAvailableAgents() async throws -> [AgentDescriptor] {
        var agents: [AgentDescriptor] = []
        for provider in AgentProvider.allCases {
            if let descriptor = try await detect(provider: provider) {
                agents.append(descriptor)
            }
        }
        return agents
    }

    public func detect(provider: AgentProvider) async throws -> AgentDescriptor? {
        guard provider.kind != .openAICompatibleHTTP else {
            guard let config = provider.openAICompatibleHTTP, config.isConfigured else {
                return nil
            }
            return AgentDescriptor(provider: provider, path: config.baseURL, version: config.model)
        }

        let name = provider.rawValue
        guard let path = shellClient.resolveExecutable(named: name) else {
            return nil
        }

        let versionResult = try await shellClient.run(executable: path, arguments: ["--version"])
        let version = versionResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        return AgentDescriptor(provider: provider, path: path.path, version: version)
    }

    public func run(provider: AgentProvider, prompt: String) async throws -> String {
        try await runDetailed(provider: provider, prompt: prompt).output
    }

    public func runDetailed(
        provider: AgentProvider,
        prompt: String,
        eventHandler: (@Sendable (AgentRunEvent) async -> Void)? = nil
    ) async throws -> AgentRunResult {
        if provider.kind == .openAICompatibleHTTP {
            return try await runOpenAICompatibleHTTP(provider: provider, prompt: prompt, eventHandler: eventHandler)
        }

        let arguments: [String]
        switch provider.kind {
        case .claudeCLI:
            arguments = ["-p", prompt]
        case .codexCLI:
            arguments = ["exec", "--skip-git-repo-check", prompt]
        case .openAICompatibleHTTP:
            arguments = []
        }

        guard let executable = shellClient.resolveExecutable(named: provider.rawValue) else {
            throw AgentServiceError.executableNotFound(provider.rawValue)
        }

        if let eventHandler {
            await eventHandler(.metadata(providerKind: provider.kind, model: provider.modelName, requestSummary: requestSummary(provider: provider, prompt: prompt)))
            await eventHandler(.started(executablePath: executable.path, arguments: arguments, isSharedLog: false))
        }

        let result: ShellResult
        do {
            result = try await shellClient.runStreaming(executable: executable, arguments: arguments, timeout: executionTimeout) { event in
                guard let eventHandler else {
                    return
                }
                switch event {
                case .started:
                    break
                case .stdout(let text):
                    await eventHandler(.stdout(text))
                case .stderr(let text):
                    await eventHandler(.stderr(text))
                case .finished(let status):
                    await eventHandler(.finished(exitCode: status))
                }
            }
        } catch is CancellationError {
            if let eventHandler {
                await eventHandler(.cancelled)
            }
            throw CancellationError()
        }

        if result.status == SIGTERM {
            if let eventHandler {
                await eventHandler(.failed(message: AgentServiceError.executionTimedOut(executionTimeout).localizedDescription))
            }
            throw AgentServiceError.executionTimedOut(executionTimeout)
        }
        guard result.status == 0 else {
            if let eventHandler {
                await eventHandler(.failed(message: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
            throw AgentServiceError.executionFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else {
            throw AgentServiceError.emptyOutput
        }
        return AgentRunResult(
            output: output,
            executablePath: executable.path,
            arguments: arguments,
            exitCode: result.status,
            stderr: result.stderr,
            providerKind: provider.kind,
            model: provider.modelName,
            requestSummary: requestSummary(provider: provider, prompt: prompt)
        )
    }

    private func runOpenAICompatibleHTTP(
        provider: AgentProvider,
        prompt: String,
        eventHandler: (@Sendable (AgentRunEvent) async -> Void)?
    ) async throws -> AgentRunResult {
        guard let config = provider.openAICompatibleHTTP else {
            throw AgentServiceError.invalidProviderConfiguration("HTTP provider 未配置")
        }
        let baseURLText = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = config.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: baseURLText), !model.isEmpty else {
            throw AgentServiceError.invalidProviderConfiguration("HTTP provider 需要 baseURL 和 model")
        }

        let endpoint = url.path.hasSuffix("/chat/completions") ? url : url.appendingPathComponent("chat/completions")
        let summary = requestSummary(provider: provider, prompt: prompt)
        if let eventHandler {
            await eventHandler(.metadata(providerKind: provider.kind, model: model, requestSummary: summary))
            await eventHandler(.started(executablePath: endpoint.absoluteString, arguments: ["model=\(model)", "stream=\(config.streaming)"], isSharedLog: false))
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(OpenAIChatCompletionsRequest(
            model: model,
            messages: [OpenAIChatMessage(role: "user", content: prompt)],
            stream: config.streaming
        ))

        let output: String
        if config.streaming {
            output = try await performStreamingHTTPRequest(request, timeout: config.timeout, eventHandler: eventHandler)
        } else {
            output = try await performJSONHTTPRequest(request, timeout: config.timeout)
            if let eventHandler {
                await eventHandler(.stdout(output))
            }
        }

        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentServiceError.emptyOutput
        }
        if let eventHandler {
            await eventHandler(.finished(exitCode: 0))
        }
        return AgentRunResult(
            output: output.trimmingCharacters(in: .whitespacesAndNewlines),
            executablePath: endpoint.absoluteString,
            arguments: ["model=\(model)", "stream=\(config.streaming)"],
            providerKind: provider.kind,
            model: model,
            requestSummary: summary
        )
    }

    private func performJSONHTTPRequest(_ request: URLRequest, timeout: TimeInterval) async throws -> String {
        let (data, response) = try await httpTransport.data(for: request, timeout: timeout)
        guard (200..<300).contains(response.statusCode) else {
            throw AgentServiceError.invalidHTTPResponse(response.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        let responseBody = try JSONDecoder().decode(OpenAIChatCompletionsResponse.self, from: data)
        return responseBody.choices.first?.message?.content ?? responseBody.choices.first?.text ?? ""
    }

    private func performStreamingHTTPRequest(
        _ request: URLRequest,
        timeout: TimeInterval,
        eventHandler: (@Sendable (AgentRunEvent) async -> Void)?
    ) async throws -> String {
        let (bytes, response) = try await httpTransport.bytes(for: request, timeout: timeout)
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw AgentServiceError.invalidHTTPResponse(httpResponse.statusCode, "")
        }
        var output = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else {
                continue
            }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
            guard payload != "[DONE]", let data = payload.data(using: .utf8) else {
                continue
            }
            let chunk = try JSONDecoder().decode(OpenAIChatCompletionsStreamChunk.self, from: data)
            let text = chunk.choices.compactMap(\.delta.content).joined()
            guard !text.isEmpty else {
                continue
            }
            output += text
            if let eventHandler {
                await eventHandler(.stdout(text))
            }
        }
        return output
    }

    private func requestSummary(provider: AgentProvider, prompt: String) -> String {
        let promptLength = prompt.count
        switch provider.kind {
        case .claudeCLI, .codexCLI:
            return "\(provider.kind.rawValue) target=\(provider.rawValue) promptChars=\(promptLength)"
        case .openAICompatibleHTTP:
            let model = provider.openAICompatibleHTTP?.model ?? ""
            return "\(provider.kind.rawValue) model=\(model) promptChars=\(promptLength) streaming=\(provider.openAICompatibleHTTP?.streaming ?? false)"
        }
    }
}

private struct OpenAIChatCompletionsRequest: Encodable {
    var model: String
    var messages: [OpenAIChatMessage]
    var stream: Bool
}

private struct OpenAIChatMessage: Codable {
    var role: String
    var content: String
}

private struct OpenAIChatCompletionsResponse: Decodable {
    var choices: [Choice]

    struct Choice: Decodable {
        var message: OpenAIChatMessage?
        var text: String?
    }
}

private struct OpenAIChatCompletionsStreamChunk: Decodable {
    var choices: [Choice]

    struct Choice: Decodable {
        var delta: Delta
    }

    struct Delta: Decodable {
        var content: String?
    }
}
