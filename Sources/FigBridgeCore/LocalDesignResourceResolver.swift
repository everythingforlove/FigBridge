import Foundation

public enum LocalDesignResourceDefaults {
    public static let semanticColorEnvironmentKey = "FIGBRIDGE_SEMANTIC_COLOR_DIR"
    public static let imageResourceEnvironmentKey = "FIGBRIDGE_IMAGE_RESOURCE_DIR"

    public static let semanticColorDirectory = URL(fileURLWithPath: "/Users/xiejialin/Documents/语义颜色", isDirectory: true)
    public static let imageResourceDirectory = URL(fileURLWithPath: "/Users/xiejialin/Desktop/project/image_resource/图标导出0521_下划线命名", isDirectory: true)
}

public struct LocalDesignResourceResolver: Sendable, Equatable {
    public var semanticColors: SemanticColorTokenLibrary
    public var imageAssets: ImageAssetLibrary

    public init(
        semanticColors: SemanticColorTokenLibrary = .empty,
        imageAssets: ImageAssetLibrary = .empty
    ) {
        self.semanticColors = semanticColors
        self.imageAssets = imageAssets
    }

    public static let empty = LocalDesignResourceResolver()

    public static func loadDefault(fileManager: FileManager = .default) -> LocalDesignResourceResolver {
        let environment = ProcessInfo.processInfo.environment
        let colorDirectory = environment[LocalDesignResourceDefaults.semanticColorEnvironmentKey]
            .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
            ?? LocalDesignResourceDefaults.semanticColorDirectory
        let imageDirectory = environment[LocalDesignResourceDefaults.imageResourceEnvironmentKey]
            .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
            ?? LocalDesignResourceDefaults.imageResourceDirectory

        return LocalDesignResourceResolver(
            semanticColors: (try? SemanticColorTokenLibrary.load(from: colorDirectory, fileManager: fileManager)) ?? .empty,
            imageAssets: (try? ImageAssetLibrary.load(from: imageDirectory, fileManager: fileManager)) ?? .empty
        )
    }
}

public enum SemanticColorUsage: Sendable {
    case fill
    case stroke
    case text
    case icon
}

public struct SemanticColorToken: Equatable, Sendable {
    public var name: String
    public var value: String
    public var alpha: Double
    public var variableID: String?
    public var groupName: String
    public var sourceFileName: String
    public var scopes: [String]

    public init(
        name: String,
        value: String,
        alpha: Double = 1,
        variableID: String? = nil,
        groupName: String = "",
        sourceFileName: String = "",
        scopes: [String] = []
    ) {
        self.name = name
        self.value = SemanticColorTokenLibrary.normalizedHex(value) ?? value
        self.alpha = alpha
        self.variableID = variableID
        self.groupName = groupName
        self.sourceFileName = sourceFileName
        self.scopes = scopes
    }

    public var designValue: String {
        SemanticColorTokenLibrary.hexWithAlpha(value, alpha: alpha) ?? value
    }
}

public struct SemanticColorTokenLibrary: Equatable, Sendable {
    public var tokens: [SemanticColorToken]

    private let tokensByVariableID: [String: [SemanticColorToken]]
    private let tokensByColor: [ColorKey: [SemanticColorToken]]

    public init(tokens: [SemanticColorToken]) {
        self.tokens = tokens
        var variableLookup: [String: [SemanticColorToken]] = [:]
        var colorLookup: [ColorKey: [SemanticColorToken]] = [:]

        for token in tokens {
            if let variableID = token.variableID?.trimmingCharacters(in: .whitespacesAndNewlines), !variableID.isEmpty {
                variableLookup[variableID, default: []].append(token)
            }
            if let key = ColorKey(hex: token.value, alpha: token.alpha) {
                colorLookup[key, default: []].append(token)
            }
        }

        self.tokensByVariableID = variableLookup
        self.tokensByColor = colorLookup
    }

