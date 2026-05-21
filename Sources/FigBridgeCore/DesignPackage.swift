import CryptoKit
import Foundation

public enum TargetPlatform: String, Codable, CaseIterable, Sendable {
    case harmonyArkUI = "harmony-arkui"
}

public enum DesignNodeType: String, Codable, CaseIterable, Sendable {
    case frame
    case text
    case image
    case icon
    case button
    case list
    case input
    case unknown
}

public enum DesignLayoutMode: String, Codable, CaseIterable, Sendable {
    case none
    case vertical
    case horizontal
    case wrap
    case absolute
}

public enum DesignSizingMode: String, Codable, CaseIterable, Sendable {
    case fixed
    case hug
    case fill
}

public struct DesignSize: Codable, Equatable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct DesignRect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct DesignInsets: Codable, Equatable, Sendable {
    public var top: Double
    public var right: Double
    public var bottom: Double
    public var left: Double

    public init(top: Double = 0, right: Double = 0, bottom: Double = 0, left: Double = 0) {
        self.top = top
        self.right = right
        self.bottom = bottom
        self.left = left
    }
}

public struct DesignSizing: Codable, Equatable, Sendable {
    public var width: DesignSizingMode
    public var height: DesignSizingMode

    public init(width: DesignSizingMode = .fixed, height: DesignSizingMode = .fixed) {
        self.width = width
        self.height = height
    }
}

public struct DesignLayout: Codable, Equatable, Sendable {
    public var mode: DesignLayoutMode
    public var spacing: Double?
    public var padding: DesignInsets?
    public var alignment: String?
    public var sizing: DesignSizing?

    public init(
        mode: DesignLayoutMode = .none,
        spacing: Double? = nil,
        padding: DesignInsets? = nil,
        alignment: String? = nil,
        sizing: DesignSizing? = nil
    ) {
        self.mode = mode
        self.spacing = spacing
        self.padding = padding
        self.alignment = alignment
        self.sizing = sizing
    }
}

public struct DesignTextStyle: Codable, Equatable, Sendable {
    public var fontFamily: String?
    public var fontSize: Double?
    public var fontWeight: String?
    public var lineHeight: Double?
    public var color: String?
    public var textAlign: String?

    public init(
        fontFamily: String? = nil,
        fontSize: Double? = nil,
        fontWeight: String? = nil,
        lineHeight: Double? = nil,
        color: String? = nil,
        textAlign: String? = nil
    ) {
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.lineHeight = lineHeight
        self.color = color
        self.textAlign = textAlign
    }
}

public struct DesignStyle: Codable, Equatable, Sendable {
    public var fill: String?
    public var stroke: String?
    public var strokeWidth: Double?
    public var cornerRadius: Double?
    public var opacity: Double?
    public var shadow: String?
    public var text: DesignTextStyle?

    public init(
        fill: String? = nil,
        stroke: String? = nil,
        strokeWidth: Double? = nil,
        cornerRadius: Double? = nil,
        opacity: Double? = nil,
        shadow: String? = nil,
        text: DesignTextStyle? = nil
    ) {
        self.fill = fill
        self.stroke = stroke
        self.strokeWidth = strokeWidth
        self.cornerRadius = cornerRadius
        self.opacity = opacity
        self.shadow = shadow
        self.text = text
    }
}

public struct DesignAssetRef: Codable, Equatable, Sendable {
    public var name: String
    public var localPath: String
    public var kind: FigmaResourceItem.ResourceKind
    public var format: ExportFormat

    public init(name: String, localPath: String, kind: FigmaResourceItem.ResourceKind, format: ExportFormat) {
        self.name = name
        self.localPath = localPath
        self.kind = kind
        self.format = format
    }
}

