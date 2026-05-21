import Foundation
import Testing
@testable import FigBridgeCore


struct AgentServiceTests {
    @Test func detectsAvailableAgentsAndReadsVersion() async throws {
        let fileManager = FileManager.default
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let claudePath = sandbox.root.appendingPathComponent("claude")
        let codexPath = sandbox.root.appendingPathComponent("codex")
        try makeExecutable(at: claudePath, body: "#!/bin/sh\nif [ \"$1\" = \"--version\" ]; then\n  echo \"claude 1.0.0\"\nelse\n  echo \"$2\"\nfi\n")
        try makeExecutable(at: codexPath, body: "#!/bin/sh\nif [ \"$1\" = \"--version\" ]; then\n  echo \"codex 2.0.0\"\nelse\n  echo \"$2\"\nfi\n")
        #expect(fileManager.fileExists(atPath: claudePath.path))

        let shell = ShellClient(pathLookupDirectories: [sandbox.root], environment: [:])
        let service = AgentService(shellClient: shell)

        let agents = try await service.detectAvailableAgents()

        #expect(agents.count == 2)
        #expect(agents.first(where: { $0.provider == .claude })?.version == "claude 1.0.0")
        #expect(agents.first(where: { $0.provider == .codex })?.version == "codex 2.0.0")
    }

    @Test func ignoresMissingCustomLookupDirectories() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let shell = ShellClient(pathLookupDirectories: [sandbox.root], environment: [:])
        let resolved = shell.resolveExecutable(named: "definitely-missing-agent")

