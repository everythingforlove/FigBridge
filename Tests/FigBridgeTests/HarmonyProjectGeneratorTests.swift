import Foundation
import Testing
@testable import FigBridgeCore

struct HarmonyProjectGeneratorTests {
    @Test func generatesHarmonyProjectFilesFromPersistedDesignPackage() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let sourceDirectory = sandbox.root.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        let assetURL = sourceDirectory.appendingPathComponent("hero.png")
        try Data("IMAGE".utf8).write(to: assetURL)

        let packageStore = DesignPackageStore(rootDirectory: sandbox.root.appendingPathComponent("packages", isDirectory: true))
        let package = try packageStore.createPackage(
            DesignPackageWriteRequest(
                packageID: "login-page",
                source: DesignPackageSource(
                    figmaURL: "https://www.figma.com/design/FILE/App?node-id=1-2",
                    fileKey: "FILE",
                    nodeId: "1:2"
                ),
                design: makeDesignIR(),
                assetFiles: [assetURL]
            )
        )

        let targetProject = sandbox.root.appendingPathComponent("HarmonyProject", isDirectory: true)
        let result = try HarmonyProjectGenerator().generate(package: package, targetProjectDirectory: targetProject)

        let pageURL = targetProject.appendingPathComponent("entry/src/main/ets/pages/LoginPage.ets")
        let resourceURL = targetProject.appendingPathComponent("entry/src/main/resources/base/media/hero.png")
        let pageContent = try String(contentsOf: pageURL, encoding: .utf8)

        #expect(result.generatedFiles == [pageURL])
        #expect(result.copiedResources == [resourceURL])
        #expect(FileManager.default.fileExists(atPath: pageURL.path))
        #expect(FileManager.default.fileExists(atPath: resourceURL.path))
        #expect(FileManager.default.fileExists(atPath: result.reportFile.path))
        #expect(pageContent.contains("struct LoginPage"))
        #expect(pageContent.contains("Image($r('app.media.hero'))"))
        #expect(try Data(contentsOf: resourceURL) == Data("IMAGE".utf8))
        #expect(result.report.markdown.contains("页面文件存在"))
        #expect(result.report.checks.allSatisfy { $0.status != .failed })
    }

    @Test func refusesToOverwriteExistingFilesWhenConfigured() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let packageStore = DesignPackageStore(rootDirectory: sandbox.root.appendingPathComponent("packages", isDirectory: true))
        let package = try packageStore.createPackage(
            DesignPackageWriteRequest(
                packageID: "existing-page",
                source: DesignPackageSource(
                    figmaURL: "https://www.figma.com/design/FILE/App?node-id=1-2",
                    fileKey: "FILE",
                    nodeId: "1:2"
                ),
                design: makeDesignIR(includeAsset: false)
            )
        )

        let targetProject = sandbox.root.appendingPathComponent("HarmonyProject", isDirectory: true)
        let existingPageURL = targetProject.appendingPathComponent("entry/src/main/ets/pages/LoginPage.ets")
        try FileManager.default.createDirectory(at: existingPageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "existing".write(to: existingPageURL, atomically: true, encoding: .utf8)

        #expect(throws: HarmonyProjectGenerationError.self) {
            _ = try HarmonyProjectGenerator().generate(
                package: package,
                targetProjectDirectory: targetProject,
                options: HarmonyProjectGenerationOptions(overwriteExistingFiles: false)
            )
        }
    }

    @Test func reportsMissingPackageResource() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let sourceDirectory = sandbox.root.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        let assetURL = sourceDirectory.appendingPathComponent("hero.png")
        try Data("IMAGE".utf8).write(to: assetURL)

        let packageStore = DesignPackageStore(rootDirectory: sandbox.root.appendingPathComponent("packages", isDirectory: true))
        let package = try packageStore.createPackage(
            DesignPackageWriteRequest(
                packageID: "missing-resource",
                source: DesignPackageSource(
                    figmaURL: "https://www.figma.com/design/FILE/App?node-id=1-2",
                    fileKey: "FILE",
                    nodeId: "1:2"
                ),
                design: makeDesignIR(),
                assetFiles: [assetURL]
            )
        )
        try FileManager.default.removeItem(at: package.packageDirectory.appendingPathComponent("assets/hero.png"))
        let targetProject = sandbox.root.appendingPathComponent("HarmonyProject", isDirectory: true)

        #expect(throws: HarmonyProjectGenerationError.self) {
            _ = try HarmonyProjectGenerator().generate(package: package, targetProjectDirectory: targetProject)
        }
    }

    private func makeDesignIR(includeAsset: Bool = true) -> DesignIR {
        let image = DesignNode(
            id: "2:1",
            name: "Hero",
            type: .image,
            bounds: DesignRect(x: 0, y: 0, width: 320, height: 160),
            asset: includeAsset ? DesignAssetRef(name: "hero", localPath: "assets/hero.png", kind: .image, format: .png) : nil
        )
        let root = DesignNode(
            id: "1:2",
            name: "Login",
            type: .frame,
            bounds: DesignRect(x: 0, y: 0, width: 360, height: 640),
            layout: DesignLayout(mode: .vertical),
            children: [image]
        )
        return DesignIR(
            screenName: "Login Page",
            fileKey: "FILE",
            nodeId: "1:2",
            viewport: DesignSize(width: 360, height: 640),
            rootNode: root
        )
    }
}
