import Foundation
import Testing
@testable import FigBridgeCore

struct ArkUIGeneratorTests {
    @Test func generatesArkUIPageFromVerticalDesignIR() throws {
        let design = makeDesignIR()
        let result = try ArkUIGenerator().generate(design: design)
        let file = try #require(result.files.first)

        #expect(file.relativePath == "entry/src/main/ets/pages/LoginPage.ets")
        #expect(file.content.contains("@Entry"))
        #expect(file.content.contains("struct LoginPage"))
        #expect(file.content.contains("Column({ space: 12 })"))
        #expect(file.content.contains("Image($r('app.media.hero_image'))"))
        #expect(file.content.contains("Text('Welcome')"))
        #expect(file.content.contains(".fontSize(24)"))
        #expect(file.content.contains(".fontWeight(FontWeight.Medium)"))
        #expect(file.content.contains(".padding({ top: 24, right: 16, bottom: 24, left: 16 })"))
        #expect(result.resources == [
            ArkUIResourceMapping(
                sourcePath: "assets/hero.png",
                targetPath: "entry/src/main/resources/base/media/hero_image.png",
                resourceName: "hero_image"
            )
        ])
        #expect(result.warnings.isEmpty)
    }

    @Test func generatesWarningsForFallbackLayoutsAndMissingAssets() throws {
        let child = DesignNode(
            id: "2:1",
            name: "Missing Image",
            type: .image,
            bounds: DesignRect(x: 0, y: 0, width: 100, height: 100),
            needsReview: true
        )
        let root = DesignNode(
            id: "1:1",
            name: "Loose Group",
            type: .frame,
            bounds: DesignRect(x: 0, y: 0, width: 360, height: 640),
            children: [child]
        )
        let design = DesignIR(
            screenName: "Loose Group",
            fileKey: "FILE",
            nodeId: "1:1",
            viewport: DesignSize(width: 360, height: 640),
            rootNode: root
        )

        let result = try ArkUIGenerator().generate(design: design)
        let content = try #require(result.files.first?.content)

        #expect(content.contains("Stack()"))
        #expect(result.warnings.contains("Loose Group 缺少布局方向，已生成 Stack"))
        #expect(result.warnings.contains("Missing Image 需要人工复核"))
        #expect(result.warnings.contains("Missing Image 缺少图片资源，已降级为空 Stack"))
    }

    @Test func sanitizesPageAndResourceNames() throws {
        let design = makeDesignIR(screenName: "123 Login / 首页", assetName: "1 Hero@Image")
        let result = try ArkUIGenerator().generate(design: design)
        let file = try #require(result.files.first)

        #expect(file.relativePath == "entry/src/main/ets/pages/Generated123Login首页.ets")
        #expect(file.content.contains("struct Generated123Login首页"))
        #expect(result.resources.first?.resourceName == "asset_1_hero_image")
    }

    @Test func referencesExistingSemanticColorResourcesByTokenName() throws {
        var design = makeDesignIR()
        design.tokens = DesignTokenSet(colors: [
            DesignColorToken(name: "color-elements-text-primary-02", value: "#D6000000")
        ])
        design.rootNode.children[1].style = DesignStyle(
            text: DesignTextStyle(
                fontSize: 24,
                fontWeight: "600",
                color: "color-elements-text-primary-02"
            )
        )

        let result = try ArkUIGenerator().generate(design: design)
        let file = try #require(result.files.first)

        #expect(file.content.contains(".fontColor($r('app.color.color-elements-text-primary-02'))"))
        #expect(result.files.count == 1)
    }

    private func makeDesignIR(screenName: String = "Login Page", assetName: String = "Hero Image") -> DesignIR {
        let image = DesignNode(
            id: "2:1",
            name: "Hero",
            type: .image,
            bounds: DesignRect(x: 16, y: 24, width: 328, height: 160),
            asset: DesignAssetRef(name: assetName, localPath: "assets/hero.png", kind: .image, format: .png)
        )
        let text = DesignNode(
            id: "2:2",
            name: "Title",
            type: .text,
            bounds: DesignRect(x: 16, y: 196, width: 328, height: 32),
            style: DesignStyle(text: DesignTextStyle(fontSize: 24, fontWeight: "600", color: "#111111")),
            text: "Welcome"
        )
        let root = DesignNode(
            id: "1:1",
            name: "Root",
            type: .frame,
            bounds: DesignRect(x: 0, y: 0, width: 360, height: 640),
            layout: DesignLayout(mode: .vertical, spacing: 12, padding: DesignInsets(top: 24, right: 16, bottom: 24, left: 16)),
            style: DesignStyle(fill: "#FFFFFF"),
            children: [image, text]
        )
        return DesignIR(
            screenName: screenName,
            fileKey: "FILE",
            nodeId: "1:1",
            viewport: DesignSize(width: 360, height: 640),
            rootNode: root
        )
    }
}
