import Cocoa
import Quartz
import UniformTypeIdentifiers

final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let data = LockedPreview.html(LockedPreview.inspect(request.fileURL))
        return QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 620, height: 440)) { reply in
            reply.stringEncoding = .utf8
            return data
        }
    }
}
