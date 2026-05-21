import Foundation

struct TestSandbox {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

func makeExecutable(at url: URL, body: String) throws {
    try body.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
}

func makeAgentDesignIRJSON(fileKey: String, nodeId: String, screenName: String = "Generated Screen") -> String {
    """
    {
      "version": "design-ir/v1",
      "screenName": "\(screenName)",
      "fileKey": "\(fileKey)",
      "nodeId": "\(nodeId)",
      "targetPlatform": "harmony-arkui",
      "viewport": {
        "width": 360,
        "height": 640
      },
      "tokens": {
        "colors": [],
        "textStyles": [],
        "spacing": {},
        "radii": {}
      },
      "rootNode": {
        "id": "\(nodeId)",
        "name": "\(screenName)",
        "type": "frame",
        "bounds": {
          "x": 0,
          "y": 0,
          "width": 360,
          "height": 640
        },
        "children": [],
        "needsReview": false,
        "warnings": []
      },
      "warnings": []
    }
    """
}

func makeAgentDesignIRYAML(fileKey: String, nodeId: String, screenName: String = "Generated Screen") -> String {
    """
    version: design-ir/v1
    screenName: \(screenName)
    fileKey: \(fileKey)
    nodeId: \(nodeId)
    targetPlatform: harmony-arkui
    viewport:
      width: 360
      height: 640
    tokens:
      colors: []
      textStyles: []
      spacing: {}
      radii: {}
    rootNode:
      id: \(nodeId)
      name: \(screenName)
      type: frame
      bounds:
        x: 0
        y: 0
        width: 360
        height: 640
      children: []
      needsReview: false
      warnings: []
    warnings: []
    """
}
