import AppKit
import Quartz

/// Owns Quick Look only while attached to a window. Closing an inactive QLPreviewView
/// can assert inside Quick Look; SwiftUI's dismantle callback may run after detachment.
final class ManagedQuickLookView: NSView {
    private var preview: QLPreviewView?
    private var itemURL: URL?
    private var finished = false

    func setItem(_ url: URL) {
        guard !finished, itemURL != url else { return }
        itemURL = url
        attachIfNeeded()
        preview?.previewItem = url as NSURL
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        attachIfNeeded()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        // Release while the preview still has its window, before AppKit deactivates it.
        if newWindow !== window { releasePreview() }
        super.viewWillMove(toWindow: newWindow)
    }

    func finish() {
        guard !finished else { return }
        finished = true
        releasePreview()
        itemURL = nil
    }

    private func attachIfNeeded() {
        guard !finished, window != nil, preview == nil, let itemURL,
              let child = QLPreviewView(frame: bounds, style: .normal) else { return }
        child.autostarts = false
        child.shouldCloseWithWindow = false
        child.autoresizingMask = [.width, .height]
        addSubview(child)
        preview = child
        child.previewItem = itemURL as NSURL
    }

    private func releasePreview() {
        guard let child = preview else { return }
        preview = nil
        child.close()
        child.removeFromSuperview()
    }
}
