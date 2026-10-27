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

    private lazy var appIcon: NSImage? = {
        Bundle(for: LockedCardView.self).image(forResource: "PreviewIcon")
    }()

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let paper = dark ? NSColor(srgbRed: 0.035, green: 0.043, blue: 0.063, alpha: 1)
                         : NSColor(srgbRed: 0.957, green: 0.973, blue: 0.996, alpha: 1)
        let ink = dark ? NSColor(srgbRed: 0.949, green: 0.957, blue: 0.969, alpha: 1)
                       : NSColor(srgbRed: 0.063, green: 0.094, blue: 0.157, alpha: 1)
        let muted = dark ? NSColor(white: 0.63, alpha: 1) : NSColor(srgbRed: 0.40, green: 0.44, blue: 0.52, alpha: 1)
        let accent = state == .locked
            ? NSColor(srgbRed: 0.114, green: 0.333, blue: 0.941, alpha: 1)
            : NSColor(srgbRed: 0.851, green: 0.467, blue: 0.024, alpha: 1)

        NSGradient(starting: dark ? NSColor(srgbRed: 0.075, green: 0.098, blue: 0.145, alpha: 1) : NSColor.white,
                   ending: paper)?.draw(in: bounds, angle: -90)

        context.saveGState()
        let scale = min(bounds.width / 640, bounds.height / 440)
        context.translateBy(x: bounds.midX - 320 * scale, y: bounds.midY - 220 * scale)
        context.scaleBy(x: scale, y: scale)

        let messages = LockedPreview.messages(state)
        drawAppIcon(in: NSRect(x: 268, y: 280, width: 104, height: 104), dark: dark)
        text(messages.title, y: 232, height: 34, size: 25, weight: .semibold, color: ink)
        text(messages.subtitle, y: 196, height: 30, size: 14.5, color: muted)
        text(messages.action, y: 110, height: 68, size: 13, color: muted, lineSpacing: 4)
        text("EASYLOCK · LOCAL VAULT", y: 50, size: 9.5, weight: .semibold,
             color: accent.withAlphaComponent(dark ? 0.72 : 0.62), tracking: 2.2)

        context.restoreGState()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    private func drawAppIcon(in rect: NSRect, dark: Bool) {
        guard let icon = appIcon else { return }
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.45 : 0.16)
        shadow.shadowBlurRadius = 16
        shadow.shadowOffset = NSSize(width: 0, height: -5)
        shadow.set()
        icon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
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
