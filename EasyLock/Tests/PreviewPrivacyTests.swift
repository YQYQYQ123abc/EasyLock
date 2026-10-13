import Foundation
import Darwin

@main struct PreviewPrivacyTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("PRIVATE_FILENAME.easylock")
        let sentinel = "DO_NOT_PREVIEW_PRIVATE_CONTENT"
        for version in ["01", "02", "03", "04"] {
            try Data(("EASYLOCK\0" + version + sentinel).utf8).write(to: file)
            precondition(LockedPreview.inspect(file) == .locked)
            let html = String(decoding: LockedPreview.html(LockedPreview.inspect(file)), as: UTF8.self)
            precondition(!html.contains(sentinel) && !html.contains(file.lastPathComponent) && !html.contains(root.path))
            precondition(html.contains("default-src 'none'"))
        }
        try Data("EASYLOCK\099".utf8).write(to: file)
        precondition(LockedPreview.inspect(file) == .unsupported)
        for text in ["", "EASYLOCK\0", "EASYLOCK\00", sentinel] {
            try Data(text.utf8).write(to: file)
            precondition(LockedPreview.inspect(file) == .invalid)
        }
        let link = root.appendingPathComponent("link.easylock")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        precondition(LockedPreview.inspect(link) == .unavailable)
        let fifo = root.appendingPathComponent("fifo.easylock")
        precondition(mkfifo(fifo.path, 0o600) == 0)
        precondition(LockedPreview.inspect(fifo) == .invalid)
        precondition(LockedPreview.inspect(root) == .invalid)
        precondition(LockedPreview.inspect(root.appendingPathComponent("missing")) == .unavailable)
        precondition(LockedPreview.inspect(URL(string: "https://example.com/private")!) == .invalid)
        for state: LockedPreview.State in [.invalid, .unavailable, .unsupported] {
            precondition(!String(decoding: LockedPreview.html(state), as: UTF8.self).contains("class='lock'"))
        }
        // A sparse 2 GiB payload must not be loaded by the preview inspector.
        try Data("EASYLOCK\004".utf8).write(to: file)
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: 2 * 1024 * 1024 * 1024); try handle.close()
        precondition(LockedPreview.inspect(file) == .locked)
        print("PASS: preview privacy, versions, invalid/truncated inputs, symlink/FIFO rejection and bounded large-file inspection")
    }
}
