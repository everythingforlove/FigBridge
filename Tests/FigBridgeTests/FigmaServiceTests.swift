import Foundation
import Testing
@testable import FigBridgeCore

struct FigmaServiceTests {
    @Test func validatesTokenByCallingMeEndpoint() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }
        let transport = MockFigmaTransport(responses: [
            MockHTTPResponse(
                path: "/v1/me",
                query: [:],
                statusCode: 200,
                body: #"{"id":"1","handle":"tester"}"#
            )
        ])
        let service = FigmaService(baseDirectory: sandbox.root, transport: transport)

        try await service.validateToken("token")

        let requests = await transport.recordedRequests()
        #expect(requests.count == 1)
        #expect(requests[0].path == "/v1/me")
    }

    @Test func fetchesPreviewAndResourcesAndCachesToDisk() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }
        let previewBody = Data("PNGDATA".utf8)
        let resourceBody = Data("<svg></svg>".utf8)
        let transport = MockFigmaTransport(responses: [
            MockHTTPResponse(
                path: "/v1/files/FILE123/nodes",
                query: ["ids": "1:2"],
                statusCode: 200,
                body: """
                {
                  "nodes": {
                    "1:2": {
                      "document": {
                        "id": "1:2",
                        "name": "Login Card",
                        "fills": [
                          { "type": "IMAGE", "imageRef": "img-ref-1" }
                        ],
                        "children": [
                          {
                            "id": "2:3",
                            "name": "Icon",
                            "fills": [
                              { "type": "IMAGE", "imageRef": "img-ref-2" }
                            ]
                          }
                        ]
                      }
                    }
                  }
                }
                """
            ),
            MockHTTPResponse(
                path: "/v1/images/FILE123",
                query: ["ids": "1:2", "format": "png", "scale": "2"],
                statusCode: 200,
                body: #"{"images":{"1:2":"https://cdn.figma.test/preview.png"}}"#
            ),
            MockHTTPResponse(
                path: "/v1/files/FILE123/images",
                query: [:],
                statusCode: 200,
                body: #"{"meta":{"images":{"img-ref-1":"https://cdn.figma.test/image.png","img-ref-2":"https://cdn.figma.test/icon.svg"}}}"#
            ),
            MockHTTPResponse(
                url: "https://cdn.figma.test/preview.png",
                statusCode: 200,
                data: previewBody
            ),
            MockHTTPResponse(
                url: "https://cdn.figma.test/image.png",
                statusCode: 200,
                data: previewBody
            ),
            MockHTTPResponse(
                url: "https://cdn.figma.test/icon.svg",
                statusCode: 200,
                data: resourceBody
            ),
        ])
        let service = FigmaService(baseDirectory: sandbox.root, transport: transport)
        let item = FigmaLinkItem(
            rawInputLine: "登录卡片",
            title: "登录卡片",
            url: "https://www.figma.com/design/FILE123/App?node-id=1-2",
            fileKey: "FILE123",
            nodeId: "1:2"
        )
        let itemDirectory = sandbox.root.appendingPathComponent("batch-1/items/item-1", isDirectory: true)

        let resolved = try await service.loadPreviewAndResources(for: item, itemDirectory: itemDirectory, token: "token", previewFormat: .png)

        #expect(resolved.nodeName == "Login Card")
        #expect(resolved.previewStatus == .success)
        #expect(resolved.resourceStatus == .success)
        #expect(resolved.previewImagePath != nil)
        #expect(resolved.resourceItems.count == 2)
        #expect(resolved.resourceItems.allSatisfy { $0.localPath != nil })
        #expect(resolved.previewImagePath?.contains("/items/item-1/assets/preview.png") == true)
        #expect(resolved.resourceItems.allSatisfy { $0.localPath?.contains("/items/item-1/assets/") == true })
        #expect(resolved.figmaNodeJSONPath?.contains("/items/item-1/figma-context/figma-node.json") == true)
        #expect(resolved.figmaDerivedDesignIRPath?.contains("/items/item-1/figma-context/figma-derived-design-ir.json") == true)
        let figmaNodeJSONPath = try #require(resolved.figmaNodeJSONPath)
        let figmaDerivedDesignIRPath = try #require(resolved.figmaDerivedDesignIRPath)
        #expect(FileManager.default.fileExists(atPath: figmaNodeJSONPath))
        #expect(FileManager.default.fileExists(atPath: figmaDerivedDesignIRPath))
    }

    @Test func usesConfiguredPreviewFormatForRequestAndCacheFilename() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }
        let transport = MockFigmaTransport(responses: [
            MockHTTPResponse(
                path: "/v1/files/FILE123/nodes",
                query: ["ids": "1:2"],
                statusCode: 200,
                body: """
                {
                  "nodes": {
                    "1:2": {
                      "document": {
                        "id": "1:2",
                        "name": "Login Card",
                        "fills": [],
                        "children": []
                      }
                    }
                  }
                }
                """
            ),
            MockHTTPResponse(
                path: "/v1/images/FILE123",
                query: ["ids": "1:2", "format": "svg", "scale": "2"],
                statusCode: 200,
                body: #"{"images":{"1:2":"https://cdn.figma.test/preview.svg"}}"#
            ),
            MockHTTPResponse(
                path: "/v1/files/FILE123/images",
                query: [:],
                statusCode: 200,
                body: #"{"meta":{"images":{}}}"#
            ),
            MockHTTPResponse(
                url: "https://cdn.figma.test/preview.svg",
                statusCode: 200,
                data: Data("<svg/>".utf8)
            )
        ])
        let service = FigmaService(baseDirectory: sandbox.root, transport: transport)
        let item = FigmaLinkItem(
            rawInputLine: "登录卡片",
            title: "登录卡片",
            url: "https://www.figma.com/design/FILE123/App?node-id=1-2",
            fileKey: "FILE123",
            nodeId: "1:2"
        )
        let itemDirectory = sandbox.root.appendingPathComponent("batch-1/items/item-1", isDirectory: true)

        let resolved = try await service.loadPreviewAndResources(for: item, itemDirectory: itemDirectory, token: "token", previewFormat: .svg)

        let requests = await transport.recordedRequests()
        #expect(requests.contains { $0.path == "/v1/images/FILE123" && $0.query["format"] == "svg" })
        #expect(resolved.previewImagePath?.hasSuffix("/preview.svg") == true)
    }

    @Test func allowsPreviewFailureWithoutBlockingResources() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }
        let transport = MockFigmaTransport(responses: [
            MockHTTPResponse(
                path: "/v1/files/FILE123/nodes",
                query: ["ids": "1:2"],
                statusCode: 200,
                body: """
                {
                  "nodes": {
                    "1:2": {
                      "document": {
                        "id": "1:2",
                        "name": "Login Card",
                        "fills": [
                          { "type": "IMAGE", "imageRef": "img-ref-1" }
                        ]
                      }
                    }
                  }
                }
                """
            ),
            MockHTTPResponse(
                path: "/v1/images/FILE123",
                query: ["ids": "1:2", "format": "png", "scale": "2"],
                statusCode: 200,
                body: #"{"images":{"1:2":null}}"#
            ),
            MockHTTPResponse(
                path: "/v1/files/FILE123/images",
                query: [:],
                statusCode: 200,
                body: #"{"meta":{"images":{"img-ref-1":"https://cdn.figma.test/image.png"}}}"#
            ),
            MockHTTPResponse(
                url: "https://cdn.figma.test/image.png",
                statusCode: 200,
                data: Data("PNGDATA".utf8)
            ),
        ])
        let service = FigmaService(baseDirectory: sandbox.root, transport: transport)
        let item = FigmaLinkItem(
            rawInputLine: "登录卡片",
            title: "登录卡片",
            url: "https://www.figma.com/design/FILE123/App?node-id=1-2",
            fileKey: "FILE123",
            nodeId: "1:2"
        )
        let itemDirectory = sandbox.root.appendingPathComponent("batch-1/items/item-1", isDirectory: true)

        let resolved = try await service.loadPreviewAndResources(for: item, itemDirectory: itemDirectory, token: "token", previewFormat: .png)

        #expect(resolved.previewStatus == .failed)
        #expect(resolved.resourceStatus == .success)
        #expect(resolved.resourceItems.count == 1)
    }

    @Test func treatsEmptyResourceSetAsSuccessfulResourceLoad() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }
        let transport = MockFigmaTransport(responses: [
            MockHTTPResponse(
                path: "/v1/files/FILE123/nodes",
                query: ["ids": "1:2"],
                statusCode: 200,
                body: """
                {
                  "nodes": {
                    "1:2": {
                      "document": {
                        "id": "1:2",
                        "name": "Plain Frame",
                        "fills": [],
                        "children": []
                      }
                    }
                  }
                }
                """
            ),
            MockHTTPResponse(
                path: "/v1/images/FILE123",
                query: ["ids": "1:2", "format": "png", "scale": "2"],
                statusCode: 200,
                body: #"{"images":{"1:2":"https://cdn.figma.test/preview.png"}}"#
            ),
            MockHTTPResponse(
                path: "/v1/files/FILE123/images",
                query: [:],
                statusCode: 200,
                body: #"{"meta":{"images":{}}}"#
            ),
            MockHTTPResponse(
                url: "https://cdn.figma.test/preview.png",
                statusCode: 200,
                data: Data("PNGDATA".utf8)
            )
        ])
        let service = FigmaService(baseDirectory: sandbox.root, transport: transport)
        let item = FigmaLinkItem(
            rawInputLine: "普通容器",
            title: "普通容器",
            url: "https://www.figma.com/design/FILE123/App?node-id=1-2",
            fileKey: "FILE123",
            nodeId: "1:2"
        )
        let itemDirectory = sandbox.root.appendingPathComponent("batch-1/items/item-1", isDirectory: true)

        let resolved = try await service.loadPreviewAndResources(for: item, itemDirectory: itemDirectory, token: "token", previewFormat: .png)

        #expect(resolved.previewStatus == .success)
        #expect(resolved.resourceStatus == .success)
        #expect(resolved.resourceItems.isEmpty)
    }

    @Test func marksResourceStatusFailedWhenAnyResourceDownloadFails() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }
        let transport = PartiallyFailingResourceTransport()
        let service = FigmaService(baseDirectory: sandbox.root, transport: transport)
        let item = FigmaLinkItem(
            rawInputLine: "登录卡片",
            title: "登录卡片",
            url: "https://www.figma.com/design/FILE123/App?node-id=1-2",
            fileKey: "FILE123",
            nodeId: "1:2"
        )
        let itemDirectory = sandbox.root.appendingPathComponent("batch-1/items/item-1", isDirectory: true)

        let resolved = try await service.loadPreviewAndResources(for: item, itemDirectory: itemDirectory, token: "token", previewFormat: .png)

        #expect(resolved.previewStatus == .success)
        #expect(resolved.resourceStatus == .failed)
        #expect(resolved.resourceItems.count == 1)
        #expect(resolved.resourceItems.first?.name == "img-ref-1")
        #expect(resolved.resourceItems.first?.localPath != nil)
        #expect(resolved.errorMessage?.isEmpty == false)
    }
}

