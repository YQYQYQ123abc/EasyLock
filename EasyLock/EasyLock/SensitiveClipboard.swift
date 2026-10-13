import AppKit

@MainActor final class SensitiveClipboard {
    private let board: NSPasteboard
    private let lifetime: Duration
    private var generation: Int?
    private var cleanup: Task<Void, Never>?
    init(board: NSPasteboard = .general, lifetime: Duration = .seconds(30)) {
        self.board = board; self.lifetime = lifetime
    }
    func copy(_ password: String) {
        cleanup?.cancel()
        board.clearContents()
        board.setString(password, forType: .string)
        board.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
        board.setData(Data(), forType: .init("org.nspasteboard.TransientType"))
        generation = board.changeCount
        let lifetime = lifetime
        cleanup = Task { [weak self] in
            do { try await Task.sleep(for: lifetime) } catch { return }
            self?.clearOwnedContents()
        }
    }
    func clearOwnedContents() {
        cleanup?.cancel(); cleanup = nil
        if let generation, board.changeCount == generation { board.clearContents() }
        generation = nil
    }
}
