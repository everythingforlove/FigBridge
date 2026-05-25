import Foundation

enum DesignIRAssetPathNormalizer {
    static func packageRelativeAssetPath(fromCachedPath path: String) -> String {
        if let normalized = packageRelativeAssetPath(fromPossiblyUnsafePath: path) {
            return normalized
        }

        let filename = URL(fileURLWithPath: path).lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !filename.isEmpty else {
            return "\(DesignPackageStore.assetsDirectoryName)/asset"
        }
        return "\(DesignPackageStore.assetsDirectoryName)/\(filename)"
    }

    static func packageRelativeAssetPath(fromPossiblyUnsafePath path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let prefix = "\(DesignPackageStore.assetsDirectoryName)/"
        if trimmed.hasPrefix(prefix) {
            return trimmed
        }

        guard trimmed.hasPrefix("/") || trimmed.contains("/\(DesignPackageStore.assetsDirectoryName)/") else {
            return nil
        }

        let filename = URL(fileURLWithPath: trimmed).lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !filename.isEmpty else {
            return nil
        }
        return "\(prefix)\(filename)"
    }
}