actor MockFigmaTransport: FigmaHTTPTransport {
    private let responses: [MockHTTPResponse]
    private var requests: [MockTransportRequest] = []

    init(responses: [MockHTTPResponse]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url else {
            throw URLError(.badURL)
        }
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let query = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value ?? "") })
        requests.append(MockTransportRequest(url: url.absoluteString, path: url.path, query: query))

        guard let response = responses.first(where: { $0.matches(url: url, query: query) }) else {
            throw URLError(.badServerResponse)
        }
        let body = response.data ?? Data(response.body.utf8)
        let http = HTTPURLResponse(url: url, statusCode: response.statusCode, httpVersion: nil, headerFields: nil)!
        return (body, http)
    }

    func recordedRequests() -> [MockTransportRequest] {
        requests
    }
}

struct MockHTTPResponse {
    var url: String?
    var path: String?
    var query: [String: String]
    var statusCode: Int
    var body: String
    var data: Data?

    init(url: String? = nil, path: String? = nil, query: [String: String], statusCode: Int, body: String, data: Data? = nil) {
        self.url = url
        self.path = path
        self.query = query
        self.statusCode = statusCode
        self.body = body
        self.data = data
    }

    init(url: String, statusCode: Int, data: Data) {
        self.url = url
        self.path = nil
        self.query = [:]
        self.statusCode = statusCode
        self.body = ""
        self.data = data
    }

