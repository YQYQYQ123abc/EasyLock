import SwiftUI
import AppKit
@main struct PreviewWindowTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        let controller = PreviewWindowController()
        var callbacks = 0
        for _ in 0..<10 {
            controller.update(show: true, title: "Fixture", content: { AnyView(Text("Preview")) }, closed: { callbacks += 1 })
            let panel = controller.window!
            panel.setFrameOrigin(NSPoint(x: 120, y: 120))
            let frame = panel.frame
            controller.update(show: true, title: "Loaded", content: { AnyView(Text("Replacement")) }, closed: { callbacks += 1 })
            precondition(controller.window === panel && panel.frame == frame)
            controller.update(show: false, title: "", content: { AnyView(EmptyView()) }, closed: {})
            controller.close()
            precondition(controller.window == nil)
        }
        precondition(callbacks == 10)
        print("PASS: preview window reused without moving; programmatic close; repeated close; 10 reopen cycles")
    }
}
