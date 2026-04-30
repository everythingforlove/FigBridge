import Foundation

public protocol FigmaHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionFigmaTransport: FigmaHTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FigmaServiceError.invalidResponse
        }
        return (data, http)
    }
}

public enum FigmaServiceError: LocalizedError {
    case missingToken
    case invalidResponse
    case httpError(Int)
    case invalidPayload
    case previewUnavailable

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            "请先配置 Figma Token"
        case .invalidResponse:
            "Figma 响应无效"
        case .httpError(let code):
            "Figma 请求失败: HTTP \(code)"
        case .invalidPayload:
            "Figma 数据解析失败"
        case .previewUnavailable:
            "节点预览不可用"
        }
    }
}

public actor FigmaService {
    public let baseDirectory: URL
    private let transport: FigmaHTTPTransport

    public init(baseDirectory: URL, transport: FigmaHTTPTransport = URLSessionFigmaTransport()) {
        self.baseDirectory = baseDirectory
        self.transport = transport
    }

    public func validateToken(_ token: String) async throws {
        let normalizedToken = try normalizedToken(token)
        let request = try makeAPIRequest(path: "/v1/me", queryItems: [], token: normalizedToken)
        _ = try await performJSONRequest(request)
    }

    public func loadPreviewAndResources(
        for item: FigmaLinkItem,
        itemDirectory: URL,
        token: String,
        previewFormat: ExportFormat
    ) async throws -> FigmaLinkItem {
        let normalizedToken = try normalizedToken(token)
        let payload = try await fetchNodePayload(
            fileKey: item.fileKey,
            nodeId: item.nodeId,
            token: normalizedToken,
            previewFormat: previewFormat
        )
        return try await cachePayload(
            payload,
            for: item,
            itemDirectory: itemDirectory,
            token: normalizedToken,
            previewFormat: previewFormat
        )
    }

    private func fetchNodePayload(fileKey: String, nodeId: String, token: String, previewFormat: ExportFormat) async throws -> FigmaNodePayload {
        let nodeRequest = try makeAPIRequest(
            path: "/v1/files/\(fileKey)/nodes",
            queryItems: [URLQueryItem(name: "ids", value: nodeId)],
            token: token
        )
        let imagesRequest = try makeAPIRequest(
            path: "/v1/images/\(fileKey)",
            queryItems: [
                URLQueryItem(name: "ids", value: nodeId),
                URLQueryItem(name: "format", value: previewFormat.rawValue),
                URLQueryItem(name: "scale", value: "2")
            ],
            token: token
        )
        let fileImagesRequest = try makeAPIRequest(
            path: "/v1/files/\(fileKey)/images",
            queryItems: [],
            token: token
        )

        async let nodeData = performJSONRequest(nodeRequest)
        async let previewData = performJSONRequest(imagesRequest)
        async let resourceData = performJSONRequest(fileImagesRequest)

        let nodeResponse = try decode(NodeResponse.self, from: try await nodeData)
        let previewResponse = try decode(PreviewResponse.self, from: try await previewData)
        let imageLookupResponse = try decode(ImageLookupResponse.self, from: try await resourceData)

        guard let node = nodeResponse.nodes[nodeId]?.document else {
            throw FigmaServiceError.invalidPayload
        }

        let imageRefs = collectImageRefs(from: node)
        let resources = imageRefs.compactMap { ref -> FigmaResourceItem? in
            guard let url = imageLookupResponse.meta.images[ref] else {
                return nil
            }
            return FigmaResourceItem(
                name: ref,
                kind: url.lowercased().hasSuffix(".svg") ? .icon : .image,
                format: url.lowercased().hasSuffix(".svg") ? .svg : .png,
                remoteURL: url
            )
        }

        return FigmaNodePayload(
            name: node.name,
            previewURL: previewResponse.images[nodeId] ?? nil,
            resources: resources
        )
    }

    private func cachePayload(
        _ payload: FigmaNodePayload,
        for item: FigmaLinkItem,
        itemDirectory: URL,
        token: String,
        previewFormat: ExportFormat
    ) async throws -> FigmaLinkItem {
        let cacheDirectory = itemDirectory.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        var resolved = item
        resolved.nodeName = payload.name

        if let previewURL = payload.previewURL {
            do {
                let previewFilename = "preview.\(previewFormat.rawValue)"
                let previewPath = try await downloadFile(from: previewURL, token: token, destinationDirectory: cacheDirectory, filename: previewFilename)
                resolved.previewImagePath = previewPath.path
                resolved.previewStatus = .success
            } catch {
                resolved.previewStatus = .failed
                resolved.errorMessage = error.localizedDescription
            }
        } else {
            resolved.previewStatus = .failed
        }

        var cachedResources: [FigmaResourceItem] = []
        var didFailToCacheAnyResource = false
        for (index, resource) in payload.resources.enumerated() {
            guard let remoteURL = resource.remoteURL else {
                continue
            }
            let filename = "\(index + 1)-\(BatchStore.pathSafe(resource.name)).\(resource.format.rawValue)"
            do {
                let localURL = try await downloadFile(from: remoteURL, token: token, destinationDirectory: cacheDirectory, filename: filename)
                var cached = resource
                cached.localPath = localURL.path
                cachedResources.append(cached)
            } catch {
                didFailToCacheAnyResource = true
                resolved.errorMessage = error.localizedDescription
            }
        }

        resolved.resourceItems = cachedResources
        resolved.resourceStatus = didFailToCacheAnyResource ? .failed : .success
        return resolved
    }

    private func downloadFile(from urlString: String, token: String, destinationDirectory: URL, filename: String) async throws -> URL {
        guard let url = URL(string: urlString) else {
            throw FigmaServiceError.invalidPayload
        }
        var request = URLRequest(url: url)
        request.setValue(token, forHTTPHeaderField: "X-Figma-Token")
        let (data, response) = try await transport.data(for: request)
        guard (200...299).contains(response.statusCode) else {
            throw FigmaServiceError.httpError(response.statusCode)
        }
        let fileURL = destinationDirectory.appendingPathComponent(filename)
        try data.write(to: fileURL)
        return fileURL
    }

    private func normalizedToken(_ token: String) throws -> String {
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw FigmaServiceError.missingToken
        }
        return normalized
    }

    private func makeAPIRequest(path: String, queryItems: [URLQueryItem], token: String) throws -> URLRequest {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.figma.com"
        components.path = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw FigmaServiceError.invalidPayload
        }
        var request = URLRequest(url: url)
        request.setValue(token, forHTTPHeaderField: "X-Figma-Token")
        return request
    }

    private func performJSONRequest(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await transport.data(for: request)
        guard (200...299).contains(response.statusCode) else {
            throw FigmaServiceError.httpError(response.statusCode)
        }
        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw FigmaServiceError.invalidPayload
        }
    }

    private func collectImageRefs(from node: FigmaDocumentNode) -> [String] {
        var refs: [String] = []
        refs.append(contentsOf: node.fills.compactMap(\.imageRef))
        for child in node.children {
            refs.append(contentsOf: collectImageRefs(from: child))
        }
        return Array(Set(refs)).sorted()
    }
}

private struct NodeResponse: Decodable {
    let nodes: [String: NodeContainer]
}

private struct NodeContainer: Decodable {
    let document: FigmaDocumentNode
}

private struct FigmaDocumentNode: Decodable {
    let id: String
    let name: String
    let fills: [FigmaFill]
    let children: [FigmaDocumentNode]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        fills = try container.decodeIfPresent([FigmaFill].self, forKey: .fills) ?? []
        children = try container.decodeIfPresent([FigmaDocumentNode].self, forKey: .children) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case fills
        case children
    }
}

private struct FigmaFill: Decodable {
    let type: String
    let imageRef: String?
}

private struct PreviewResponse: Decodable {
    let images: [String: String?]
}

private struct ImageLookupResponse: Decodable {
    let meta: ImageLookupMeta
}

private struct ImageLookupMeta: Decodable {
    let images: [String: String]
}
