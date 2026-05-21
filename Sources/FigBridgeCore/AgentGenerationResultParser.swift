import Foundation

public enum AgentGenerationResultParserError: LocalizedError, Equatable, Sendable {
    case emptyOutput
    case markdownOutput
    case invalidFormat(String)
    case validationFailed(String)
    case sourceMismatch(expectedFileKey: String, expectedNodeId: String, actualFileKey: String, actualNodeId: String)

    public var errorDescription: String? {
        switch self {
        case .emptyOutput:
            "Agent 输出为空，未找到 DesignIR"
        case .markdownOutput:
            "Agent 输出包含 Markdown 代码块，请只输出严格的 DesignIR JSON/YAML"
        case .invalidFormat(let message):
            "Agent 输出不是有效的 DesignIR JSON/YAML: \(message)"
        case .validationFailed(let message):
            "DesignIR 校验失败: \(message)"
        case .sourceMismatch(let expectedFileKey, let expectedNodeId, let actualFileKey, let actualNodeId):
            "DesignIR 来源不匹配: 期望 fileKey=\(expectedFileKey), nodeId=\(expectedNodeId)，实际 fileKey=\(actualFileKey), nodeId=\(actualNodeId)"
        }
    }
}

public struct AgentGenerationResultParser: Sendable {
    public struct ParseResult: Equatable, Sendable {
        public var design: DesignIR
        public var normalizedJSON: String

        public init(design: DesignIR, normalizedJSON: String) {
            self.design = design
            self.normalizedJSON = normalizedJSON
        }
    }

    private let validator: DesignIRValidator

    public init(validator: DesignIRValidator = DesignIRValidator()) {
        self.validator = validator
    }

    public func parse(_ output: String, expectedItem: FigmaLinkItem? = nil) throws -> ParseResult {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AgentGenerationResultParserError.emptyOutput
        }
        guard !trimmed.contains("```") else {
            throw AgentGenerationResultParserError.markdownOutput
        }