public struct DesignNode: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var type: DesignNodeType
    public var bounds: DesignRect?
    public var layout: DesignLayout?
    public var style: DesignStyle?
    public var text: String?
    public var asset: DesignAssetRef?
    public var children: [DesignNode]
    public var needsReview: Bool
    public var confidence: Double?
    public var warnings: [String]

    public init(
        id: String,
        name: String,
        type: DesignNodeType,
        bounds: DesignRect? = nil,
        layout: DesignLayout? = nil,
        style: DesignStyle? = nil,
        text: String? = nil,
        asset: DesignAssetRef? = nil,
        children: [DesignNode] = [],
        needsReview: Bool = false,
        confidence: Double? = nil,
        warnings: [String] = []
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.bounds = bounds
        self.layout = layout
        self.style = style
        self.text = text
        self.asset = asset
        self.children = children
        self.needsReview = needsReview
        self.confidence = confidence
        self.warnings = warnings
    }
}

public struct DesignColorToken: Codable, Equatable, Sendable {
    public var name: String
    public var value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

public struct DesignTextToken: Codable, Equatable, Sendable {
    public var name: String
    public var style: DesignTextStyle

    public init(name: String, style: DesignTextStyle) {
        self.name = name
        self.style = style
    }
}

public struct DesignTokenSet: Codable, Equatable, Sendable {
    public var colors: [DesignColorToken]
    public var textStyles: [DesignTextToken]
    public var spacing: [String: Double]
    public var radii: [String: Double]

    public init(
        colors: [DesignColorToken] = [],
        textStyles: [DesignTextToken] = [],
        spacing: [String: Double] = [:],
        radii: [String: Double] = [:]
    ) {
        self.colors = colors
        self.textStyles = textStyles
        self.spacing = spacing
        self.radii = radii
    }
}

public struct DesignIR: Codable, Equatable, Sendable {
    public static let currentVersion = "design-ir/v1"

    public var version: String
    public var screenName: String
    public var fileKey: String
    public var nodeId: String
    public var targetPlatform: TargetPlatform
    public var viewport: DesignSize
    public var tokens: DesignTokenSet
    public var rootNode: DesignNode
    public var warnings: [String]

    public init(
        version: String = DesignIR.currentVersion,
        screenName: String,
        fileKey: String,
        nodeId: String,
        targetPlatform: TargetPlatform = .harmonyArkUI,
        viewport: DesignSize,
        tokens: DesignTokenSet = DesignTokenSet(),
        rootNode: DesignNode,
        warnings: [String] = []
    ) {
        self.version = version
        self.screenName = screenName
        self.fileKey = fileKey
        self.nodeId = nodeId
        self.targetPlatform = targetPlatform
        self.viewport = viewport
        self.tokens = tokens
        self.rootNode = rootNode
        self.warnings = warnings
    }
}

public struct DesignPackageSource: Codable, Equatable, Sendable {
    public var figmaURL: String
    public var fileKey: String
    public var nodeId: String
    public var exportedAt: Date
    public var exporter: String

    public init(figmaURL: String, fileKey: String, nodeId: String, exportedAt: Date = Date(), exporter: String = "FigBridge") {
        self.figmaURL = figmaURL
        self.fileKey = fileKey
        self.nodeId = nodeId
        self.exportedAt = exportedAt
        self.exporter = exporter
    }
}

public struct DesignPackageManifest: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = "figbridge-design-package/v1"

    public var schemaVersion: String
    public var packageID: String
    public var createdAt: Date
    public var targetPlatform: TargetPlatform
    public var source: DesignPackageSource
    public var designFile: String
    public var figmaNodeFile: String?
    public var previewFile: String?
    public var assetsDirectory: String
    public var checksums: [String: String]

    public init(
        schemaVersion: String = DesignPackageManifest.currentSchemaVersion,
        packageID: String,
        createdAt: Date = Date(),
        targetPlatform: TargetPlatform = .harmonyArkUI,
        source: DesignPackageSource,
        designFile: String = DesignPackageStore.designFilename,
        figmaNodeFile: String? = nil,
        previewFile: String? = nil,
        assetsDirectory: String = DesignPackageStore.assetsDirectoryName,
        checksums: [String: String] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.packageID = packageID
        self.createdAt = createdAt
        self.targetPlatform = targetPlatform
        self.source = source
        self.designFile = designFile
        self.figmaNodeFile = figmaNodeFile
        self.previewFile = previewFile
        self.assetsDirectory = assetsDirectory
        self.checksums = checksums
    }
}

