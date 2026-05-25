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
    private let localResources: LocalDesignResourceResolver

    public init(
        baseDirectory: URL,
        transport: FigmaHTTPTransport = URLSessionFigmaTransport(),
        localResources: LocalDesignResourceResolver = .loadDefault()
    ) {
        self.baseDirectory = baseDirectory
        self.transport = transport
        self.localResources = localResources
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

        let resolvedNodeData = try await nodeData
        let nodeResponse = try decode(NodeResponse.self, from: resolvedNodeData)
        let previewResponse = try decode(PreviewResponse.self, from: try await previewData)
        let imageLookupResponse = try decode(ImageLookupResponse.self, from: try await resourceData)

        guard let node = nodeResponse.nodes[nodeId]?.document else {
            throw FigmaServiceError.invalidPayload
        }
        let documentJSON = try? extractDocumentJSON(from: resolvedNodeData, nodeId: nodeId)

        let imageRefs = collectImageRefs(from: node)
        let remoteResources = imageRefs.compactMap { ref -> FigmaResourceItem? in
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
        let resources = mergeResources(remoteResources + collectLocalAssetResources(from: node))

        return FigmaNodePayload(
            name: node.name,
            previewURL: previewResponse.images[nodeId] ?? nil,
            resources: resources,
            document: node,
            documentJSON: documentJSON
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
        var usedFilenames = Set<String>()
        for (index, resource) in payload.resources.enumerated() {
            let filename = uniqueResourceFilename(for: resource, index: index, usedFilenames: &usedFilenames)
            do {
                let localURL: URL
                if let remoteURL = resource.remoteURL {
                    localURL = try await downloadFile(from: remoteURL, token: token, destinationDirectory: cacheDirectory, filename: filename)
                } else if let localPath = resource.localPath {
                    localURL = try copyLocalResource(from: localPath, destinationDirectory: cacheDirectory, filename: filename)
                } else {
                    continue
                }
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
        try cacheLocalFigmaContext(
            payload,
            for: &resolved,
            itemDirectory: itemDirectory,
            cachedResources: cachedResources
        )
        return resolved
    }

    private func cacheLocalFigmaContext(
        _ payload: FigmaNodePayload,
        for item: inout FigmaLinkItem,
        itemDirectory: URL,
        cachedResources: [FigmaResourceItem]
    ) throws {
        let contextDirectory = itemDirectory.appendingPathComponent("figma-context", isDirectory: true)
        try FileManager.default.createDirectory(at: contextDirectory, withIntermediateDirectories: true)

        if let documentJSON = payload.documentJSON {
            let documentURL = contextDirectory.appendingPathComponent("figma-node.json")
            try documentJSON.write(to: documentURL)
            item.figmaNodeJSONPath = documentURL.path
        }

        guard let document = payload.document else {
            return
        }

        let design = FigmaNodeToDesignIRMapper().map(
            document: document,
            fileKey: item.fileKey,
            nodeId: item.nodeId,
            resources: cachedResources,
            localResources: localResources
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let designData = try encoder.encode(design)
        let designURL = contextDirectory.appendingPathComponent("figma-derived-design-ir.json")
        try designData.write(to: designURL)
        item.figmaDerivedDesignIRPath = designURL.path
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

    private func copyLocalResource(from path: String, destinationDirectory: URL, filename: String) throws -> URL {
        let sourceURL = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw FigmaServiceError.invalidPayload
        }

        let fileURL = destinationDirectory.appendingPathComponent(filename)
        if sourceURL.standardizedFileURL == fileURL.standardizedFileURL {
            return fileURL
        }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: fileURL)
        return fileURL
    }

    private func uniqueResourceFilename(
        for resource: FigmaResourceItem,
        index: Int,
        usedFilenames: inout Set<String>
    ) -> String {
        let rawBase = resource.remoteURL == nil
            ? LocalResourceName.normalized(resource.name)
            : "\(index + 1)-\(BatchStore.pathSafe(resource.name))"
        let base = rawBase.trimmingCharacters(in: CharacterSet(charactersIn: ". /\\")).isEmpty ? "asset-\(index + 1)" : rawBase
        let ext = resource.format.rawValue
        var candidate = "\(base).\(ext)"
        var suffix = 2
        while usedFilenames.contains(candidate) {
            candidate = "\(base)-\(suffix).\(ext)"
            suffix += 1
        }
        usedFilenames.insert(candidate)
        return candidate
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

    private func extractDocumentJSON(from data: Data, nodeId: String) throws -> Data {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let nodes = object["nodes"] as? [String: Any],
              let nodeContainer = nodes[nodeId] as? [String: Any],
              let document = nodeContainer["document"] else {
            throw FigmaServiceError.invalidPayload
        }
        return try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
    }

    private func collectImageRefs(from node: FigmaDocumentNode) -> [String] {
        var refs: [String] = []
        refs.append(contentsOf: node.fills.compactMap(\.imageRef))
        for child in node.children {
            refs.append(contentsOf: collectImageRefs(from: child))
        }
        return Array(Set(refs)).sorted()
    }

    private func collectLocalAssetResources(from node: FigmaDocumentNode) -> [FigmaResourceItem] {
        guard !localResources.imageAssets.isEmpty else {
            return []
        }

        var resourcesByKey: [String: FigmaResourceItem] = [:]
        collectLocalAssetResources(from: node, resourcesByKey: &resourcesByKey)
        return resourcesByKey.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func collectLocalAssetResources(from node: FigmaDocumentNode, resourcesByKey: inout [String: FigmaResourceItem]) {
        if let match = localResources.imageAssets.match(nodeName: node.name) {
            let key = "\(match.assetName)|\(match.url.path)"
            resourcesByKey[key] = resourcesByKey[key] ?? FigmaResourceItem(
                name: match.assetName,
                kind: match.kind,
                format: match.format,
                remoteURL: nil,
                localPath: match.url.path
            )
        }

        for child in node.children {
            collectLocalAssetResources(from: child, resourcesByKey: &resourcesByKey)
        }
    }

    private func mergeResources(_ resources: [FigmaResourceItem]) -> [FigmaResourceItem] {
        var seen = Set<String>()
        return resources.filter { resource in
            let key = [resource.name, resource.remoteURL ?? "", resource.localPath ?? ""].joined(separator: "|")
            guard !seen.contains(key) else {
                return false
            }
            seen.insert(key)
            return true
        }
    }
}

private struct NodeResponse: Decodable {
    let nodes: [String: NodeContainer]
}

private struct NodeContainer: Decodable {
    let document: FigmaDocumentNode
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
