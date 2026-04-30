import Foundation

/// 通用「重命名输入框」状态。条目重命名（ID 为 `UUID`）和批次重命名（ID 为 `String`）共用。
///
/// 用法：
/// - `begin(_:originalTitle:)`：进入编辑态，把当前标题塞进 `title`
/// - `cancel()`：取消编辑态
/// - `shouldCommitOnBlur`：失焦时是否应当落库（trim 后内容有变化才落库）
/// - `trimmedTitle`：调用方落库时拿到的实际新标题
public struct RenameState<ID: Hashable & Sendable>: Sendable {
    public var identifier: ID?
    public var title: String = ""
    public var originalTitle: String = ""

    public init() {}

    public var isActive: Bool {
        identifier != nil
    }

    public var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var shouldCommitOnBlur: Bool {
        trimmedTitle != originalTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public mutating func begin(_ id: ID, originalTitle: String) {
        self.identifier = id
        self.title = originalTitle
        self.originalTitle = originalTitle
    }

    public mutating func cancel() {
        identifier = nil
        title = ""
        originalTitle = ""
    }
}
