import Foundation
import ImageIO
import UniformTypeIdentifiers
@main struct RasterPreviewTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("large.png")
        let context = CGContext(data: nil, width: 6000, height: 3000, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(destination))
        let image = RasterPreview.load(url)!
        precondition(image.width == 2560 && image.height == 1280)
        let small = RasterPreview.load(url, maximumDimension: 320)!
        precondition(small.width == 320 && small.height == 160)
        try Data("damaged".utf8).write(to: url)
        precondition(RasterPreview.load(url) == nil)
        precondition(RasterPreview.load(root.appendingPathComponent("missing.png")) == nil)
        print("PASS: large raster capped at 2560 pixels; aspect ratio preserved; damaged and missing files fail safely")
    }
}