    public static let empty = SemanticColorTokenLibrary(tokens: [])

    public var isEmpty: Bool {
        tokens.isEmpty
    }

    public static func load(from directory: URL, fileManager: FileManager = .default) throws -> SemanticColorTokenLibrary {
        guard fileManager.fileExists(atPath: directory.path) else {
            return .empty
        }

        let entries = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        let tokenFiles = entries
            .filter { $0.lastPathComponent.hasSuffix(".tokens.json") || $0.pathExtension.lowercased() == "json" }
            .sorted { preferredTokenFileOrder($0.lastPathComponent, $1.lastPathComponent) }

        let tokens = try tokenFiles.flatMap { file in
            try loadTokens(from: file)
        }

        return SemanticColorTokenLibrary(tokens: tokens)
    }

    public func resolve(
        variableID: String?,
        colorHex: String,
        alpha: Double,
        usage: SemanticColorUsage
    ) -> SemanticColorToken? {
        let normalizedVariableID = variableID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let variableCandidates = normalizedVariableID.flatMap { $0.isEmpty ? nil : tokensByVariableID[$0] } ?? []
        if let match = bestMatch(in: variableCandidates, colorHex: colorHex, alpha: alpha, usage: usage, preferVariableMatch: true) {
            return match
        }

        guard let key = ColorKey(hex: colorHex, alpha: alpha),
              let colorCandidates = tokensByColor[key] else {
            return nil
        }
        return bestMatch(in: colorCandidates, colorHex: colorHex, alpha: alpha, usage: usage, preferVariableMatch: false)
    }

    public static func normalizedHex(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("#") else {
            return nil
        }
        let hex = String(trimmed.dropFirst())
        guard hex.count == 6 || hex.count == 8,
              hex.allSatisfy({ $0.isHexDigit }) else {
            return nil
        }
        return "#\(hex.uppercased())"
    }

    public static func hexWithAlpha(_ value: String, alpha: Double) -> String? {
        guard let hex = normalizedHex(value) else {
            return nil
        }
        let normalizedAlpha = min(max(alpha, 0), 1)
        guard normalizedAlpha < 0.999 else {
            return hex
        }
        let alphaByte = Int((normalizedAlpha * 255).rounded())
        let rgb = String(hex.dropFirst()).suffix(6)
        return String(format: "#%02X%@", alphaByte, String(rgb))
    }

    private static func loadTokens(from file: URL) throws -> [SemanticColorToken] {
        let data = try Data(contentsOf: file)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            return []
        }

