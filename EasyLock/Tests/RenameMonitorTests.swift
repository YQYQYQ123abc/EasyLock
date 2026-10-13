import Foundation

@main
struct RenameMonitorTests {
    @MainActor
    static func main() async throws {
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent("easylock-monitor-\(UUID().uuidString)")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: folder) }
        let original = folder.appendingPathComponent("sample.easylock")
        let renamed = folder.appendingPathComponent("sample.jpg")
        try Data("fixture".utf8).write(to: original)
        var received: URL?
        let monitor = FileRenameMonitor(url: original) { url in received = url }
        precondition(monitor != nil)
        try fm.moveItem(at: original, to: renamed)
        for _ in 0..<50 {
            if received != nil { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        precondition(received?.standardizedFileURL == renamed.standardizedFileURL, "Rename event was not delivered")
        withExtendedLifetime(monitor) {}
        print("PASS: live rename monitor reports renamed file URL")
    }
}
