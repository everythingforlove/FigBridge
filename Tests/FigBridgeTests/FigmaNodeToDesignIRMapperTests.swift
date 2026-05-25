import Foundation
import Testing
@testable import FigBridgeCore

struct FigmaNodeToDesignIRMapperTests {
    @Test func mapsRowColumnTextAndImageFixtureToStableDesignIR() throws {
        let node = try loadFigmaNodeFixture(named: "basic-row-column-text-image")
        let resources = [
            FigmaResourceItem(
                name: "hero-ref",
                kind: .image,
                format: .png,
                remoteURL: "https://cdn.figma.test/hero.png",
                localPath: "assets/hero.png"
            )
        ]

        let design = FigmaNodeToDesignIRMapper().map(
            document: node,
            fileKey: "FILE123",
            nodeId: "1:1",
            resources: resources
        )

        try DesignIRValidator().validate(design)
        try expectStableGoldenJSON(design, named: "basic-row-column-text-image")
    }

    @Test func marksUnsupportedAndUncertainNodesForReview() throws {
        let node = FigmaDocumentNode(
            id: "1:1",
            name: "Unknown Shape",
            type: "BOOLEAN_OPERATION",
            bounds: DesignRect(x: 0, y: 0, width: 20, height: 20),
            fills: [
                FigmaPaint(type: "SOLID", color: FigmaColor(r: 1, g: 0, b: 0)),
                FigmaPaint(type: "SOLID", color: FigmaColor(r: 0, g: 0, b: 1))
            ]
        )

        let design = FigmaNodeToDesignIRMapper().map(document: node, fileKey: "FILE123", nodeId: "1:1")

        #expect(design.rootNode.type == .unknown)
        #expect(design.rootNode.needsReview)
        #expect(design.rootNode.confidence == 0.72)
        #expect(design.rootNode.warnings.contains("Unsupported Figma node type BOOLEAN_OPERATION"))
        #expect(design.rootNode.warnings.contains("Multiple visible fills require review"))
    }

    @Test func resolvesFigmaVariableColorsToSemanticTokenNames() throws {
        let text = FigmaDocumentNode(
            id: "2:1",
            name: "Title",
            type: "TEXT",
            bounds: DesignRect(x: 0, y: 0, width: 120, height: 24),
            fills: [
                FigmaPaint(type: "SOLID", color: FigmaColor(r: 0, g: 0, b: 0), opacity: 0.84)
            ],
            characters: "Welcome",
            boundVariables: FigmaBoundVariables(
                fills: [FigmaVariableAlias(id: "VariableID:18:12095")]
            )
        )
        let root = FigmaDocumentNode(
            id: "1:1",
            name: "Root",
            type: "FRAME",
            bounds: DesignRect(x: 0, y: 0, width: 360, height: 640),
            children: [text]
        )
        let colors = SemanticColorTokenLibrary(tokens: [
            SemanticColorToken(
                name: "color-elements-text-primary-02",
                value: "#000000",
                alpha: 0.84,
                variableID: "VariableID:18:12095",
                groupName: "文本色",
                scopes: ["TEXT_FILL"]
            )
        ])

        let design = FigmaNodeToDesignIRMapper().map(
            document: root,
            fileKey: "FILE123",
            nodeId: "1:1",
            localResources: LocalDesignResourceResolver(semanticColors: colors)
        )

        #expect(design.tokens.colors == [
            DesignColorToken(name: "color-elements-text-primary-02", value: "#D6000000")
        ])
        #expect(design.rootNode.children.first?.style?.text?.color == "color-elements-text-primary-02")
    }

    @Test func mapsNamedIconNodesToCachedLocalLibraryAssets() throws {
        let iconNode = FigmaDocumentNode(
            id: "2:1",
            name: "Button/Icon/icon_home_24",
            type: "INSTANCE",
            bounds: DesignRect(x: 0, y: 0, width: 24, height: 24),
            children: [
                FigmaDocumentNode(
                    id: "3:1",
                    name: "Vector",
                    type: "VECTOR",
                    bounds: DesignRect(x: 0, y: 0, width: 24, height: 24)
                )
            ]
        )
        let root = FigmaDocumentNode(
            id: "1:1",
            name: "Root",
            type: "FRAME",
            bounds: DesignRect(x: 0, y: 0, width: 360, height: 640),
            children: [iconNode]
        )
        let resources = [
            FigmaResourceItem(
                name: "icon_home_24",
                kind: .icon,
                format: .svg,
                localPath: "/tmp/figbridge-cache/assets/icon_home_24.svg"
            )
        ]

        let design = FigmaNodeToDesignIRMapper().map(
            document: root,
            fileKey: "FILE123",
            nodeId: "1:1",
            resources: resources
        )

        let mappedIcon = try #require(design.rootNode.children.first)
        #expect(mappedIcon.type == .icon)
        #expect(mappedIcon.asset == DesignAssetRef(name: "icon_home_24", localPath: "assets/icon_home_24.svg", kind: .icon, format: .svg))
        #expect(mappedIcon.children.isEmpty)
    }

    private func loadFigmaNodeFixture(named name: String) throws -> FigmaDocumentNode {
        let url = fixtureDirectory().appendingPathComponent("\(name).json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(FigmaDocumentNode.self, from: data)
    }

    private func expectStableGoldenJSON(_ design: DesignIR, named name: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let actual = String(data: try encoder.encode(design), encoding: .utf8)!
        let expectedURL = fixtureDirectory().appendingPathComponent("\(name).golden.json")
        let expected = try String(contentsOf: expectedURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(actual.trimmingCharacters(in: .whitespacesAndNewlines) == expected)
    }

    private func fixtureDirectory() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/FigmaNodes", isDirectory: true)
    }
}
