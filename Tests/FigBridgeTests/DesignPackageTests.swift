import Foundation
import Testing
@testable import FigBridgeCore

struct DesignPackageTests {
    @Test func createsAndLoadsDesignPackageWithAssetsAndChecksums() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let sourceDirectory = sandbox.root.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        let previewURL = sourceDirectory.appendingPathComponent("preview.png")
        let assetURL = sourceDirectory.appendingPathComponent("hero.png")
        try Data("PREVIEW".utf8).write(to: previewURL)
        try Data("IMAGE".utf8).write(to: assetURL)

        let store = DesignPackageStore(rootDirectory: sandbox.root.appendingPathComponent("packages", isDirectory: true))
        let design = makeDesignIR(assetPath: "assets/hero.png")
        let source = DesignPackageSource(
            figmaURL: "https://www.figma.com/design/FILE123/App?node-id=1-2",
            fileKey: "FILE123",
            nodeId: "1:2",
            exportedAt: Date(timeIntervalSince1970: 0),
            exporter: "test"
        )

        let persisted = try store.createPackage(
            DesignPackageWriteRequest(
                packageID: "login-screen",
                source: source,
                design: design,
                previewFile: previewURL,
                figmaNodeJSON: Data(#"{"id":"1:2"}"#.utf8),
                assetFiles: [assetURL]
            )
        )
        let loaded = try store.loadPackage(at: persisted.packageDirectory)

        #expect(loaded.manifest.schemaVersion == DesignPackageManifest.currentSchemaVersion)
        #expect(loaded.manifest.designFile == "design.json")
        #expect(loaded.manifest.previewFile == "preview.png")
        #expect(loaded.manifest.figmaNodeFile == "figma-node.json")
        #expect(loaded.manifest.checksums.keys.contains("design.json"))
        #expect(loaded.manifest.checksums.keys.contains("preview.png"))
        #expect(loaded.manifest.checksums.keys.contains("figma-node.json"))
        #expect(loaded.manifest.checksums.keys.contains("assets/hero.png"))
        #expect(loaded.design == design)
        #expect(FileManager.default.fileExists(atPath: loaded.packageDirectory.appendingPathComponent("assets/hero.png").path))
    }

    @Test func importPackageDirectoryCopiesIntoStoreRoot() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let sourceRoot = sandbox.root.appendingPathComponent("source-root", isDirectory: true)
        let destinationRoot = sandbox.root.appendingPathComponent("destination-root", isDirectory: true)
        let sourceStore = DesignPackageStore(rootDirectory: sourceRoot)
        let destinationStore = DesignPackageStore(rootDirectory: destinationRoot)

        let persisted = try sourceStore.createPackage(
            DesignPackageWriteRequest(
                packageID: "screen-a",
                source: DesignPackageSource(figmaURL: "https://www.figma.com/design/FILE123/App?node-id=1-2", fileKey: "FILE123", nodeId: "1:2"),
                design: makeDesignIR()
            )
        )

        let imported = try destinationStore.importPackageDirectory(from: persisted.packageDirectory)