        #expect(resolved == nil)
    }

    @Test func detectsAgentsFromFallbackHomeBinDirectories() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let homeDirectory = sandbox.root.appendingPathComponent("home", isDirectory: true)
        let fallbackDirectory = homeDirectory.appendingPathComponent(".superconductor/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: fallbackDirectory, withIntermediateDirectories: true)

        let claudePath = fallbackDirectory.appendingPathComponent("claude")
        let codexPath = fallbackDirectory.appendingPathComponent("codex")
        try makeExecutable(at: claudePath, body: "#!/bin/sh\nif [ \"$1\" = \"--version\" ]; then\n  echo \"claude 9.9.9\"\nfi\n")
        try makeExecutable(at: codexPath, body: "#!/bin/sh\nif [ \"$1\" = \"--version\" ]; then\n  echo \"codex 8.8.8\"\nfi\n")

        let shell = ShellClient(pathLookupDirectories: [], environment: ["HOME": homeDirectory.path, "PATH": "/usr/bin:/bin"])
        let service = AgentService(shellClient: shell)

        let agents = try await service.detectAvailableAgents()

        #expect(agents.count == 2)
        #expect(agents.first(where: { $0.provider == .claude })?.path == claudePath.path)
        #expect(agents.first(where: { $0.provider == .codex })?.path == codexPath.path)
    }

    @Test func runsClaudeAndCodexWithExpectedArguments() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let claudePath = sandbox.root.appendingPathComponent("claude")
        let codexPath = sandbox.root.appendingPathComponent("codex")
        try makeExecutable(at: claudePath, body: "#!/bin/sh\nif [ \"$1\" = \"--version\" ]; then\n  echo \"claude 1.0.0\"\nelif [ \"$1\" = \"-p\" ]; then\n  echo \"$2\"\nelse\n  exit 1\nfi\n")
        try makeExecutable(at: codexPath, body: "#!/bin/sh\nif [ \"$1\" = \"--version\" ]; then\n  echo \"codex 2.0.0\"\nelif [ \"$1\" = \"exec\" ]; then\n  echo \"$3\"\nelse\n  exit 1\nfi\n")

        let shell = ShellClient(pathLookupDirectories: [sandbox.root], environment: [:])
        let service = AgentService(shellClient: shell)

        let claudeOutput = try await service.run(provider: .claude, prompt: "hello")
        let codexOutput = try await service.run(provider: .codex, prompt: "world")

        #expect(claudeOutput == "hello")
        #expect(codexOutput == "world")
    }

    @Test func runUsesExpandedPathForWrapperDependencies() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let homeDirectory = sandbox.root.appendingPathComponent("home", isDirectory: true)
        let wrapperDirectory = homeDirectory.appendingPathComponent(".superconductor/bin", isDirectory: true)
        let nodeDirectory = homeDirectory.appendingPathComponent(".local/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: wrapperDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nodeDirectory, withIntermediateDirectories: true)

        let nodePath = nodeDirectory.appendingPathComponent("node")
        try makeExecutable(at: nodePath, body: "#!/bin/sh\necho \"fake node\"\n")

        let claudePath = wrapperDirectory.appendingPathComponent("claude")
        try makeExecutable(
            at: claudePath,
            body: """
            #!/bin/sh
            if [ "$1" = "--version" ]; then
              echo "claude wrapper"
              exit 0
            fi
            env node >/dev/null 2>&1 || { echo "env: node: No such file or directory" >&2; exit 127; }
            echo "$2"
            """
        )

        let shell = ShellClient(
            pathLookupDirectories: [],
            environment: [
                "HOME": homeDirectory.path,
                "PATH": "/usr/bin:/bin"
            ]
        )
        let service = AgentService(shellClient: shell)

        let output = try await service.run(provider: .claude, prompt: "hello with node")

        #expect(output == "hello with node")
    }

    @Test func runsOpenAICompatibleHTTPProviderWithMockTransport() async throws {
        let transport = MockAgentHTTPTransport(responseBody: """
        {
          "choices": [
            {
              "message": {
                "role": "assistant",
                "content": "\(makeAgentDesignIRJSON(fileKey: "FILE1", nodeId: "1:2").replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\"", with: "\\\""))"
              }
            }
          ]
        }
        """)
        let provider = AgentProvider(
            id: "mock-http",
            kind: .openAICompatibleHTTP,
            displayNameOverride: "Mock HTTP",
            openAICompatibleHTTP: OpenAICompatibleHTTPProviderConfig(
                baseURL: "https://mock.example/v1",
                apiKey: "test-key",
                model: "mock-model",
                timeout: 42,
                streaming: false
            )
        )
        let service = AgentService(httpTransport: transport)
        let recorder = AgentRunEventRecorder()

        let output = try await service.runDetailed(provider: provider, prompt: "hello http") { event in
            await recorder.append(event)
        }

        let request = try #require(transport.recordedRequest)
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        let events = await recorder.events()
        #expect(request.url?.absoluteString == "https://mock.example/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
        #expect(body.contains("\"model\":\"mock-model\""))
        #expect(body.contains("hello http"))
        #expect(output.providerKind == .openAICompatibleHTTP)
        #expect(output.model == "mock-model")
        #expect(output.requestSummary.contains("promptChars=10"))
        #expect(events.contains { if case .metadata(.openAICompatibleHTTP, "mock-model", let summary) = $0 { return summary.contains("mock-model") } else { return false } })
        #expect(output.output.contains("\"fileKey\": \"FILE1\""))
    }

    @Test func streamsShellOutputEventsBeforeCompletion() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let scriptPath = sandbox.root.appendingPathComponent("stream-agent")
        try makeExecutable(
            at: scriptPath,
            body: """
            #!/bin/sh
            printf 'out-1\\n'
            printf 'err-1\\n' >&2
            sleep 0.1
            printf 'out-2\\n'
            printf 'err-2\\n' >&2
            """
        )

        let shell = ShellClient(pathLookupDirectories: [sandbox.root], environment: [:])
        let recorder = ShellEventRecorder()

        let result = try await shell.runStreaming(executable: scriptPath, arguments: []) { event in
            await recorder.append(event)
        }
        let events = await recorder.events()

        #expect(result.status == 0)
        #expect(result.stdout.contains("out-1"))
        #expect(result.stdout.contains("out-2"))
        #expect(result.stderr.contains("err-1"))
        #expect(result.stderr.contains("err-2"))
        #expect(events.contains { event in
            if case .stdout(let text) = event { return text.contains("out-1") }
            return false
        })
        #expect(events.contains { event in
            if case .stderr(let text) = event { return text.contains("err-1") }
            return false
        })
        #expect(events.contains { event in
            if case .started(let pid) = event { return pid > 0 }
            return false
        })
        #expect(events.contains(.finished(status: 0)))
    }

    @Test func timesOutLongRunningAgentProcess() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let claudePath = sandbox.root.appendingPathComponent("claude")
        try makeExecutable(
            at: claudePath,
            body: """
            #!/bin/sh
            sleep 5
            echo "$2"
            """
        )

        let shell = ShellClient(pathLookupDirectories: [sandbox.root], environment: [:])
        let service = AgentService(shellClient: shell, executionTimeout: 0.1)

        await #expect(throws: AgentServiceError.self) {
            _ = try await service.run(provider: .claude, prompt: "hello")
        }
    }

    @Test func runStreamingClosesStandardInputSoProcessCanFinish() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let scriptPath = sandbox.root.appendingPathComponent("stdin-agent")
        try makeExecutable(
            at: scriptPath,
            body: """
            #!/bin/sh
            cat >/dev/null
            printf 'done\\n'
            exit 0
            """
        )

        let shell = ShellClient(pathLookupDirectories: [sandbox.root], environment: [:])
        let start = Date()
        let timeout: TimeInterval = 2
        let result = try await shell.runStreaming(executable: scriptPath, arguments: [], timeout: timeout, onEvent: nil)
        let elapsed = Date().timeIntervalSince(start)

        #expect(result.status == 0)
        #expect(result.stdout.contains("done"))
        #expect(elapsed < timeout)
    }
}

private actor AgentRunEventRecorder {
    private var values: [AgentRunEvent] = []

    func append(_ event: AgentRunEvent) {
        values.append(event)
    }

    func events() -> [AgentRunEvent] {
        values
    }
}

private final class MockAgentHTTPTransport: AgentHTTPTransport, @unchecked Sendable {
    private let responseBody: String
    private(set) var recordedRequest: URLRequest?

    init(responseBody: String) {
        self.responseBody = responseBody
    }

    func data(for request: URLRequest, timeout: TimeInterval) async throws -> (Data, HTTPURLResponse) {
        recordedRequest = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (Data(responseBody.utf8), response)
    }

    func bytes(for request: URLRequest, timeout: TimeInterval) async throws -> (URLSession.AsyncBytes, URLResponse) {
        fatalError("Streaming is not used by this mock")
    }
}

private actor ShellEventRecorder {
    private var values: [ShellEvent] = []

    func append(_ event: ShellEvent) {
        values.append(event)
    }

    func events() -> [ShellEvent] {
        values
    }
}
