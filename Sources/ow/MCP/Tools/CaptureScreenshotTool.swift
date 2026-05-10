import Foundation

struct CaptureScreenshotTool: MCPTool {
    static let name = "capture_screenshot"

    static let description = """
        Capture the oscilloscope's display as an image. Returns the image inline as PNG so the
        caller can view it directly. Optionally saves the BMP to a file path.

        Use this to: see what's currently on the scope, document a measurement, share what an
        engineer is looking at, or correlate a waveform capture with the scope's UI state
        (cursors, measurements, trigger settings).
        """

    static let inputSchema: JSONValue = .object([
        "type": .string("object"),
        "properties": .object(scopeOverrideProperties.merging([
            "save_path": .object([
                "type": .string("string"),
                "description": .string("Optional file path. .bmp saves raw, .png converts. Tilde expansion supported.")
            ])
        ]) { _, new in new })
    ])

    let scope: ScopeConfig?

    init(scope: ScopeConfig?) {
        self.scope = scope
    }

    func execute(args: [String: JSONValue]) async throws -> [JSONValue] {
        guard let config = resolveScope(args: args, default: scope) else { return [noHostBlock] }
        let client = ScopeClient(config)
        let response = try await client.capture(.startScreenshot)
        let bmpData = response.payload
        let pngData = try BMP.toPNG(bmpData)

        var blocks: [JSONValue] = []
        if let savePath = args["save_path"]?.stringValue {
            let url = URL(fileURLWithPath: (savePath as NSString).expandingTildeInPath)
            let dataToWrite: Data = url.pathExtension.lowercased() == "png" ? pngData : bmpData
            try dataToWrite.write(to: url)
            blocks.append(textBlock("saved \(dataToWrite.count) bytes to \(url.path)"))
        }
        blocks.append(.object([
            "type": .string("image"),
            "data": .string(pngData.base64EncodedString()),
            "mimeType": .string("image/png")
        ]))
        return blocks
    }
}
