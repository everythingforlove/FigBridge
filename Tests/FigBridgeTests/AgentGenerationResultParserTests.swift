import Foundation
import Testing
@testable import FigBridgeCore

struct AgentGenerationResultParserTests {
    @Test func parsesAndNormalizesDesignIRJSON() throws {
        let item = FigmaLinkItem(rawInputLine: "one", title: "one", url: "https://www.figma.com/design/FILE1/A?node-id=1-2", fileKey: "FILE1", nodeId: "1:2")
        let result = try AgentGenerationResultParser().parse(
            makeAgentDesignIRJSON(fileKey: "FILE1", nodeId: "1:2", screenName: "Login"),
            expectedItem: item
        )

        #expect(result.design.screenName == "Login")
        #expect(result.normalizedJSON.contains(#""version""#))
    }

    @Test func parsesDesignIRYAML() throws {
        let item = FigmaLinkItem(rawInputLine: "one", title: "one", url: "https://www.figma.com/design/FILE1/A?node-id=1-2", fileKey: "FILE1", nodeId: "1:2")
        let result = try AgentGenerationResultParser().parse(
            makeAgentDesignIRYAML(fileKey: "FILE1", nodeId: "1:2", screenName: "Login"),
            expectedItem: item
        )

        #expect(result.design.fileKey == "FILE1")
        #expect(result.design.nodeId == "1:2")
    }

    @Test func normalizesCommonAgentTokenMapShapes() throws {
        let item = FigmaLinkItem(rawInputLine: "one", title: "one", url: "https://www.figma.com/design/FILE1/A?node-id=1-2", fileKey: "FILE1", nodeId: "1:2")
        let output = """
        {
          "version": "design-ir/v1",
          "screenName": "Login",
          "fileKey": "FILE1",
          "nodeId": "1:2",
          "targetPlatform": "harmony-arkui",
          "viewport": { "width": 360, "height": 640 },
          "tokens": {
            "colors": {
              "brandPrimary": "#E93030",
              "textPrimary": { "value": "#111111" }
            },
            "textStyles": {
              "body": { "fontSize": 14, "fontWeight": "400" }
            },
            "spacing": [
              { "name": "pagePadding", "value": 16 }
            ],
            "radii": [
              { "name": "card", "radius": 8 }
            ]
          },
          "rootNode": {
            "id": "1:2",
            "name": "Login",
            "type": "frame",
            "bounds": { "x": 0, "y": 0, "width": 360, "height": 640 },
            "children": [],
            "needsReview": false,
            "warnings": []
          },
          "warnings": []
        }
        """

        let result = try AgentGenerationResultParser().parse(output, expectedItem: item)

        #expect(result.design.tokens.colors.map(\.name) == ["brandPrimary", "textPrimary"])
        #expect(result.design.tokens.colors.map(\.value) == ["#E93030", "#111111"])
        #expect(result.design.tokens.textStyles.first?.name == "body")
        #expect(result.design.tokens.textStyles.first?.style.fontSize == 14)
        #expect(result.design.tokens.spacing["pagePadding"] == 16)
        #expect(result.design.tokens.radii["card"] == 8)
    }

    @Test func normalizesAbsoluteCachedAssetPathsToPackageRelativePaths() throws {
        let item = FigmaLinkItem(rawInputLine: "one", title: "one", url: "https://www.figma.com/design/FILE1/A?node-id=1-2", fileKey: "FILE1", nodeId: "1:2")
        let output = """
        {
          "version": "design-ir/v1",
          "screenName": "Login",
          "fileKey": "FILE1",
          "nodeId": "1:2",
          "targetPlatform": "harmony-arkui",
          "viewport": { "width": 360, "height": 640 },
          "tokens": {
            "colors": [],
            "textStyles": [],
            "spacing": {},
            "radii": {}
          },
          "rootNode": {
            "id": "1:2",
            "name": "Login",
            "type": "frame",
            "bounds": { "x": 0, "y": 0, "width": 360, "height": 640 },
            "children": [
              {
                "id": "2:1",
                "name": "icon_bot_24",
                "type": "icon",
                "asset": {
                  "name": "icon_bot_24",
                  "localPath": "/Users/xiejialin/Library/Application Support/FigBridge/Batches/batch/items/item/assets/icon_bot_24.svg",
                  "kind": "icon",
                  "format": "svg"
                },
                "children": [],
                "needsReview": false,
                "warnings": []
              }
            ],
            "needsReview": false,
            "warnings": []
          },
          "warnings": []
        }
        """

        let result = try AgentGenerationResultParser().parse(output, expectedItem: item)

        #expect(result.design.rootNode.children.first?.asset?.localPath == "assets/icon_bot_24.svg")
    }

    @Test func parsesFencedDesignIRAndRejectsMissingFieldsAndMalformedOutput() throws {
        let parser = AgentGenerationResultParser()
        let item = FigmaLinkItem(rawInputLine: "one", title: "one", url: "https://www.figma.com/design/FILE1/A?node-id=1-2", fileKey: "FILE1", nodeId: "1:2")

        let fencedResult = try parser.parse(
            """
            ```json
            \(makeAgentDesignIRJSON(fileKey: "FILE1", nodeId: "1:2", screenName: "Fenced"))
            ```
            """,
            expectedItem: item
        )
        #expect(fencedResult.design.screenName == "Fenced")

        expectParserError(containing: "缺少字段") {
            _ = try parser.parse(#"{"version":"design-ir/v1"}"#, expectedItem: item)
        }

        expectParserError(containing: "Markdown") {
            _ = try parser.parse(
                """
                这是结果：
                ```json
                \(makeAgentDesignIRJSON(fileKey: "FILE1", nodeId: "1:2"))
                ```
                """,
                expectedItem: item
            )
        }

        expectParserError(containing: "不是有效") {
            _ = try parser.parse("this is not design ir", expectedItem: item)
        }
    }

    @Test func rejectsMismatchedSource() {
        let item = FigmaLinkItem(rawInputLine: "one", title: "one", url: "https://www.figma.com/design/FILE1/A?node-id=1-2", fileKey: "FILE1", nodeId: "1:2")

        expectParserError(containing: "来源不匹配") {
            _ = try AgentGenerationResultParser().parse(
                makeAgentDesignIRJSON(fileKey: "OTHER", nodeId: "9:9"),
                expectedItem: item
            )
        }
    }

    private func expectParserError(containing expectedText: String, _ operation: () throws -> Void) {
        do {
            try operation()
            Issue.record("Expected AgentGenerationResultParserError containing \(expectedText)")
        } catch let error as AgentGenerationResultParserError {
            #expect(error.localizedDescription.contains(expectedText))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