    func matches(url candidateURL: URL, query candidateQuery: [String: String]) -> Bool {
        if let url, url == candidateURL.absoluteString {
            return true
        }
        guard let path else {
            return false
        }
        return candidateURL.path == path && candidateQuery == query
    }
}

struct MockTransportRequest {
    let url: String
    let path: String
    let query: [String: String]
}

actor PartiallyFailingResourceTransport: FigmaHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url else {
            throw URLError(.badURL)
        }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []
        let query = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value ?? "") })

        switch url.path {
        case "/v1/files/FILE123/nodes":
            return response(
                url: url,
                status: 200,
                body: """
                {
                  "nodes": {
                    "1:2": {
                      "document": {
                        "id": "1:2",
                        "name": "Login Card",
                        "fills": [
                          { "type": "IMAGE", "imageRef": "img-ref-1" },
                          { "type": "IMAGE", "imageRef": "img-ref-2" }
                        ],
                        "children": []
                      }
                    }
                  }
                }
                """
            )
        case "/v1/images/FILE123":
            if query["ids"] == "1:2" {
                return response(url: url, status: 200, body: #"{"images":{"1:2":"https://cdn.figma.test/preview.png"}}"#)
            }
        case "/v1/files/FILE123/images":
            return response(
                url: url,
                status: 200,
                body: #"{"meta":{"images":{"img-ref-1":"https://cdn.figma.test/image.png","img-ref-2":"https://cdn.figma.test/broken.png"}}}"#
            )
        default:
            break
        }

        switch url.absoluteString {
        case "https://cdn.figma.test/preview.png":
            return response(url: url, status: 200, data: Data("PNG".utf8))
        case "https://cdn.figma.test/image.png":
            return response(url: url, status: 200, data: Data("RES".utf8))
        case "https://cdn.figma.test/broken.png":
            throw URLError(.secureConnectionFailed)
        default:
            throw URLError(.badServerResponse)
        }
    }

    private func response(url: URL, status: Int, body: String) -> (Data, HTTPURLResponse) {
        response(url: url, status: status, data: Data(body.utf8))
    }

    private func response(url: URL, status: Int, data: Data) -> (Data, HTTPURLResponse) {
        let http = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (data, http)
    }
}
