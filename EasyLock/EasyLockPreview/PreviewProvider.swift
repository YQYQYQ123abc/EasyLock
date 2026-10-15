import Cocoa
import Quartz

/// Keep one view for the lifetime of the remote preview connection.
final class PreviewProvider: NSViewController, QLPreviewingController {
    override func loadView() {
        view = LockedCardView(frame: NSRect(x: 0, y: 0, width: 640, height: 440))
        preferredContentSize = NSSize(width: 640, height: 440)
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        // Replacing the root view after Quick Look connects can invalidate the remote view.
        let card = view as! LockedCardView
        card.state = LockedPreview.inspect(url)
        card.needsDisplay = true
        handler(nil)
    }
}

final class LockedCardView: NSView {
    var state: LockedPreview.State = .locked
    override func draw(_ dirtyRect: NSRect) {
        NSColor(red: 0.97, green: 0.97, blue: 0.99, alpha: 1).setFill()
        bounds.fill()
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        let scale = min(bounds.width / 640, bounds.height / 440)
        context.translateBy(x: bounds.midX - 320 * scale, y: bounds.midY - 220 * scale)
        context.scaleBy(x: scale, y: scale)
        let badge = NSBezierPath(roundedRect: NSRect(x: 276, y: 296, width: 88, height: 88), xRadius: 26, yRadius: 26)
        NSGradient(starting: NSColor(red: 0.36, green: 0.49, blue: 0.91, alpha: 1), ending: NSColor(red: 0.75, green: 0.45, blue: 0.77, alpha: 1))?.draw(in: badge, angle: -45)
        if state == .locked {
        NSColor.white.setStroke(); NSColor.white.setFill()
        let shackle = NSBezierPath(roundedRect: NSRect(x: 306, y: 334, width: 28, height: 29), xRadius: 14, yRadius: 14)
        shackle.lineWidth = 5; shackle.stroke()
        NSBezierPath(roundedRect: NSRect(x: 297, y: 313, width: 46, height: 32), xRadius: 7, yRadius: 7).fill()
        } else {
            text("!", y: 314, height: 56, size: 40, weight: .semibold, color: .white)
        }
        let messages = LockedPreview.messages(state)
        text(messages.title, y: 238, size: 28, weight: .semibold, color: .init(white: 0.15, alpha: 1))
        text(messages.subtitle, y: 188, size: 16, color: .init(white: 0.38, alpha: 1))
        text(messages.action, y: 116, height: 62, size: 15, color: .init(white: 0.38, alpha: 1))
        text("EASYLOCK · 本地隐私保护", y: 40, size: 12, weight: .medium, color: .init(red: 0.36, green: 0.44, blue: 0.70, alpha: 1))
        context.restoreGState()
    }
    private func text(_ value: String, y: CGFloat, height: CGFloat = 38, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor) {
        let style = NSMutableParagraphStyle(); style.alignment = .center
        style.lineBreakMode = .byWordWrapping
        (value as NSString).draw(in: NSRect(x: 40, y: y, width: 560, height: height), withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: style])
    }
}
