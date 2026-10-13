import CoreGraphics
import QuickLookThumbnailing

final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        let valid = LockedPreview.inspect(request.fileURL) == .locked
        let side = max(1, min(request.maximumSize.width, request.maximumSize.height))
        handler(QLThumbnailReply(contextSize: CGSize(width: side, height: side), drawing: { context in
            context.scaleBy(x: side / 128, y: side / 128)
            let paper = CGPath(roundedRect: CGRect(x: 17, y: 5, width: 94, height: 118), cornerWidth: 16, cornerHeight: 16, transform: nil)
            context.setFillColor(CGColor(red: 0.93, green: 0.94, blue: 0.99, alpha: 1))
            context.addPath(paper); context.fillPath()
            context.setStrokeColor(CGColor(red: 0.34, green: 0.47, blue: 0.84, alpha: 1))
            context.setFillColor(CGColor(red: 0.34, green: 0.47, blue: 0.84, alpha: 1))
            if valid {
                context.setLineWidth(7); context.setLineCap(.round)
                context.addPath(CGPath(roundedRect: CGRect(x: 47, y: 57, width: 34, height: 35), cornerWidth: 17, cornerHeight: 17, transform: nil)); context.strokePath()
                context.addPath(CGPath(roundedRect: CGRect(x: 36, y: 32, width: 56, height: 44), cornerWidth: 9, cornerHeight: 9, transform: nil)); context.fillPath()
                context.setFillColor(CGColor(red: 0.93, green: 0.94, blue: 0.99, alpha: 1))
                context.addPath(CGPath(roundedRect: CGRect(x: 60, y: 45, width: 8, height: 17), cornerWidth: 4, cornerHeight: 4, transform: nil)); context.fillPath()
            } else {
                // An unrecognized file must not receive a misleading "secure" lock thumbnail.
                context.setLineWidth(8); context.setLineCap(.round)
                context.move(to: CGPoint(x: 64, y: 51)); context.addLine(to: CGPoint(x: 64, y: 86)); context.strokePath()
                context.fillEllipse(in: CGRect(x: 60, y: 32, width: 8, height: 8))
            }
            return true
        }), nil)
    }
}
