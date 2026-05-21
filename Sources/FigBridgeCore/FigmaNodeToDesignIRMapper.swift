import Foundation

public struct FigmaNodeToDesignIRMapper: Sendable {
    public init() {}

    public func map(
        document: FigmaDocumentNode,
        fileKey: String,
        nodeId: String,
        resources: [FigmaResourceItem] = []
    ) -> DesignIR {
        let resourceLookup = Dictionary(uniqueKeysWithValues: resources.map { ($0.name, $0) })
        let rootNode = mapNode(document, resourceLookup: resourceLookup)
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
            rootNode: rootNode,
            warnings: warnings
        )
    }

    private func mapNode(_ node: FigmaDocumentNode, resourceLookup: [String: FigmaResourceItem]) -> DesignNode {
        let visibleFills = visiblePaints(node.fills)
        let visibleStrokes = visiblePaints(node.strokes)
        let imageFill = visibleFills.first { $0.type.uppercased() == "IMAGE" }
        let type = designType(for: node, imageFill: imageFill)
        let style = mapStyle(node: node, visibleFills: visibleFills, visibleStrokes: visibleStrokes)
        let children = node.children.map { mapNode($0, resourceLookup: resourceLookup) }

        var warnings = reviewWarnings(for: node, type: type, visibleFills: visibleFills, visibleStrokes: visibleStrokes)
        var asset: DesignAssetRef?
        if type == .image, let imageRef = imageFill?.imageRef {
            if let resource = resourceLookup[imageRef], let localPath = resource.localPath {
                asset = DesignAssetRef(name: resource.name, localPath: localPath, kind: resource.kind, format: resource.format)
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

    private func designType(for node: FigmaDocumentNode, imageFill: FigmaPaint?) -> DesignNodeType {
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

    private func mapStyle(node: FigmaDocumentNode, visibleFills: [FigmaPaint], visibleStrokes: [FigmaPaint]) -> DesignStyle? {
        let fill = firstSolidColor(in: visibleFills)
        let stroke = firstSolidColor(in: visibleStrokes)
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
        visibleFills: [FigmaPaint],
        visibleStrokes: [FigmaPaint]
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

    private func visiblePaints(_ paints: [FigmaPaint]) -> [FigmaPaint] {
        paints.filter { $0.visible ?? true }
    }

    private func firstSolidColor(in paints: [FigmaPaint]) -> String? {
        paints.first { $0.type.uppercased() == "SOLID" }?.color.map(hexColor)
    }

    private func hexColor(_ color: FigmaColor) -> String {
        let r = Int((color.r.clampedToUnit * 255).rounded())
        let g = Int((color.g.clampedToUnit * 255).rounded())
        let b = Int((color.b.clampedToUnit * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    private func collectWarnings(from node: DesignNode) -> [String] {
        node.warnings + node.children.flatMap(collectWarnings)
    }
}

private extension Double {
    var clampedToUnit: Double {
        min(max(self, 0), 1)
    }
}
