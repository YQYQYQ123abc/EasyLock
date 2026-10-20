import SwiftUI
import AppKit

/// Keeps the preview outside the sheet stack, while retaining its serialized presentation slot.
struct PreviewWindow: NSViewRepresentable {
    let panel: PanelCoordinator.Panel?
    let title: String
    let content: () -> AnyView
    let closed: () -> Void
    func makeCoordinator() -> PreviewWindowController { PreviewWindowController() }
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.update(show: panel == .preview || panel == .localPreview,
                                   title: title, content: content, closed: closed)
    }
    static func dismantleNSView(_ view: NSView, coordinator: PreviewWindowController) { coordinator.close() }
}

@MainActor final class PreviewWindowController: NSObject, NSWindowDelegate {
    private(set) var window: NSPanel?
    private var monitor: Any?
    private var onClose: (() -> Void)?
    func update(show: Bool, title: String, content: () -> AnyView, closed: @escaping () -> Void) {
        guard show else { close(); return }
        onClose = closed
        if let window { window.title = Self.displayTitle(title); return }
        let screen = NSApp.keyWindow?.screen ?? NSScreen.main
        let available = screen?.visibleFrame.size ?? NSSize(width: 1200, height: 800)
        let size = NSSize(width: min(900, available.width - 80), height: min(660, available.height - 100))
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = true
        panel.isFloatingPanel = true
        panel.title = Self.displayTitle(title)
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.titlebarAppearsTransparent = true
        panel.contentMinSize = NSSize(width: 560, height: 400)
        let host = NSHostingView(rootView: content())
        host.sizingOptions = [] // Content changes must never reposition or resize the window.
        panel.contentView = host
        panel.setContentSize(size)
        panel.delegate = self
        window = panel
        panel.center()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, window.isKeyWindow else { return event }
            let editing = (window.firstResponder as? NSTextView)?.isEditable == true
            if event.keyCode == 53 || (event.keyCode == 49 && !editing && event.modifierFlags.intersection([.command, .control, .option]).isEmpty) {
                self.close(); return nil
            }
            return event
        }
        panel.makeKeyAndOrderFront(nil)
    }
    static func displayTitle(_ title: String) -> String {
        guard title.count > 54 else { return title }
        return String(title.prefix(30)) + "…" + String(title.suffix(18))
    }
    func close() { window?.close() }
    func windowWillClose(_ notification: Notification) {
        guard let panel = window else { return }
        window = nil
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        // Detach Quick Look before releasing the authorization and removing plaintext.
        panel.contentView = nil
        let callback = onClose; onClose = nil
        callback?()
    }
}
