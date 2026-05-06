import Foundation
import AppKit
import UniformTypeIdentifiers

/// BMP↔PNG conversions for screenshot output.
enum BMP {
    /// Convert a Windows BMP to PNG. Used for MCP screenshot return so an LLM can
    /// view the image inline.
    static func toPNG(_ bmpData: Data) throws -> Data {
        guard let image = NSImage(data: bmpData),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            throw BMPError.conversionFailed
        }
        return png
    }
}

enum BMPError: Error, CustomStringConvertible {
    case conversionFailed

    var description: String {
        switch self {
        case .conversionFailed:
            return "could not decode BMP into a PNG representation"
        }
    }
}
