import Foundation

public struct FigmaNodeToDesignIRMapper: Sendable {
    public init() {}

    public func map(
        document: FigmaDocumentNode,
        fileKey: String,
        nodeId: String,
        resources: [FigmaResourceItem] = [],
        localResources: LocalDesignResourceResolver = .empty
    ) -> DesignIR {
        let context = MappingContext(resources: resources, semanticColors: localResources.semanticColors)
        let rootNode = mapNode(document, context: context)
        let viewport = DesignSize(
            width: max(rootNode.bounds?.width ?? 1, 1),
            height: max(rootNode.bounds?.height ?? 1, 1)
        )
        let warnings = collectWarnings(from: rootNode)

        return DesignIR(
            screenName: document.name.isEmpty ? nodeId : document.name,
            fileKey: fileKey,
            nodeId: nodeId,
            viewport: viewport,
            tokens: DesignTokenSet(colors: context.colorTokens),
            rootNode: rootNode,
            warnings: warnings
        )
    }

    private func mapNode(_ node: FigmaDocumentNode, context: MappingContext) -> DesignNode {
        let visibleFills = visiblePaints(node.fills)
        let visibleStrokes = visiblePaints(node.strokes)
        let imageFill = visibleFills.first { $0.paint.type.uppercased() == "IMAGE" }
        let namedResource = context.resourceMatching(nodeName: node.name)
        let type = designType(for: node, imageFill: imageFill?.paint, namedResource: namedResource)
        let style = mapStyle(node: node, type: type, visibleFills: visibleFills, visibleStrokes: visibleStrokes, context: context)
        let children = namedResource == nil ? node.children.map { mapNode($0, context: context) } : []

        var warnings = reviewWarnings(for: node, type: type, visibleFills: visibleFills, visibleStrokes: visibleStrokes)
        var asset: DesignAssetRef?
        if let namedResource, let localPath = namedResource.localPath {
            asset = DesignAssetRef(
                name: namedResource.name,
                localPath: DesignIRAssetPathNormalizer.packageRelativeAssetPath(fromCachedPath: localPath),
                kind: namedResource.kind,
                format: namedResource.format
            )
        } else if [.image, .icon].contains(type), let imageRef = imageFill?.paint.imageRef {
            if let resource = context.imageRefLookup[imageRef], let localPath = resource.localPath {
                asset = DesignAssetRef(
                    name: resource.name,
                    localPath: DesignIRAssetPathNormalizer.packageRelativeAssetPath(fromCachedPath: localPath),
                    kind: resource.kind,
                    format: resource.format
                )
            } else {
                warnings.append("Image fill \(imageRef) has no cached asset")
            }
        }

        let needsReview = !warnings.isEmpty || children.contains(where: \.needsReview)
        return DesignNode(
            id: node.id,
            name: node.name.isEmpty ? node.id : node.name,
            type: type,
            bounds: node.bounds,
            layout: mapLayout(node),
            style: style,
            text: type == .text ? node.characters : nil,
            asset: asset,
            children: children,
            needsReview: needsReview,
            confidence: needsReview ? 0.72 : 0.95,
            warnings: warnings
        )
    }

    private func designType(for node: FigmaDocumentNode, imageFill: FigmaPaint?, namedResource: FigmaResourceItem?) -> DesignNodeType {
        if let namedResource {
            return namedResource.kind == .icon ? .icon : .image
        }

        switch node.type.uppercased() {
        case "FRAME", "COMPONENT", "COMPONENT_SET", "INSTANCE", "GROUP", "SECTION":
            return .frame
        case "TEXT":
            return .text
        case "RECTANGLE", "VECTOR", "ELLIPSE", "POLYGON", "STAR":
            return imageFill == nil ? .unknown : .image
        default:
            return imageFill == nil ? .unknown : .image
        }
    }

    private func mapLayout(_ node: FigmaDocumentNode) -> DesignLayout? {
        let mode: DesignLayoutMode
        switch node.layoutMode?.uppercased() {
        case "HORIZONTAL":
            mode = .horizontal
        case "VERTICAL":
            mode = .vertical
        case "NONE":
            mode = node.children.isEmpty ? .none : .absolute
        case nil:
            mode = node.children.isEmpty ? .none : .absolute
        default:
            mode = .none
        }

        let padding = DesignInsets(
            top: node.paddingTop ?? 0,
            right: node.paddingRight ?? 0,
            bottom: node.paddingBottom ?? 0,
            left: node.paddingLeft ?? 0
        )
        let hasPadding = padding.top > 0 || padding.right > 0 || padding.bottom > 0 || padding.left > 0
        let spacing = node.itemSpacing

        guard mode != .none || hasPadding || spacing != nil else {
            return nil
        }

        return DesignLayout(
            mode: mode,
            spacing: spacing,
            padding: hasPadding ? padding : nil
        )
    }

    private func mapStyle(
        node: FigmaDocumentNode,
        type: DesignNodeType,
        visibleFills: [VisiblePaint],
        visibleStrokes: [VisiblePaint],
        context: MappingContext
    ) -> DesignStyle? {
        let colorUsage: SemanticColorUsage = switch type {
        case .text:
            .text
        case .icon:
            .icon
        default:
            .fill
        }
        let fill = firstSolidColor(in: visibleFills, variables: node.boundVariables?.fills ?? [], usage: colorUsage, context: context)
        let stroke = firstSolidColor(in: visibleStrokes, variables: node.boundVariables?.strokes ?? [], usage: .stroke, context: context)
        let textStyle = node.type.uppercased() == "TEXT" ? mapTextStyle(node: node, color: fill) : nil

        guard fill != nil
            || stroke != nil
            || node.strokeWeight != nil
            || node.cornerRadius != nil
            || node.opacity != nil
            || textStyle != nil
        else {
            return nil
        }

        return DesignStyle(
            fill: node.type.uppercased() == "TEXT" ? nil : fill,
            stroke: stroke,
            strokeWidth: node.strokeWeight,
            cornerRadius: node.cornerRadius,
            opacity: node.opacity,
            text: textStyle
        )
    }

