import Cocoa
@main struct PreviewControllerTests {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".easylock")
        try Data("EASYLOCK\u{0}04".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let controller = PreviewProvider()
        let original = controller.view
        let size = controller.preferredContentSize
        for _ in 0..<30 {
            var completed = false
            controller.preparePreviewOfFile(at: url) { error in
                precondition(error == nil); completed = true
            }
            precondition(completed)
            precondition(controller.view === original)
            precondition(controller.preferredContentSize == size)
            precondition((controller.view as? LockedCardView)?.state == .locked)
        }
        try Data("invalid".utf8).write(to: url)
        controller.preparePreviewOfFile(at: url) { precondition($0 == nil) }
        precondition((controller.view as? LockedCardView)?.state == .invalid)
        precondition(controller.view === original)
        print("PASS: 30 preview requests preserve root view and size; invalid input is not presented as locked")
    }
}