        var result: [SemanticColorToken] = []
        collectTokens(in: dictionary, groupName: "", sourceFileName: file.lastPathComponent, result: &result)
        return result
    }

    private static func collectTokens(
        in dictionary: [String: Any],
        groupName: String,
        sourceFileName: String,
        result: inout [SemanticColorToken]
    ) {
        for key in dictionary.keys.sorted() {
            guard let value = dictionary[key] else {
                continue
            }
            guard let nested = value as? [String: Any] else {
                continue
            }

            if let token = token(named: key, dictionary: nested, groupName: groupName, sourceFileName: sourceFileName) {
                result.append(token)
            } else {
                let nextGroupName = groupName.isEmpty ? key : "\(groupName)/\(key)"
                collectTokens(in: nested, groupName: nextGroupName, sourceFileName: sourceFileName, result: &result)
            }
        }
    }

    private static func token(
        named name: String,
        dictionary: [String: Any],
        groupName: String,
        sourceFileName: String
    ) -> SemanticColorToken? {
        guard (dictionary["$type"] as? String)?.lowercased() == "color",
              let value = dictionary["$value"] as? [String: Any],
              let hex = value["hex"] as? String,
              let normalizedHex = normalizedHex(hex) else {
            return nil
        }

        let alpha = number(from: value["alpha"]) ?? 1
        let extensions = dictionary["$extensions"] as? [String: Any]
        let variableID = extensions?["com.figma.variableId"] as? String
        let scopes = extensions?["com.figma.scopes"] as? [String] ?? []

        return SemanticColorToken(
            name: name,
            value: normalizedHex,
            alpha: alpha,
            variableID: variableID,
            groupName: groupName,
            sourceFileName: sourceFileName,
            scopes: scopes
        )
    }

    private static func number(from value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            return number.doubleValue
        case let double as Double:
            return double
        case let string as String:
            return Double(string)
        default:
            return nil
        }
    }

    private static func preferredTokenFileOrder(_ left: String, _ right: String) -> Bool {
        let leftScore = fileOrderScore(left)
        let rightScore = fileOrderScore(right)
        if leftScore != rightScore {
            return leftScore < rightScore
        }
        return left.localizedStandardCompare(right) == .orderedAscending
    }

    private static func fileOrderScore(_ name: String) -> Int {
        let lower = name.lowercased()
        if lower.contains("light") {
            return 0
        }
        if lower.contains("dark") {
            return 1
        }
        return 2
    }

    private func bestMatch(
        in candidates: [SemanticColorToken],
        colorHex: String,
        alpha: Double,
        usage: SemanticColorUsage,
        preferVariableMatch: Bool
    ) -> SemanticColorToken? {
        guard !candidates.isEmpty else {
            return nil
        }

        return candidates.max { left, right in
            score(left, colorHex: colorHex, alpha: alpha, usage: usage, preferVariableMatch: preferVariableMatch)
                < score(right, colorHex: colorHex, alpha: alpha, usage: usage, preferVariableMatch: preferVariableMatch)
        }
    }

    private func score(
        _ token: SemanticColorToken,
        colorHex: String,
        alpha: Double,
        usage: SemanticColorUsage,
        preferVariableMatch: Bool
    ) -> Int {
        var result = preferVariableMatch ? 100 : 0
        if ColorKey(hex: token.value, alpha: token.alpha) == ColorKey(hex: colorHex, alpha: alpha) {
            result += 40
        }
        if matchesUsage(token, usage: usage) {
            result += 20
        }
        if token.sourceFileName.lowercased().contains("light") {
            result += 4
        }
        if !token.name.contains(" ") {
            result += 1
        }
        return result
    }

    private func matchesUsage(_ token: SemanticColorToken, usage: SemanticColorUsage) -> Bool {
        let name = token.name.lowercased()
        let group = token.groupName.lowercased()
        let scopes = Set(token.scopes.map { $0.uppercased() })

        switch usage {
        case .text:
            return scopes.contains("TEXT_FILL") || group.contains("文本") || name.contains("text")
        case .icon:
            return group.contains("图标") || name.contains("icon")
        case .stroke:
            return scopes.contains("STROKE") || group.contains("描边") || name.contains("border")
        case .fill:
            return scopes.contains("FRAME_FILL")
                || scopes.contains("SHAPE_FILL")
                || group.contains("背景")
                || name.contains("surface")
                || name.contains("background")
                || name.contains("button-bg")
        }
    }

    private struct ColorKey: Hashable {
        var hex: String
        var alphaBucket: Int

        init?(hex: String, alpha: Double) {
            guard let normalizedHex = SemanticColorTokenLibrary.normalizedHex(hex) else {
                return nil
            }
            self.hex = String(normalizedHex.suffix(6))
            self.alphaBucket = Int((min(max(alpha, 0), 1) * 1000).rounded())
        }
    }
}

public struct ImageAssetMatch: Equatable, Sendable {
    public var assetName: String
    public var url: URL
    public var kind: FigmaResourceItem.ResourceKind
    public var format: ExportFormat

    public init(assetName: String, url: URL, kind: FigmaResourceItem.ResourceKind, format: ExportFormat) {
        self.assetName = assetName
        self.url = url
        self.kind = kind
        self.format = format
    }
}

