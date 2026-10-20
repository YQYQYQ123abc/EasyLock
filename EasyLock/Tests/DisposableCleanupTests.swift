import Foundation
import Darwin
@main struct DisposableCleanupTests {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("EasyLock-cleanup-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let source = root.appendingPathComponent("original")
        try Data("keep original".utf8).write(to: source)
        let transaction = root.appendingPathComponent(".easylock-transaction-test")
        let verification = transaction.appendingPathComponent("verification")
        let readonly = verification.appendingPathComponent("readonly")
        try fm.createDirectory(at: readonly, withIntermediateDirectories: true)
        try Data("temporary".utf8).write(to: readonly.appendingPathComponent("copy"))
        try fm.createSymbolicLink(at: readonly.appendingPathComponent("link"), withDestinationURL: source)
        precondition(chmod(readonly.path, 0o555) == 0)
        let before = try FileMetadata.capture(source)
        try TransactionRecovery.removeDisposableTree(verification)
        precondition(!fm.fileExists(atPath: verification.path))
        let after = try FileMetadata.capture(source)
        precondition(before.matches(after))
        let bytes = try Data(contentsOf: source)
        precondition(bytes == Data("keep original".utf8))
        do {
            try TransactionRecovery.removeDisposableTree(root)
            fatalError("non-transaction directory accepted")
        } catch {}
        try TransactionRecovery.removeDisposableTree(transaction)
        print("PASS: read-only disposable directories removed; symlink target and original metadata unchanged; non-transaction cleanup rejected")
    }
}