        let isLikelyJSON = trimmed.hasPrefix("{") || trimmed.hasPrefix("[")
        do {
            return try decodeAndValidate(
                Data(trimmed.utf8),
                formatLabel: "DesignIR JSON",
                expectedItem: expectedItem
            )
        } catch {
            if isLikelyJSON {
                throw parserError(from: error, formatLabel: "DesignIR JSON")
            }

            let jsonError = parserMessage(from: error, formatLabel: "DesignIR JSON")
            do {
                var yamlParser = try MinimalYAMLParser(text: trimmed)
                let yamlData = try yamlParser.jsonData()
                return try decodeAndValidate(
                    yamlData,
                    formatLabel: "DesignIR YAML",
                    expectedItem: expectedItem
                )
            } catch {
                let yamlError = parserMessage(from: error, formatLabel: "DesignIR YAML")
                throw AgentGenerationResultParserError.invalidFormat("\(jsonError); \(yamlError)")
            }
        }
    }

    private func decodeAndValidate(
        _ data: Data,
        formatLabel: String,
        expectedItem: FigmaLinkItem?
    ) throws -> ParseResult {
        let decoder = JSONDecoder()
        let design: DesignIR
        do {
            design = try decoder.decode(DesignIR.self, from: data)
        } catch {
            throw parserError(from: error, formatLabel: formatLabel)
        }

        do {
            try validator.validate(design)
        } catch {
            throw AgentGenerationResultParserError.validationFailed(error.localizedDescription)
        }

        if let expectedItem,
           design.fileKey != expectedItem.fileKey || design.nodeId != expectedItem.nodeId {
            throw AgentGenerationResultParserError.sourceMismatch(
                expectedFileKey: expectedItem.fileKey,
                expectedNodeId: expectedItem.nodeId,
                actualFileKey: design.fileKey,
                actualNodeId: design.nodeId
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let normalizedData = try encoder.encode(design)
        return ParseResult(
            design: design,
            normalizedJSON: String(decoding: normalizedData, as: UTF8.self)
        )
    }

    private func parserError(from error: Error, formatLabel: String) -> AgentGenerationResultParserError {
        if let parserError = error as? AgentGenerationResultParserError {
            return parserError
        }
        return .invalidFormat(parserMessage(from: error, formatLabel: formatLabel))
    }

    private func parserMessage(from error: Error, formatLabel: String) -> String {
        if let parserError = error as? AgentGenerationResultParserError {
            return parserError.localizedDescription
        }
        if let yamlError = error as? MinimalYAMLParser.Error {
            return "\(formatLabel) 解析失败: \(yamlError.localizedDescription)"
        }
        if let decodingError = error as? DecodingError {
            return decodingMessage(from: decodingError, formatLabel: formatLabel)
        }
        return "\(formatLabel) 解析失败: \(error.localizedDescription)"
    }

    private func decodingMessage(from error: DecodingError, formatLabel: String) -> String {
        switch error {
        case .keyNotFound(let key, let context):
            return "\(formatLabel) 缺少字段: \(codingPath(context.codingPath + [key]))"
        case .typeMismatch(let type, let context):
            return "\(formatLabel) 字段类型不匹配: \(codingPath(context.codingPath))，期望 \(type)"
        case .valueNotFound(let type, let context):
            return "\(formatLabel) 字段缺少值: \(codingPath(context.codingPath))，期望 \(type)"
        case .dataCorrupted(let context):
            let path = codingPath(context.codingPath)
            if path.isEmpty {
                return "\(formatLabel) 格式错误: \(context.debugDescription)"
            }
            return "\(formatLabel) 格式错误: \(path) (\(context.debugDescription))"
        @unknown default:
            return "\(formatLabel) 解码失败"
        }
    }

    private func codingPath(_ path: [CodingKey]) -> String {
        path.map(\.stringValue).joined(separator: ".")
    }
}

private struct MinimalYAMLParser {
    enum Error: LocalizedError {
        case invalidIndent(line: Int)
        case expectedMapping(line: Int)
        case expectedNestedBlock(line: Int)
        case unexpectedIndent(line: Int)
        case invalidTopLevel
        case invalidJSONObject

        var errorDescription: String? {
            switch self {
            case .invalidIndent(let line):
                "第 \(line) 行缩进无效"
            case .expectedMapping(let line):
                "第 \(line) 行不是 key: value 映射"
            case .expectedNestedBlock(let line):
                "第 \(line) 行缺少嵌套内容"
            case .unexpectedIndent(let line):
                "第 \(line) 行缩进层级不符合规范"
            case .invalidTopLevel:
                "顶层必须是 DesignIR 对象"
            case .invalidJSONObject:
                "YAML 内容无法转换为 JSON 对象"
            }
        }
    }

    private struct Line {
        var number: Int
        var indent: Int
        var content: String
    }

    private let lines: [Line]
    private var index = 0

    init(text: String) throws {
        var parsedLines: [Line] = []
        for (offset, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let lineNumber = offset + 1
            let trimmedRight = rawLine.trimmingCharacters(in: .whitespaces)
            let trimmed = trimmedRight.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
                continue
            }
            let indent = rawLine.prefix { $0 == " " }.count
            guard rawLine.dropFirst(indent).first != "\t" else {
                throw Error.invalidIndent(line: lineNumber)
            }
            parsedLines.append(Line(number: lineNumber, indent: indent, content: String(rawLine.dropFirst(indent)).trimmingCharacters(in: .whitespaces)))
        }
        lines = parsedLines
    }

    mutating func jsonData() throws -> Data {
        guard !lines.isEmpty else {
            throw Error.invalidTopLevel
        }
        let value = try parseBlock(indent: lines[0].indent)
        guard index == lines.count else {
            throw Error.unexpectedIndent(line: lines[index].number)
        }
        guard JSONSerialization.isValidJSONObject(value) else {
            throw Error.invalidJSONObject
        }
        return try JSONSerialization.data(withJSONObject: value)
    }

    private mutating func parseBlock(indent: Int) throws -> Any {
        guard index < lines.count else {
            throw Error.invalidTopLevel
        }
        if lines[index].content.hasPrefix("- ") {
            return try parseArray(indent: indent)
        }
        return try parseMap(indent: indent)
    }

    private mutating func parseMap(indent: Int) throws -> [String: Any] {
        var result: [String: Any] = [:]
        while index < lines.count {
            let line = lines[index]
            if line.indent < indent {
                break
            }
            guard line.indent == indent else {
                throw Error.unexpectedIndent(line: line.number)
            }
            if line.content.hasPrefix("- ") {
                break
            }
            let pair = try splitMapping(line.content, lineNumber: line.number)
            index += 1
            result[pair.key] = try value(from: pair.value, parentLine: line.number, parentIndent: indent)
        }
        return result
    }

    private mutating func parseArray(indent: Int) throws -> [Any] {
        var result: [Any] = []
        while index < lines.count {
            let line = lines[index]
            if line.indent < indent {
                break
            }
            guard line.indent == indent, line.content.hasPrefix("- ") else {
                break
            }
            let itemText = String(line.content.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            index += 1
            if itemText.isEmpty {
                result.append(try nestedValue(parentLine: line.number, parentIndent: indent))
                continue
            }

            if let pair = try? splitMapping(itemText, lineNumber: line.number) {
                var item: [String: Any] = [:]
                item[pair.key] = try value(from: pair.value, parentLine: line.number, parentIndent: indent)
                if index < lines.count, lines[index].indent > indent, !lines[index].content.hasPrefix("- ") {
                    let nestedMap = try parseMap(indent: lines[index].indent)
                    item.merge(nestedMap) { _, new in new }
                }
                result.append(item)
            } else {
                result.append(try parseScalar(itemText))
            }
        }
        return result
    }

    private mutating func value(from text: String, parentLine: Int, parentIndent: Int) throws -> Any {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return try nestedValue(parentLine: parentLine, parentIndent: parentIndent)
        }
        return try parseScalar(trimmed)
    }

    private mutating func nestedValue(parentLine: Int, parentIndent: Int) throws -> Any {
        guard index < lines.count, lines[index].indent > parentIndent else {
            throw Error.expectedNestedBlock(line: parentLine)
        }
        return try parseBlock(indent: lines[index].indent)
    }

    private func splitMapping(_ text: String, lineNumber: Int) throws -> (key: String, value: String) {
        var quote: Character?
        for (offset, character) in text.enumerated() {
            if character == "\"" || character == "'" {
                if quote == character {
                    quote = nil
                } else if quote == nil {
                    quote = character
                }
            }
            if character == ":", quote == nil {
                let key = String(text.prefix(offset)).trimmingCharacters(in: .whitespaces)
                guard !key.isEmpty else {
                    throw Error.expectedMapping(line: lineNumber)
                }
                let valueStart = text.index(text.startIndex, offsetBy: offset + 1)
                let value = String(text[valueStart...]).trimmingCharacters(in: .whitespaces)
                return (key, value)
            }
        }
        throw Error.expectedMapping(line: lineNumber)
    }

    private func parseScalar(_ text: String) throws -> Any {
        switch text {
        case "null", "Null", "NULL", "~":
            return NSNull()
        case "true", "True", "TRUE":
            return true
        case "false", "False", "FALSE":
            return false
        case "[]":
            return [Any]()
        case "{}":
            return [String: Any]()
        default:
            break
        }

        if text.hasPrefix("\""), text.hasSuffix("\""),
           let data = text.data(using: .utf8),
           let value = try JSONSerialization.jsonObject(with: data) as? String {
            return value
        }
        if text.hasPrefix("'"), text.hasSuffix("'") {
            return String(text.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        }
        if (text.hasPrefix("{") && text.hasSuffix("}")) || (text.hasPrefix("[") && text.hasSuffix("]")),
           let data = text.data(using: .utf8),
           let value = try? JSONSerialization.jsonObject(with: data) {
            return value
        }
        if let integer = Int(text), String(integer) == text {
            return integer
        }
        if let double = Double(text), double.isFinite {
            return double
        }
        return text
    }
}