public struct DesignPackageWriteRequest: Sendable {
    public var packageID: String
    public var source: DesignPackageSource
    public var design: DesignIR
    public var previewFile: URL?
    public var figmaNodeJSON: Data?
    public var assetFiles: [URL]

    public init(
        packageID: String,
        source: DesignPackageSource,
        design: DesignIR,
        previewFile: URL? = nil,
        figmaNodeJSON: Data? = nil,
        assetFiles: [URL] = []
    ) {
        self.packageID = packageID
        self.source = source
        self.design = design
        self.previewFile = previewFile
        self.figmaNodeJSON = figmaNodeJSON
        self.assetFiles = assetFiles
    }
}

public struct PersistedDesignPackage: Sendable {
    public var manifest: DesignPackageManifest
    public var design: DesignIR
    public var packageDirectory: URL
    public var assetsDirectory: URL

    public init(manifest: DesignPackageManifest, design: DesignIR, packageDirectory: URL, assetsDirectory: URL) {
        self.manifest = manifest
        self.design = design
        self.packageDirectory = packageDirectory
        self.assetsDirectory = assetsDirectory
    }
}

public enum DesignPackageError: LocalizedError, Equatable {
    case invalidPackageDirectory
    case invalidSchemaVersion(String)
    case invalidDesignIRVersion(String)
    case invalidField(String, String)
    case missingRequiredField(String)
    case missingReferencedFile(String)
    case unsafePath(String)
    case missingChecksum(String)
    case unexpectedChecksum(String)
    case checksumMismatch(String)
    case importFailed

    public var errorDescription: String? {
        switch self {
        case .invalidPackageDirectory:
            "设计包目录无效"
        case .invalidSchemaVersion(let version):
            "设计包版本不支持: \(version)"
        case .invalidDesignIRVersion(let version):
            "DesignIR 版本不支持: \(version)"
        case .invalidField(let field, let reason):
            "设计包字段无效: \(field) (\(reason))"
        case .missingRequiredField(let field):
            "设计包缺少必填字段: \(field)"
        case .missingReferencedFile(let path):
            "设计包缺少引用文件: \(path)"
        case .unsafePath(let path):
            "设计包路径不安全: \(path)"
        case .missingChecksum(let path):
            "设计包缺少文件校验值: \(path)"
        case .unexpectedChecksum(let path):
            "设计包包含未声明文件校验值: \(path)"
        case .checksumMismatch(let path):
            "设计包文件校验失败: \(path)"
        case .importFailed:
            "设计包导入失败"
        }
    }
}

public struct DesignIRValidator: Sendable {
    public init() {}