    private func mapTextStyle(node: FigmaDocumentNode, color: String?) -> DesignTextStyle {
        DesignTextStyle(
            fontFamily: node.style?.fontFamily,
            fontSize: node.style?.fontSize,
            fontWeight: node.style?.fontWeight.map { String(Int($0)) },
            lineHeight: node.style?.lineHeightPx,
            color: color,
            textAlign: node.style?.textAlignHorizontal?.lowercased()
        )
    }

    private func reviewWarnings(
        for node: FigmaDocumentNode,
        type: DesignNodeType,
        visibleFills: [VisiblePaint],
        visibleStrokes: [VisiblePaint]
    ) -> [String] {
        var warnings: [String] = []
        if type == .unknown {
            warnings.append("Unsupported Figma node type \(node.type)")
        }
        if visibleFills.count > 1 {
            warnings.append("Multiple visible fills require review")
        }
        if visibleStrokes.count > 1 {
            warnings.append("Multiple visible strokes require review")
        }
        if let layoutMode = node.layoutMode, !["NONE", "HORIZONTAL", "VERTICAL"].contains(layoutMode.uppercased()) {
            warnings.append("Unsupported layoutMode \(layoutMode)")
        }
        return warnings
    }

    private func visiblePaints(_ paints: [FigmaPaint]) -> [VisiblePaint] {
        paints.enumerated().compactMap { index, paint in
            guard paint.visible ?? true else {
                return nil
            }
            return VisiblePaint(index: index, paint: paint)
        }
    }

    private func firstSolidColor(
        in paints: [VisiblePaint],
        variables: [FigmaVariableAlias],
        usage: SemanticColorUsage,
        context: MappingContext
    ) -> String? {
        guard let visiblePaint = paints.first(where: { $0.paint.type.uppercased() == "SOLID" }),
              let color = visiblePaint.paint.color else {
            return nil
        }

        let alpha = effectiveAlpha(color: color, paintOpacity: visiblePaint.paint.opacity)
        let rgbHex = rgbHexColor(color)
        let displayValue = hexColor(color, paintOpacity: visiblePaint.paint.opacity)
        let variableID = variables.indices.contains(visiblePaint.index) ? variables[visiblePaint.index].id : nil

        if let token = context.semanticColors.resolve(variableID: variableID, colorHex: rgbHex, alpha: alpha, usage: usage) {
            return context.register(colorToken: token, resolvedValue: displayValue)
        }

        return displayValue
    }

    private func rgbHexColor(_ color: FigmaColor) -> String {
        let r = Int((color.r.clampedToUnit * 255).rounded())
        let g = Int((color.g.clampedToUnit * 255).rounded())
        let b = Int((color.b.clampedToUnit * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    private func hexColor(_ color: FigmaColor, paintOpacity: Double?) -> String {
        let rgb = rgbHexColor(color)
        let alpha = effectiveAlpha(color: color, paintOpacity: paintOpacity)
        return SemanticColorTokenLibrary.hexWithAlpha(rgb, alpha: alpha) ?? rgb
    }

    private func effectiveAlpha(color: FigmaColor, paintOpacity: Double?) -> Double {
        color.a.clampedToUnit * (paintOpacity ?? 1).clampedToUnit
    }

    private func collectWarnings(from node: DesignNode) -> [String] {
        node.warnings + node.children.flatMap(collectWarnings)
    }
}

private struct VisiblePaint {
    var index: Int
    var paint: FigmaPaint
}

private final class MappingContext {
    let imageRefLookup: [String: FigmaResourceItem]
    let semanticColors: SemanticColorTokenLibrary

    private let namedResourceLookup: [String: FigmaResourceItem]
    private var colorTokensByName: [String: DesignColorToken] = [:]

    init(resources: [FigmaResourceItem], semanticColors: SemanticColorTokenLibrary) {
        var imageRefLookup: [String: FigmaResourceItem] = [:]
        for resource in resources {
            imageRefLookup[resource.name] = imageRefLookup[resource.name] ?? resource
        }
        self.imageRefLookup = imageRefLookup
        self.semanticColors = semanticColors

        var namedLookup: [String: FigmaResourceItem] = [:]
        for resource in resources {
            guard resource.localPath != nil else {
                continue
            }
            let key = LocalResourceName.normalized(resource.name)
            namedLookup[key] = namedLookup[key] ?? resource
            namedLookup[LocalResourceName.compactKey(key)] = namedLookup[LocalResourceName.compactKey(key)] ?? resource
        }
        self.namedResourceLookup = namedLookup
    }

    var colorTokens: [DesignColorToken] {
        colorTokensByName.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func resourceMatching(nodeName: String) -> FigmaResourceItem? {
        for candidate in LocalResourceName.candidates(from: nodeName) {
            if let exact = namedResourceLookup[candidate] {
                return exact
            }
            if let compact = namedResourceLookup[LocalResourceName.compactKey(candidate)] {
                return compact
            }
        }
        return nil
    }

    func register(colorToken token: SemanticColorToken, resolvedValue: String) -> String {
        colorTokensByName[token.name] = colorTokensByName[token.name] ?? DesignColorToken(name: token.name, value: resolvedValue)
        return token.name
    }
}

private extension Double {
    var clampedToUnit: Double {
        min(max(self, 0), 1)
    }
}
