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

    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let paper = dark ? NSColor(srgbRed: 0.035, green: 0.035, blue: 0.039, alpha: 1)
                         : NSColor(srgbRed: 0.957, green: 0.957, blue: 0.941, alpha: 1)
        let ink = dark ? NSColor(srgbRed: 0.965, green: 0.965, blue: 0.949, alpha: 1)
                       : NSColor(srgbRed: 0.063, green: 0.063, blue: 0.071, alpha: 1)
        let muted = dark ? NSColor(white: 0.64, alpha: 1) : NSColor(white: 0.42, alpha: 1)
        let faint = dark ? NSColor(white: 0.44, alpha: 1) : NSColor(white: 0.56, alpha: 1)

        NSGradient(starting: dark ? NSColor(white: 0.10, alpha: 1) : NSColor.white,
                   ending: paper)?.draw(in: bounds, angle: -90)

        context.saveGState()
        let scale = min(bounds.width / 640, bounds.height / 440)
        context.translateBy(x: bounds.midX - 320 * scale, y: bounds.midY - 220 * scale)
        context.scaleBy(x: scale, y: scale)

        let messages = LockedPreview.messages(state)
        drawSeal(in: NSRect(x: 266, y: 286, width: 108, height: 120), ink: ink, paper: paper, dark: dark)
        text(messages.title, y: 238, height: 38, size: 26, weight: .semibold, color: ink)
        text(messages.subtitle, y: 197, height: 30, size: 15, color: muted)
        text(messages.action, y: 112, height: 68, size: 13.5, color: muted, lineSpacing: 4)
        text("EASYLOCK · LOCAL VAULT", y: 52, size: 9.5, weight: .semibold, color: faint, tracking: 2.2)

        context.restoreGState()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    private func drawSeal(in rect: NSRect, ink: NSColor, paper: NSColor, dark: Bool) {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.5 : 0.16)
        shadow.shadowBlurRadius = 16
        shadow.shadowOffset = NSSize(width: 0, height: -6)
        shadow.set()
        ink.setFill()
        shieldPath(in: rect).fill()
        NSGraphicsContext.restoreGraphicsState()

        let rim = rect.insetBy(dx: rect.width * 0.11, dy: rect.height * 0.10)
        let rimPath = shieldPath(in: rim)
        rimPath.lineWidth = 1.3
        paper.withAlphaComponent(0.45).setStroke()
        rimPath.stroke()

        if state == .locked {
            paper.setFill()
            paper.setStroke()
            let shackle = NSBezierPath(roundedRect: NSRect(x: rect.midX - 14, y: rect.midY + 2,
                                                           width: 28, height: 24),
                                       xRadius: 14, yRadius: 14)
            shackle.lineWidth = 5
            shackle.stroke()
            let body = NSBezierPath(roundedRect: NSRect(x: rect.midX - 22, y: rect.midY - 30,
                                                        width: 44, height: 36),
                                    xRadius: 7, yRadius: 7)
            body.fill()
            ink.setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.midX - 3.5, y: rect.midY - 15, width: 7, height: 7)).fill()
            NSRect(x: rect.midX - 2, y: rect.midY - 23, width: 4, height: 10).fill()
        } else {
            paper.setFill()
            NSBezierPath(roundedRect: NSRect(x: rect.midX - 2.6, y: rect.midY - 2,
                                             width: 5.2, height: 26),
                         xRadius: 2.6, yRadius: 2.6).fill()
            NSBezierPath(ovalIn: NSRect(x: rect.midX - 3.6, y: rect.midY - 18,
                                        width: 7.2, height: 7.2)).fill()
        }
    }

    private func shieldPath(in rect: NSRect) -> NSBezierPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            NSPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        let path = NSBezierPath()
        path.move(to: point(0.5, 0.988))
        path.line(to: point(0.148, 0.868))
        path.curve(to: point(0.064, 0.786),
                   controlPoint1: point(0.064, 0.857), controlPoint2: point(0.064, 0.857))
        path.curve(to: point(0.5, 0.012),
                   controlPoint1: point(0.069, 0.44), controlPoint2: point(0.232, 0.138))
        path.curve(to: point(0.936, 0.786),
                   controlPoint1: point(0.768, 0.138), controlPoint2: point(0.931, 0.44))
        path.curve(to: point(0.852, 0.868),
                   controlPoint1: point(0.936, 0.857), controlPoint2: point(0.936, 0.857))
        path.close()
        return path
    }

    private func text(_ value: String, y: CGFloat, height: CGFloat = 30, size: CGFloat,
                      weight: NSFont.Weight = .regular, color: NSColor,
                      tracking: CGFloat = 0, lineSpacing: CGFloat = 0) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byWordWrapping
        style.lineSpacing = lineSpacing
        var attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: style
        ]
        if tracking != 0 { attributes[.kern] = tracking }
        (value as NSString).draw(in: NSRect(x: 34, y: y, width: 572, height: height), withAttributes: attributes)
    }
}
