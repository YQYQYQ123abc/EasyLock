import AppKit
import Quartz

@main struct QuickLookLifecycleTests {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("EasyLock-ql-lifecycle-\(UUID().uuidString).txt")
        try Data("Preview lifecycle fixture".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        for _ in 0..<20 {
            // SwiftUI may create and dismantle a representable without attaching it.
            let unattached = ManagedQuickLookView()
            unattached.setItem(file)
            unattached.finish(); unattached.finish()
            let view = ManagedQuickLookView(frame: window.contentView!.bounds)
            view.setItem(file)
            window.contentView!.addSubview(view)
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            view.removeFromSuperview()
            view.finish(); view.finish()
            let explicit = ManagedQuickLookView(frame: window.contentView!.bounds)
            window.contentView!.addSubview(explicit)
            explicit.setItem(file)
            explicit.finish()
            explicit.removeFromSuperview()
        }
        let closing = ManagedQuickLookView(frame: window.contentView!.bounds)
        window.contentView!.addSubview(closing)
        closing.setItem(file)
        window.close()
        closing.finish()
        print("PASS: Quick Look unattached disposal, attached disposal, detach-before-dismantle and repeated cleanup (20 cycles)")
    }
}
