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