    public func validate(_ design: DesignIR, packageDirectory: URL? = nil) throws {
        guard design.version == DesignIR.currentVersion else {
            throw DesignPackageError.invalidDesignIRVersion(design.version)
        }
        guard !design.screenName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DesignPackageError.missingRequiredField("screenName")
        }
        guard !design.fileKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DesignPackageError.missingRequiredField("fileKey")
        }
        guard !design.nodeId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DesignPackageError.missingRequiredField("nodeId")
        }
        try validatePositiveFinite(design.viewport.width, field: "viewport.width")
        try validatePositiveFinite(design.viewport.height, field: "viewport.height")
        guard design.rootNode.type == .frame else {
            throw DesignPackageError.invalidField("rootNode.type", "rootNode must be frame")
        }
        try validate(tokens: design.tokens)

        var seenNodeIDs = Set<String>()
        try validate(node: design.rootNode, path: "rootNode", packageDirectory: packageDirectory, seenNodeIDs: &seenNodeIDs)
    }

    private func validate(node: DesignNode, path: String, packageDirectory: URL?, seenNodeIDs: inout Set<String>) throws {
        let trimmedID = node.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            throw DesignPackageError.missingRequiredField("\(path).id")
        }
        guard !seenNodeIDs.contains(trimmedID) else {
            throw DesignPackageError.invalidField("\(path).id", "duplicate node id: \(trimmedID)")
        }
        seenNodeIDs.insert(trimmedID)

        guard !node.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DesignPackageError.missingRequiredField("\(path).name")
        }
        if let bounds = node.bounds {
            try validateFinite(bounds.x, field: "\(path).bounds.x")
            try validateFinite(bounds.y, field: "\(path).bounds.y")
            try validateNonNegativeFinite(bounds.width, field: "\(path).bounds.width")
            try validateNonNegativeFinite(bounds.height, field: "\(path).bounds.height")
        }
        if let layout = node.layout {
            if let spacing = layout.spacing {
                try validateNonNegativeFinite(spacing, field: "\(path).layout.spacing")
            }
            if let padding = layout.padding {
                try validateNonNegativeFinite(padding.top, field: "\(path).layout.padding.top")
                try validateNonNegativeFinite(padding.right, field: "\(path).layout.padding.right")
                try validateNonNegativeFinite(padding.bottom, field: "\(path).layout.padding.bottom")
                try validateNonNegativeFinite(padding.left, field: "\(path).layout.padding.left")
            }
        }
        if let style = node.style {
            try validate(style: style, path: "\(path).style")
        }
        if let confidence = node.confidence, !(0...1).contains(confidence) {
            throw DesignPackageError.invalidField("\(path).confidence", "must be between 0 and 1")
        }
        if let asset = node.asset {
            try validate(asset: asset, path: "\(path).asset", packageDirectory: packageDirectory)
        }
        for (index, child) in node.children.enumerated() {
            try validate(node: child, path: "\(path).children[\(index)]", packageDirectory: packageDirectory, seenNodeIDs: &seenNodeIDs)
        }
    }

    private func validate(asset: DesignAssetRef, path: String, packageDirectory: URL?) throws {
        try DesignPackagePathPolicy.validateAssetPath(asset.localPath, assetsDirectory: DesignPackageStore.assetsDirectoryName)
        let expectedExtension = asset.format.rawValue.lowercased()
        let actualExtension = URL(fileURLWithPath: asset.localPath).pathExtension.lowercased()
        guard actualExtension == expectedExtension else {
            throw DesignPackageError.invalidField("\(path).localPath", "extension must match asset format \(expectedExtension)")
        }

        if let packageDirectory {
            let assetURL = try DesignPackagePathPolicy.fileURL(for: asset.localPath, in: packageDirectory)
            guard FileManager.default.fileExists(atPath: assetURL.path) else {
                throw DesignPackageError.missingReferencedFile(asset.localPath)
            }
        }
    }

    private func validate(style: DesignStyle, path: String) throws {
        if let strokeWidth = style.strokeWidth {
            try validateNonNegativeFinite(strokeWidth, field: "\(path).strokeWidth")
        }
        if let cornerRadius = style.cornerRadius {
            try validateNonNegativeFinite(cornerRadius, field: "\(path).cornerRadius")
        }
        if let opacity = style.opacity, !(0...1).contains(opacity) {
            throw DesignPackageError.invalidField("\(path).opacity", "must be between 0 and 1")
        }
        if let text = style.text {
            if let fontSize = text.fontSize {
                try validatePositiveFinite(fontSize, field: "\(path).text.fontSize")
            }
            if let lineHeight = text.lineHeight {
                try validatePositiveFinite(lineHeight, field: "\(path).text.lineHeight")
            }
        }
    }

    private func validate(tokens: DesignTokenSet) throws {
        var colorNames = Set<String>()
        for token in tokens.colors {
            let name = token.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                throw DesignPackageError.missingRequiredField("tokens.colors[].name")
            }
            guard !colorNames.contains(name) else {
                throw DesignPackageError.invalidField("tokens.colors[].name", "duplicate token name: \(name)")
            }
            colorNames.insert(name)
            guard !token.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw DesignPackageError.missingRequiredField("tokens.colors[\(name)].value")
            }
        }

        var textStyleNames = Set<String>()
        for token in tokens.textStyles {
            let name = token.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                throw DesignPackageError.missingRequiredField("tokens.textStyles[].name")
            }
            guard !textStyleNames.contains(name) else {
                throw DesignPackageError.invalidField("tokens.textStyles[].name", "duplicate token name: \(name)")
            }
            textStyleNames.insert(name)
        }

        for (name, value) in tokens.spacing {
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw DesignPackageError.missingRequiredField("tokens.spacing key")
            }
            try validateNonNegativeFinite(value, field: "tokens.spacing[\(name)]")
        }
        for (name, value) in tokens.radii {
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw DesignPackageError.missingRequiredField("tokens.radii key")
            }
            try validateNonNegativeFinite(value, field: "tokens.radii[\(name)]")
        }
    }

    private func validateFinite(_ value: Double, field: String) throws {
        guard value.isFinite else {
            throw DesignPackageError.invalidField(field, "must be finite")
        }
    }

    private func validatePositiveFinite(_ value: Double, field: String) throws {
        guard value.isFinite, value > 0 else {
            throw DesignPackageError.invalidField(field, "must be a positive finite number")
        }
    }

    private func validateNonNegativeFinite(_ value: Double, field: String) throws {
        guard value.isFinite, value >= 0 else {
            throw DesignPackageError.invalidField(field, "must be a non-negative finite number")
        }
    }
}