        #expect(imported.packageDirectory.deletingLastPathComponent().path == destinationRoot.path)
        #expect(imported.manifest.packageID == "screen-a")
        #expect(imported.design.screenName == "Login")
    }

    @Test func importPackageZipCopiesIntoStoreRoot() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let sourceRoot = sandbox.root.appendingPathComponent("source-root", isDirectory: true)
        let destinationRoot = sandbox.root.appendingPathComponent("destination-root", isDirectory: true)
        let sourceStore = DesignPackageStore(rootDirectory: sourceRoot)
        let destinationStore = DesignPackageStore(rootDirectory: destinationRoot)
        let persisted = try sourceStore.createPackage(
            DesignPackageWriteRequest(
                packageID: "screen-zip",
                source: DesignPackageSource(figmaURL: "https://www.figma.com/design/FILE123/App?node-id=1-2", fileKey: "FILE123", nodeId: "1:2"),
                design: makeDesignIR()
            )
        )

        let zipURL = sandbox.root.appendingPathComponent("screen-zip.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-qr", zipURL.path, persisted.packageDirectory.lastPathComponent]
        process.currentDirectoryURL = persisted.packageDirectory.deletingLastPathComponent()
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)

        let imported = try destinationStore.importPackageArchive(from: zipURL)

        #expect(imported.packageDirectory.deletingLastPathComponent().path == destinationRoot.path)
        #expect(imported.manifest.packageID == "screen-zip")
        #expect(FileManager.default.fileExists(atPath: imported.packageDirectory.appendingPathComponent("manifest.json").path))
    }

    @Test func loadPackageRejectsChecksumMismatch() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let store = DesignPackageStore(rootDirectory: sandbox.root.appendingPathComponent("packages", isDirectory: true))
        let persisted = try store.createPackage(
            DesignPackageWriteRequest(
                packageID: "tamper",
                source: DesignPackageSource(figmaURL: "https://www.figma.com/design/FILE/App?node-id=1-2", fileKey: "FILE", nodeId: "1:2"),
                design: makeDesignIR()
            )
        )
        let designURL = persisted.packageDirectory.appendingPathComponent("design.json")
        try Data(#"{"tampered":true}"#.utf8).write(to: designURL)

        expectDesignPackageError(containing: "设计包文件校验失败: design.json") {
            _ = try store.loadPackage(at: persisted.packageDirectory)
        }
    }

    @Test func validatorRejectsMissingAssetReference() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let validator = DesignIRValidator()

        expectDesignPackageError(containing: "设计包缺少引用文件: assets/missing.png") {
            try validator.validate(makeDesignIR(assetPath: "assets/missing.png"), packageDirectory: sandbox.root)
        }
    }

    @Test func validatorRejectsInvalidViewportRootDuplicateIDsUnsafeAssetsAndConfidence() throws {
        let validator = DesignIRValidator()

        var invalidViewport = makeDesignIR()
        invalidViewport.viewport = DesignSize(width: 0, height: 640)
        expectDesignPackageError(containing: "viewport.width") {
            try validator.validate(invalidViewport)
        }

        var invalidRoot = makeDesignIR()
        invalidRoot.rootNode.type = .text
        expectDesignPackageError(containing: "rootNode.type") {
            try validator.validate(invalidRoot)
        }

        var duplicateID = makeDesignIR()
        duplicateID.rootNode.children[1].id = "2:1"
        expectDesignPackageError(containing: "duplicate node id: 2:1") {
            try validator.validate(duplicateID)
        }

        expectDesignPackageError(containing: "设计包路径不安全: ../hero.png") {
            try validator.validate(makeDesignIR(assetPath: "../hero.png"))
        }

        var badConfidence = makeDesignIR()
        badConfidence.rootNode.children[0].confidence = 1.2
        expectDesignPackageError(containing: "rootNode.children[0].confidence") {
            try validator.validate(badConfidence)
        }
    }

    @Test func loadPackageRejectsManifestPathAndChecksumContractViolations() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let store = DesignPackageStore(rootDirectory: sandbox.root.appendingPathComponent("packages", isDirectory: true))
        let persisted = try store.createPackage(
            DesignPackageWriteRequest(
                packageID: "manifest-contract",
                source: DesignPackageSource(figmaURL: "https://www.figma.com/design/FILE/App?node-id=1-2", fileKey: "FILE123", nodeId: "1:2"),
                design: makeDesignIR()
            )
        )
        let manifestURL = persisted.packageDirectory.appendingPathComponent(DesignPackageStore.manifestFilename)
        var manifest = persisted.manifest
        manifest.designFile = "design.yaml"
        try writeManifest(manifest, to: manifestURL)

        expectDesignPackageError(containing: "manifest.designFile") {
            _ = try store.loadPackage(at: persisted.packageDirectory)
        }

        manifest = persisted.manifest
        manifest.checksums.removeValue(forKey: "design.json")
        try writeManifest(manifest, to: manifestURL)

        expectDesignPackageError(containing: "设计包缺少文件校验值: design.json") {
            _ = try store.loadPackage(at: persisted.packageDirectory)
        }

        manifest = persisted.manifest
        manifest.checksums["ghost.json"] = String(repeating: "0", count: 64)
        try writeManifest(manifest, to: manifestURL)

        expectDesignPackageError(containing: "设计包包含未声明文件校验值: ghost.json") {
            _ = try store.loadPackage(at: persisted.packageDirectory)
        }
    }

    @Test func fixturePackageLoadsImportsValidatesAndGeneratesStably() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let fixtureURL = fixturePackageURL(named: "login-basic")
        let store = DesignPackageStore(rootDirectory: sandbox.root.appendingPathComponent("imported", isDirectory: true))

        let firstLoad = try store.loadPackage(at: fixtureURL)
        let secondLoad = try store.loadPackage(at: fixtureURL)
        let firstResult = try ArkUIGenerator().generate(design: firstLoad.design)
        let secondResult = try ArkUIGenerator().generate(design: secondLoad.design)

        #expect(firstLoad.manifest.designFile == "design.json")
        #expect(firstLoad.design == secondLoad.design)
        #expect(firstResult == secondResult)

        let imported = try store.importPackageDirectory(from: fixtureURL)
        let importedResult = try ArkUIGenerator().generate(design: imported.design)

        #expect(imported.design == firstLoad.design)
        #expect(importedResult == firstResult)
    }

    private func makeDesignIR(assetPath: String? = nil) -> DesignIR {
        let heroNode = DesignNode(
            id: "2:1",
            name: "Hero",
            type: .image,
            bounds: DesignRect(x: 0, y: 0, width: 320, height: 160),
            asset: assetPath.map {
                DesignAssetRef(name: "hero", localPath: $0, kind: .image, format: .png)
            },
            confidence: 1
        )
        let titleNode = DesignNode(
            id: "2:2",
            name: "Title",
            type: .text,
            bounds: DesignRect(x: 24, y: 184, width: 272, height: 32),
            style: DesignStyle(text: DesignTextStyle(fontSize: 24, fontWeight: "600", color: "#111111")),
            text: "Welcome",
            confidence: 0.9
        )
        let root = DesignNode(
            id: "1:2",
            name: "Login",
            type: .frame,
            bounds: DesignRect(x: 0, y: 0, width: 360, height: 640),
            layout: DesignLayout(mode: .vertical, spacing: 16, padding: DesignInsets(top: 24, right: 24, bottom: 24, left: 24)),
            children: [heroNode, titleNode],
            confidence: 0.95
        )
        return DesignIR(
            screenName: "Login",
            fileKey: "FILE123",
            nodeId: "1:2",
            viewport: DesignSize(width: 360, height: 640),
            tokens: DesignTokenSet(colors: [DesignColorToken(name: "text.primary", value: "#111111")]),
            rootNode: root
        )
    }

    private func writeManifest(_ manifest: DesignPackageManifest, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: url)
    }

    private func fixturePackageURL(named name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/DesignPackages/\(name)", isDirectory: true)
    }

    private func expectDesignPackageError(containing expectedText: String, _ operation: () throws -> Void) {
        do {
            try operation()
            Issue.record("Expected DesignPackageError containing \(expectedText)")
        } catch let error as DesignPackageError {
            #expect(error.localizedDescription.contains(expectedText))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
