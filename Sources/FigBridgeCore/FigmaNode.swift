import Foundation

public struct FigmaDocumentNode: Decodable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var type: String
    public var bounds: DesignRect?
    public var layoutMode: String?
    public var paddingLeft: Double?
    public var paddingRight: Double?
    public var paddingTop: Double?
    public var paddingBottom: Double?
    public var itemSpacing: Double?
    public var fills: [FigmaPaint]
    public var strokes: [FigmaPaint]
    public var strokeWeight: Double?
    public var cornerRadius: Double?
    public var opacity: Double?
    public var characters: String?
    public var style: FigmaTextStyle?
    public var boundVariables: FigmaBoundVariables?
    public var children: [FigmaDocumentNode]

    public init(
        id: String,
        name: String,
        type: String,
        bounds: DesignRect? = nil,
        layoutMode: String? = nil,
        paddingLeft: Double? = nil,
        paddingRight: Double? = nil,
        paddingTop: Double? = nil,
        paddingBottom: Double? = nil,
        itemSpacing: Double? = nil,
        fills: [FigmaPaint] = [],
        strokes: [FigmaPaint] = [],
        strokeWeight: Double? = nil,
        cornerRadius: Double? = nil,
        opacity: Double? = nil,
        characters: String? = nil,
        style: FigmaTextStyle? = nil,
        boundVariables: FigmaBoundVariables? = nil,
        children: [FigmaDocumentNode] = []
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.bounds = bounds
        self.layoutMode = layoutMode
        self.paddingLeft = paddingLeft
        self.paddingRight = paddingRight
        self.paddingTop = paddingTop
        self.paddingBottom = paddingBottom
        self.itemSpacing = itemSpacing
        self.fills = fills
        self.strokes = strokes
        self.strokeWeight = strokeWeight
        self.cornerRadius = cornerRadius
        self.opacity = opacity
        self.characters = characters
        self.style = style
        self.boundVariables = boundVariables
        self.children = children
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? "UNKNOWN"
        bounds = try container.decodeIfPresent(DesignRect.self, forKey: .absoluteBoundingBox)
            ?? container.decodeIfPresent(DesignRect.self, forKey: .bounds)
        layoutMode = try container.decodeIfPresent(String.self, forKey: .layoutMode)
        paddingLeft = try container.decodeIfPresent(Double.self, forKey: .paddingLeft)
        paddingRight = try container.decodeIfPresent(Double.self, forKey: .paddingRight)
        paddingTop = try container.decodeIfPresent(Double.self, forKey: .paddingTop)
        paddingBottom = try container.decodeIfPresent(Double.self, forKey: .paddingBottom)
        itemSpacing = try container.decodeIfPresent(Double.self, forKey: .itemSpacing)
        fills = try container.decodeIfPresent([FigmaPaint].self, forKey: .fills) ?? []
        strokes = try container.decodeIfPresent([FigmaPaint].self, forKey: .strokes) ?? []
        strokeWeight = try container.decodeIfPresent(Double.self, forKey: .strokeWeight)
        cornerRadius = try container.decodeIfPresent(Double.self, forKey: .cornerRadius)
        opacity = try container.decodeIfPresent(Double.self, forKey: .opacity)
        characters = try container.decodeIfPresent(String.self, forKey: .characters)
        style = try container.decodeIfPresent(FigmaTextStyle.self, forKey: .style)
        boundVariables = try container.decodeIfPresent(FigmaBoundVariables.self, forKey: .boundVariables)
        children = try container.decodeIfPresent([FigmaDocumentNode].self, forKey: .children) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case type
        case absoluteBoundingBox
        case bounds
        case layoutMode
        case paddingLeft
        case paddingRight
        case paddingTop
        case paddingBottom
        case itemSpacing
        case fills
        case strokes
        case strokeWeight
        case cornerRadius
        case opacity
        case characters
        case style
        case boundVariables
        case children
    }
}

public struct FigmaPaint: Decodable, Equatable, Sendable {
    public var type: String
    public var color: FigmaColor?
    public var opacity: Double?
    public var visible: Bool?
    public var imageRef: String?

    public init(type: String, color: FigmaColor? = nil, opacity: Double? = nil, visible: Bool? = nil, imageRef: String? = nil) {
        self.type = type
        self.color = color
        self.opacity = opacity
        self.visible = visible
        self.imageRef = imageRef
    }
}

public struct FigmaColor: Decodable, Equatable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        r = try container.decode(Double.self, forKey: .r)
        g = try container.decode(Double.self, forKey: .g)
        b = try container.decode(Double.self, forKey: .b)
        a = try container.decodeIfPresent(Double.self, forKey: .a) ?? 1
    }

    enum CodingKeys: String, CodingKey {
        case r
        case g
        case b
        case a
    }
}

public struct FigmaTextStyle: Decodable, Equatable, Sendable {
    public var fontFamily: String?
    public var fontPostScriptName: String?
    public var fontWeight: Double?
    public var fontSize: Double?
    public var lineHeightPx: Double?
    public var textAlignHorizontal: String?

    public init(
        fontFamily: String? = nil,
        fontPostScriptName: String? = nil,
        fontWeight: Double? = nil,
        fontSize: Double? = nil,
        lineHeightPx: Double? = nil,
        textAlignHorizontal: String? = nil
    ) {
        self.fontFamily = fontFamily
        self.fontPostScriptName = fontPostScriptName
        self.fontWeight = fontWeight
        self.fontSize = fontSize
        self.lineHeightPx = lineHeightPx
        self.textAlignHorizontal = textAlignHorizontal
    }
}

public struct FigmaVariableAlias: Decodable, Equatable, Sendable {
    public var type: String?
    public var id: String

    public init(type: String? = nil, id: String) {
        self.type = type
        self.id = id
    }
}

public struct FigmaBoundVariables: Decodable, Equatable, Sendable {
    public var fills: [FigmaVariableAlias]
    public var strokes: [FigmaVariableAlias]
    public var variablesByField: [String: [FigmaVariableAlias]]

    public init(
        fills: [FigmaVariableAlias] = [],
        strokes: [FigmaVariableAlias] = [],
        variablesByField: [String: [FigmaVariableAlias]] = [:]
    ) {
        self.fills = fills
        self.strokes = strokes
        self.variablesByField = variablesByField
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        var fields: [String: [FigmaVariableAlias]] = [:]

        for key in container.allKeys {
            if let aliases = try Self.decodeAliases(from: container, forKey: key) {
                fields[key.stringValue] = aliases
            }
        }

        fills = fields["fills"] ?? []
        strokes = fields["strokes"] ?? []
        variablesByField = fields
    }

    public func variableID(for field: String, index: Int = 0) -> String? {
        guard let aliases = variablesByField[field], aliases.indices.contains(index) else {
            return nil
        }
        return aliases[index].id
    }

    private static func decodeAliases(
        from container: KeyedDecodingContainer<DynamicCodingKey>,
        forKey key: DynamicCodingKey
    ) throws -> [FigmaVariableAlias]? {
        if let aliases = try? container.decode([FigmaVariableAlias].self, forKey: key) {
            return aliases
        }
        if let alias = try? container.decode(FigmaVariableAlias.self, forKey: key) {
            return [alias]
        }
        return nil
    }
}

private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}