private enum DesignPackagePathPolicy {
    static func validateRootFilePath(_ path: String, field: String) throws {
        let normalized = try normalizedRelativePath(path)
        guard !normalized.contains("/") else {
            throw DesignPackageError.invalidField(field, "must be a package-root file")
        }
    }

    static func validateAssetPath(_ path: String, assetsDirectory: String) throws {
        let normalized = try normalizedRelativePath(path)
        let prefix = "\(assetsDirectory)/"
        guard normalized.hasPrefix(prefix), normalized.count > prefix.count else {
            throw DesignPackageError.invalidField("asset.localPath", "must be under \(assetsDirectory)/")
        }
    }

    static func fileURL(for path: String, in baseDirectory: URL) throws -> URL {
        let normalized = try normalizedRelativePath(path)
        let url = baseDirectory.appendingPathComponent(normalized)
        let basePath = baseDirectory.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path == basePath || path.hasPrefix(basePath + "/") else {
            throw DesignPackageError.unsafePath(normalized)
        }
        return url
    }

    static func normalizedRelativePath(_ path: String) throws -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DesignPackageError.unsafePath(path)
        }
        guard !trimmed.hasPrefix("/"), !trimmed.hasPrefix("~"), !trimmed.contains("\\") else {
            throw DesignPackageError.unsafePath(path)
        }
        let components = trimmed.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw DesignPackageError.unsafePath(path)
        }
        return components.joined(separator: "/")
    }
}

public final class DesignPackageStore: Sendable {
    public static let manifestFilename = "manifest.json"
    public static let designFilename = "design.json"
    public static let figmaNodeFilename = "figma-node.json"
    public static let assetsDirectoryName = "assets"

    public let rootDirectory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let validator: DesignIRValidator

