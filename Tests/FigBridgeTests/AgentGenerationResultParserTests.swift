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

    @Test func rejectsMissingFieldsMarkdownAndMalformedOutput() {
        let parser = AgentGenerationResultParser()
        let item = FigmaLinkItem(rawInputLine: "one", title: "one", url: "https://www.figma.com/design/FILE1/A?node-id=1-2", fileKey: "FILE1", nodeId: "1:2")

        expectParserError(containing: "缺少字段") {
            _ = try parser.parse(#"{"version":"design-ir/v1"}"#, expectedItem: item)
        }

        expectParserError(containing: "Markdown") {
            _ = try parser.parse(
                """
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
