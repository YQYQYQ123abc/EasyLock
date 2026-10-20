import Foundation
import ImageIO

/// Decode only a bounded first-frame preview off the UI thread; never cache full-resolution pixels.
enum RasterPreview {
    static func supports(_ url: URL) -> Bool {
        ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "bmp", "webp"].contains(url.pathExtension.lowercased())
    }
    static func load(_ url: URL, maximumDimension: Int = 2560) -> CGImage? {
        guard !Task.isCancelled, maximumDimension > 0,
              let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(maximumDimension, 2560),
            kCGImageSourceShouldCacheImmediately: true
        ]
        let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        return Task.isCancelled ? nil : image
    }
}