    public init(rootDirectory: URL, validator: DesignIRValidator = DesignIRValidator()) {
        self.rootDirectory = rootDirectory
        self.validator = validator
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public func createPackage(_ request: DesignPackageWriteRequest) throws -> PersistedDesignPackage {
        try validator.validate(request.design)
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)

        let packageDirectory = rootDirectory.appendingPathComponent(pathSafe(request.packageID), isDirectory: true)
        if FileManager.default.fileExists(atPath: packageDirectory.path) {
            try FileManager.default.removeItem(at: packageDirectory)
        }
        try FileManager.default.createDirectory(at: packageDirectory, withIntermediateDirectories: true)

        let assetsDirectory = packageDirectory.appendingPathComponent(Self.assetsDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)

        let designURL = packageDirectory.appendingPathComponent(Self.designFilename)
        try encoder.encode(request.design).write(to: designURL)

        var figmaNodeFile: String?
        if let figmaNodeJSON = request.figmaNodeJSON {
            let figmaNodeURL = packageDirectory.appendingPathComponent(Self.figmaNodeFilename)
            try figmaNodeJSON.write(to: figmaNodeURL)
            figmaNodeFile = Self.figmaNodeFilename
        }

        var previewFile: String?
        if let sourcePreviewURL = request.previewFile {
            let ext = sourcePreviewURL.pathExtension.isEmpty ? "png" : sourcePreviewURL.pathExtension
            let filename = "preview.\(ext)"
            try copyFile(sourcePreviewURL, to: packageDirectory.appendingPathComponent(filename))
            previewFile = filename
        }

        for assetURL in request.assetFiles {
            let destination = assetsDirectory.appendingPathComponent(assetURL.lastPathComponent)
            try copyFile(assetURL, to: destination)
        }
        try validator.validate(request.design, packageDirectory: packageDirectory)

        let manifestWithoutChecksums = DesignPackageManifest(
            packageID: pathSafe(request.packageID),
            targetPlatform: request.design.targetPlatform,
            source: request.source,
            figmaNodeFile: figmaNodeFile,
            previewFile: previewFile
        )
        var manifest = manifestWithoutChecksums
        manifest.checksums = try checksums(for: manifestWithoutChecksums, packageDirectory: packageDirectory)

        let manifestURL = packageDirectory.appendingPathComponent(Self.manifestFilename)
        try encoder.encode(manifest).write(to: manifestURL)

        return PersistedDesignPackage(
            manifest: manifest,
            design: request.design,
            packageDirectory: packageDirectory,
            assetsDirectory: assetsDirectory
        )
    }

    public func loadPackage(at packageDirectory: URL) throws -> PersistedDesignPackage {
        let manifestURL = packageDirectory.appendingPathComponent(Self.manifestFilename)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw DesignPackageError.invalidPackageDirectory
        }

        let manifest = try decoder.decode(DesignPackageManifest.self, from: Data(contentsOf: manifestURL))
        try validateManifest(manifest)
        try verifyChecksums(manifest, packageDirectory: packageDirectory)

        let designURL = try DesignPackagePathPolicy.fileURL(for: manifest.designFile, in: packageDirectory)
        guard FileManager.default.fileExists(atPath: designURL.path) else {
            throw DesignPackageError.missingReferencedFile(manifest.designFile)
        }
        let design = try decoder.decode(DesignIR.self, from: Data(contentsOf: designURL))
        try validator.validate(design, packageDirectory: packageDirectory)
        try validateManifest(manifest, matches: design)

