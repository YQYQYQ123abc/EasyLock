import AppKit

@main struct SensitiveClipboardTests {
    @MainActor static func main() async throws {
        // An isolated named pasteboard never touches the user's system clipboard.
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let clipboard = SensitiveClipboard(board: board, lifetime: .milliseconds(60))
        clipboard.copy("test-only-secret")
        precondition(board.string(forType: .string) == "test-only-secret")
        precondition(board.types?.contains(.init("org.nspasteboard.ConcealedType")) == true)
        precondition(board.types?.contains(.init("org.nspasteboard.TransientType")) == true)
        try await Task.sleep(for: .milliseconds(180))
        precondition(board.string(forType: .string) == nil)
        clipboard.copy("second-secret")
        board.clearContents(); board.setString("replacement", forType: .string)
        try await Task.sleep(for: .milliseconds(180))
        precondition(board.string(forType: .string) == "replacement")
        clipboard.copy("third-secret"); clipboard.clearOwnedContents()
        precondition(board.string(forType: .string) == nil)
        clipboard.copy("fourth-secret"); clipboard.copy("fifth-secret")
        precondition(board.string(forType: .string) == "fifth-secret")
        try await Task.sleep(for: .milliseconds(180))
        precondition(board.string(forType: .string) == nil)
        print("PASS: isolated password clipboard expiry, privacy flags, ownership protection, lock cleanup and repeated copies")
    }
}
