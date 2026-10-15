import Foundation
import QuickLookThumbnailing

final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        let name = LockedPreview.inspect(request.fileURL) == .locked
            ? (min(request.maximumSize.width, request.maximumSize.height) >= 256 ? "LockedInfo" : "LockedThumbnail")
            : "InvalidThumbnail"
        // Supply a full-resolution immutable image. Quick Look owns resizing/Retina handling.
        // No filename, original image or decrypted bytes are ever used for this thumbnail.
        guard let image = Bundle(for: ThumbnailProvider.self).url(forResource: name, withExtension: "png") else {
            handler(nil, CocoaError(.fileNoSuchFile)); return
        }
        handler(QLThumbnailReply(imageFileURL: image), nil)
    }
}