        return PersistedDesignPackage(
            manifest: manifest,
            design: design,
            packageDirectory: packageDirectory,
            assetsDirectory: packageDirectory.appendingPathComponent(manifest.assetsDirectory, isDirectory: true)
        )
    }

    public func importPackageDirectory(from sourceDirectory: URL) throws -> PersistedDesignPackage {
        _ = try loadPackage(at: sourceDirectory)
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let destinationURL = uniqueImportedDirectoryName(for: sourceDirectory.lastPathComponent)
        try FileManager.default.copyItem(at: sourceDirectory, to: destinationURL)
        return try loadPackage(at: destinationURL)
    }

    public func importPackageArchive(from archiveURL: URL) throws -> PersistedDesignPackage {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", archiveURL.path, "-d", tempDirectory.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw DesignPackageError.importFailed
        }

        let packageDirectory: URL
        let baseName: String
        if FileManager.default.fileExists(atPath: tempDirectory.appendingPathComponent(Self.manifestFilename).path) {
            packageDirectory = tempDirectory
            baseName = archiveURL.deletingPathExtension().lastPathComponent
        } else {
            let entries = try FileManager.default.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            guard let extractedPackageDirectory = entries.first(where: {
                FileManager.default.fileExists(atPath: $0.appendingPathComponent(Self.manifestFilename).path)
            }) else {
                throw DesignPackageError.invalidPackageDirectory
            }
            packageDirectory = extractedPackageDirectory
            baseName = extractedPackageDirectory.lastPathComponent
        }

        _ = try loadPackage(at: packageDirectory)
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let destinationURL = uniqueImportedDirectoryName(for: baseName)
        try FileManager.default.copyItem(at: packageDirectory, to: destinationURL)
        return try loadPackage(at: destinationURL)
    }

    private func checksums(for manifest: DesignPackageManifest, packageDirectory: URL) throws -> [String: String] {
        let paths = try expectedChecksumPaths(for: manifest, packageDirectory: packageDirectory)

        var result: [String: String] = [:]
        for path in paths.sorted() {
            let url = try DesignPackagePathPolicy.fileURL(for: path, in: packageDirectory)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw DesignPackageError.missingReferencedFile(path)
            }
            result[path] = try sha256Hex(for: url)
        }
        return result
    }

    private func verifyChecksums(_ manifest: DesignPackageManifest, packageDirectory: URL) throws {
        let expectedPaths = Set(try expectedChecksumPaths(for: manifest, packageDirectory: packageDirectory))
        let providedPaths = Set(manifest.checksums.keys)
        for path in expectedPaths.subtracting(providedPaths).sorted() {
            throw DesignPackageError.missingChecksum(path)
        }
        for path in providedPaths.subtracting(expectedPaths).sorted() {
            throw DesignPackageError.unexpectedChecksum(path)
        }

        for path in expectedPaths.sorted() {
            let url = try DesignPackagePathPolicy.fileURL(for: path, in: packageDirectory)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw DesignPackageError.missingReferencedFile(path)
            }
            guard let expected = manifest.checksums[path] else {
                throw DesignPackageError.missingChecksum(path)
            }
            let actual = try sha256Hex(for: url)
            guard actual == expected else {
                throw DesignPackageError.checksumMismatch(path)
            }
        }
    }

    private func expectedChecksumPaths(for manifest: DesignPackageManifest, packageDirectory: URL) throws -> [String] {
        try validateManifestPaths(manifest)
        var paths = [manifest.designFile]
        if let figmaNodeFile = manifest.figmaNodeFile {
            paths.append(figmaNodeFile)
        }
        if let previewFile = manifest.previewFile {
            paths.append(previewFile)
        }
        paths.append(
            contentsOf: try assetPaths(
                in: packageDirectory.appendingPathComponent(manifest.assetsDirectory, isDirectory: true),
                relativeTo: packageDirectory
            )
        )
        return paths.sorted()
    }

    private func assetPaths(in directory: URL, relativeTo baseDirectory: URL) throws -> [String] {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return []
        }
        let entries = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        return try entries.flatMap { entry -> [String] in
            let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            if isDirectory {
                return try assetPaths(in: entry, relativeTo: baseDirectory)
            }
            let relativePath = relativePath(for: entry, baseDirectory: baseDirectory)
            try DesignPackagePathPolicy.validateAssetPath(relativePath, assetsDirectory: Self.assetsDirectoryName)
            return [relativePath]
        }
    }

    private func validateManifest(_ manifest: DesignPackageManifest) throws {
        guard manifest.schemaVersion == DesignPackageManifest.currentSchemaVersion else {
            throw DesignPackageError.invalidSchemaVersion(manifest.schemaVersion)
        }
        try validateManifestPaths(manifest)
        guard !manifest.packageID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DesignPackageError.missingRequiredField("manifest.packageID")
        }
        guard !manifest.source.figmaURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DesignPackageError.missingRequiredField("manifest.source.figmaURL")
        }
        guard !manifest.source.fileKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DesignPackageError.missingRequiredField("manifest.source.fileKey")
        }
        guard !manifest.source.nodeId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DesignPackageError.missingRequiredField("manifest.source.nodeId")
        }
        guard !manifest.source.exporter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DesignPackageError.missingRequiredField("manifest.source.exporter")
        }
        for (path, checksum) in manifest.checksums {
            _ = try DesignPackagePathPolicy.normalizedRelativePath(path)
            guard checksum.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil else {
                throw DesignPackageError.invalidField("manifest.checksums[\(path)]", "must be a lowercase SHA-256 hex digest")
            }
        }
    }

    private func validateManifestPaths(_ manifest: DesignPackageManifest) throws {
        guard manifest.designFile == Self.designFilename else {
            throw DesignPackageError.invalidField("manifest.designFile", "must be \(Self.designFilename)")
        }
        try DesignPackagePathPolicy.validateRootFilePath(manifest.designFile, field: "manifest.designFile")
        if let figmaNodeFile = manifest.figmaNodeFile {
            try DesignPackagePathPolicy.validateRootFilePath(figmaNodeFile, field: "manifest.figmaNodeFile")
        }
        if let previewFile = manifest.previewFile {
            try DesignPackagePathPolicy.validateRootFilePath(previewFile, field: "manifest.previewFile")
        }
        guard manifest.assetsDirectory == Self.assetsDirectoryName else {
            throw DesignPackageError.invalidField("manifest.assetsDirectory", "must be \(Self.assetsDirectoryName)")
        }
        _ = try DesignPackagePathPolicy.normalizedRelativePath(manifest.assetsDirectory)
        guard !manifest.assetsDirectory.contains("/") else {
            throw DesignPackageError.invalidField("manifest.assetsDirectory", "must be a single directory name")
        }
    }

    private func validateManifest(_ manifest: DesignPackageManifest, matches design: DesignIR) throws {
        guard manifest.targetPlatform == design.targetPlatform else {
            throw DesignPackageError.invalidField("manifest.targetPlatform", "must match design.targetPlatform")
        }
        guard manifest.source.fileKey == design.fileKey else {
            throw DesignPackageError.invalidField("manifest.source.fileKey", "must match design.fileKey")
        }
        guard manifest.source.nodeId == design.nodeId else {
            throw DesignPackageError.invalidField("manifest.source.nodeId", "must match design.nodeId")
        }
    }

    private func relativePath(for url: URL, baseDirectory: URL) -> String {
        let basePath = baseDirectory.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(basePath + "/") else {
            return url.lastPathComponent
        }
        return String(path.dropFirst(basePath.count + 1))
    }

    private func sha256Hex(for url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func copyFile(_ sourceURL: URL, to destinationURL: URL) throws {
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    }

    private func uniqueImportedDirectoryName(for baseName: String) -> URL {
        let primaryCandidate = rootDirectory.appendingPathComponent(pathSafe(baseName), isDirectory: true)
        guard !FileManager.default.fileExists(atPath: primaryCandidate.path) else {
            var index = 2
            while true {
                let candidate = rootDirectory.appendingPathComponent("\(pathSafe(baseName))(\(index))", isDirectory: true)
                if !FileManager.default.fileExists(atPath: candidate.path) {
                    return candidate
                }
                index += 1
            }
        }
        return primaryCandidate
    }

    private func pathSafe(_ component: String) -> String {
        let trimmed = component.trimmingCharacters(in: .whitespacesAndNewlines)
        let mapped = trimmed.map { character -> Character in
            if character.isLetter || character.isNumber || character == "-" || character == "_" {
                return character
            }
            return "-"
        }
        let safe = String(mapped)
            .replacingOccurrences(of: "-{2,}", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return safe.isEmpty ? UUID().uuidString.lowercased() : safe
    }
}