public struct ImageAssetLibrary: Equatable, Sendable {
    public var assets: [ImageAssetMatch]

    private let exactLookup: [String: ImageAssetMatch]
    private let compactLookup: [String: ImageAssetMatch]

    public init(assets: [ImageAssetMatch]) {
        self.assets = assets

        var exact: [String: ImageAssetMatch] = [:]
        var compact: [String: ImageAssetMatch] = [:]
        for asset in assets {
            let key = LocalResourceName.normalized(asset.assetName)
            exact[key] = exact[key] ?? asset
            compact[LocalResourceName.compactKey(key)] = compact[LocalResourceName.compactKey(key)] ?? asset
        }
        self.exactLookup = exact
        self.compactLookup = compact
    }

    public static let empty = ImageAssetLibrary(assets: [])

    public var isEmpty: Bool {
        assets.isEmpty
    }

    public static func load(from directory: URL, fileManager: FileManager = .default) throws -> ImageAssetLibrary {
        guard fileManager.fileExists(atPath: directory.path) else {
            return .empty
        }

        let supportedExtensions = Set(["svg", "png"])
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return .empty
        }

        var assets: [ImageAssetMatch] = []
        for case let file as URL in enumerator {
            let resourceValues = try? file.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues?.isRegularFile == true else {
                continue
            }
            let ext = file.pathExtension.lowercased()
            guard supportedExtensions.contains(ext),
                  let format = ExportFormat(rawValue: ext) else {
                continue
            }

            let rawName = file.deletingPathExtension().lastPathComponent
            let assetName = LocalResourceName.normalized(rawName)
            let kind: FigmaResourceItem.ResourceKind = ext == "svg" || assetName.hasPrefix("icon_") ? .icon : .image
            assets.append(ImageAssetMatch(assetName: assetName, url: file, kind: kind, format: format))
        }

        return ImageAssetLibrary(assets: assets.sorted { $0.assetName.localizedStandardCompare($1.assetName) == .orderedAscending })
    }

    public func match(nodeName: String) -> ImageAssetMatch? {
        for candidate in LocalResourceName.candidates(from: nodeName) {
            if let exact = exactLookup[candidate] {
                return exact
            }
            if let compact = compactLookup[LocalResourceName.compactKey(candidate)] {
                return compact
            }
        }
        return nil
    }
}

public enum LocalResourceName {
    public static func candidates(from name: String) -> [String] {
        let parts = name
            .split { character in
                character == "/" || character == "\\" || character == ":" || character == "#" || character == "(" || character == ")"
            }
            .map(String.init)

        var candidates: [String] = [normalized(name)]
        candidates.append(contentsOf: parts.map(normalized))

        if let iconRange = normalized(name).range(of: #"icon_[a-z0-9_\p{Han}]+"#, options: .regularExpression) {
            candidates.append(String(normalized(name)[iconRange]))
        }

        var seen = Set<String>()
        return candidates.filter { candidate in
            guard !candidate.isEmpty, !seen.contains(candidate) else {
                return false
            }
            seen.insert(candidate)
            return true
        }
    }

    public static func normalized(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName: String
        if let dotIndex = trimmed.lastIndex(of: ".") {
            let extensionText = trimmed[trimmed.index(after: dotIndex)...].lowercased()
            if ["svg", "png", "jpg", "jpeg", "webp"].contains(String(extensionText)) {
                baseName = String(trimmed[..<dotIndex])
            } else {
                baseName = trimmed
            }
        } else {
            baseName = trimmed
        }
        let mapped = baseName.lowercased().map { character -> Character in
            if character.isLetter || character.isNumber {
                return character
            }
            return "_"
        }
        return String(mapped)
            .replacingOccurrences(of: "_{2,}", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    public static func compactKey(_ value: String) -> String {
        normalized(value).replacingOccurrences(of: "_", with: "")
    }
}
