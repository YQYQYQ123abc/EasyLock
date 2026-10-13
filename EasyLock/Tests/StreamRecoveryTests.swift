import Foundation
import CryptoKit
import Darwin

@main
struct StreamRecoveryTests {
    static let fm = FileManager.default
    static let secret = "streaming regression password"
    final class ControlBox: @unchecked Sendable { var control: OperationControl! }
    static func main() throws {
        if CommandLine.arguments.count > 1 {
            let source = URL(fileURLWithPath: CommandLine.arguments[2])
            if CommandLine.arguments[1] == "write-failure" {
                signal(SIGXFSZ, SIG_IGN)
                var limit = rlimit(rlim_cur: 1024 * 1024, rlim_max: 1024 * 1024)
                guard setrlimit(RLIMIT_FSIZE, &limit) == 0 else { fatalError("cannot set test file size limit") }
                do { _ = try LockEngine.encryptInPlace(source, password: secret) }
                catch { _exit(87) }
                fatalError("expected write failure")
            }
            let step = CommandLine.arguments[3]
            let hook: (LockEngine.Checkpoint) throws -> Void = { point in
                if (step == "moved" && point == .sourceMoved) || (step == "published" && point == .published) || (step == "verified" && point == .verified) { _exit(86) }
            }
            if CommandLine.arguments[1] == "decrypt" { _ = try LockEngine.decryptInPlace(source, password: secret, checkpoint: hook) }
            else { _ = try LockEngine.encryptInPlace(source, password: secret, checkpoint: hook) }
            fatalError("child did not reach checkpoint")
        }
        let root = fm.temporaryDirectory.appendingPathComponent("easylock-stream-tests-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: root) }
        let large = root.appendingPathComponent("大文件.mov")
        fm.createFile(atPath: large.path, contents: nil)
        let output = try FileHandle(forWritingTo: large)
        let block = Data((0..<1024 * 1024).map { UInt8(truncatingIfNeeded: $0 * 7) })
        for _ in 0..<70 { try output.write(contentsOf: block) }
        try output.close()
        let original = try StreamArchive.hash(large, control: nil)
        let encrypted = try LockEngine.encryptInPlace(large, password: secret)
        precondition(encrypted.warning == nil && !LockEngine.exists(large))
        let decrypted = try LockEngine.decryptInPlace(encrypted.url, password: secret)
        let roundtrip = try StreamArchive.hash(decrypted.url, control: nil)
        precondition(roundtrip == original)
        print("PASS: 70 MiB file exceeds legacy limit and round-trips with identical SHA256")
        let largeFolder = root.appendingPathComponent("大文件夹")
        try fm.createDirectory(at: largeFolder, withIntermediateDirectories: false)
        try fm.moveItem(at: large, to: largeFolder.appendingPathComponent(large.lastPathComponent))
        let folderLocked = try LockEngine.encryptInPlace(largeFolder, password: secret)
        _ = try LockEngine.decryptInPlace(folderLocked.url, password: secret)
        let folderHash = try StreamArchive.hash(largeFolder.appendingPathComponent(large.lastPathComponent), control: nil)
        precondition(folderHash == original)
        print("PASS: folder with more than 64 MiB round-trips")

        let small = root.appendingPathComponent("frames.bin")
        try (block + block + Data([1, 2, 3])).write(to: small)
        let manifest = try StreamArchive.snapshot(small)
        let cipher = root.appendingPathComponent("test.easylock")
        try StreamArchive.seal(manifest, source: small, to: cipher, password: secret, control: nil)
        let bytes = try Data(contentsOf: cipher)
        var offsets: [Range<Int>] = []; var offset = StreamArchive.magic.count + 16
        while offset < bytes.count {
            let length = bytes[offset..<offset+8].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            offsets.append(offset..<(offset + 8 + Int(length))); offset += 8 + Int(length)
        }
        var mutations: [(String, Data)] = [("truncation", Data(bytes.dropLast())), ("trailing data", bytes + Data([0]))]
        var tampered = bytes; tampered[offsets[1].lowerBound + 9] ^= 1
        mutations.append(("tampering", tampered))
        var reordered = bytes
        reordered.replaceSubrange(offsets[1], with: bytes[offsets[2]])
        reordered.replaceSubrange(offsets[2], with: bytes[offsets[1]])
        mutations.append(("reordered blocks", reordered))
        var duplicate = bytes; duplicate.replaceSubrange(offsets[2], with: bytes[offsets[1]])
        mutations.append(("duplicated blocks", duplicate))
        var oversized = bytes; oversized.replaceSubrange(offsets[1].lowerBound..<offsets[1].lowerBound+8, with: Data(repeating: 255, count: 8))
        mutations.append(("oversized frame", oversized))
        for (label, data) in mutations {
            let bad = root.appendingPathComponent("bad.easylock")
            try data.write(to: bad)
            try expectFailure(label) { _ = try LockEngine.decryptInPlace(bad, password: secret) }
            precondition(tryData(bad) == data)
            // Existing original is intentionally present; exercise full restore directly too.
            let staging = root.appendingPathComponent(UUID().uuidString)
            try fm.createDirectory(at: staging, withIntermediateDirectories: false)
            try expectFailure("authenticate \(label)") { _ = try StreamArchive.restore(bad, into: staging, password: secret, control: nil) }
            try fm.removeItem(at: staging)
        }
        try expectFailure("wrong stream password") { _ = try LockEngine.decryptInPlace(cipher, password: "incorrect") }

        for phase in ["检查文件", "加密内容", "恢复并校验内容"] {
            let source = root.appendingPathComponent("cancel-\(UUID().uuidString)")
            try (block + block).write(to: source)
            let box = ControlBox()
            box.control = OperationControl { update in if update.phase == phase { box.control.cancel() } }
            do { _ = try LockEngine.encryptInPlace(source, password: secret, control: box.control); fatalError("expected cancellation") }
            catch is CancellationError { }
            precondition(tryData(source) == block + block)
            precondition(!LockEngine.exists(source.appendingPathExtension("easylock")))
        }
        let failureSource = root.appendingPathComponent("write-failure.dat")
        try (block + block).write(to: failureSource)
        let failureProcess = Process()
        failureProcess.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        failureProcess.arguments = ["write-failure", failureSource.path]
        try failureProcess.run(); failureProcess.waitUntilExit()
        precondition(failureProcess.terminationStatus == 87)
        precondition(tryData(failureSource) == block + block)
        precondition(!LockEngine.exists(failureSource.appendingPathExtension("easylock")))
        print("PASS: real partial-write failure retains the original")
        let decryptCancel = root.appendingPathComponent("cancel-decryption.dat")
        try (block + block).write(to: decryptCancel)
        let cancelCipher = try LockEngine.encryptInPlace(decryptCancel, password: secret)
        let cipherBefore = tryData(cancelCipher.url)
        let cancelBox = ControlBox()
        cancelBox.control = OperationControl { update in if update.phase == "恢复并校验内容" { cancelBox.control.cancel() } }
        do { _ = try LockEngine.decryptInPlace(cancelCipher.url, password: secret, control: cancelBox.control); fatalError("expected decrypt cancellation") }
        catch is CancellationError { }
        precondition(tryData(cancelCipher.url) == cipherBefore && !LockEngine.exists(decryptCancel))
        print("PASS: cancellation during decryption retains identical ciphertext")
        let commit = root.appendingPathComponent("commit.txt")
        try Data("commit".utf8).write(to: commit)
        let control = OperationControl()
        let committed = try LockEngine.encryptInPlace(commit, password: secret, control: control) { if $0 == .sourceMoved { control.cancel() } }
        precondition(committed.warning == nil && !LockEngine.exists(commit))
        _ = try LockEngine.decryptInPlace(committed.url, password: secret)
        print("PASS: cancellation during scan/encrypt/restore retains source; cancellation during commit finishes safely")

        for step in ["verified", "moved", "published"] {
            let parent = root.appendingPathComponent("crash-\(step)")
            try fm.createDirectory(at: parent, withIntermediateDirectories: false)
            let source = parent.appendingPathComponent("original.txt")
            try block.write(to: source)
            try crash(source, operation: "encrypt", step: step)
            let entries = try TransactionRecovery.scan(parent)
            precondition(entries.count == 1)
            if step == "verified" {
                precondition(entries[0].canDiscard)
                try TransactionRecovery.discard(entries[0])
            } else {
                precondition(entries[0].canRestore)
                if step == "moved" {
                    try Data("new file".utf8).write(to: source)
                    try expectFailure("recovery collision") { try TransactionRecovery.recover(entries[0]) }
                    precondition(tryData(source) == Data("new file".utf8))
                    try fm.removeItem(at: source)
                }
                try TransactionRecovery.recover(entries[0])
            }
            precondition(tryData(source) == block)
            precondition(tryScan(parent).isEmpty)
            if step == "published" { precondition(LockEngine.exists(source.appendingPathExtension("easylock"))) }
        }
        let parent = root.appendingPathComponent("decrypt-crash")
        try fm.createDirectory(at: parent, withIntermediateDirectories: false)
        let source = parent.appendingPathComponent("original.docx")
        try block.write(to: source)
        let locked = try LockEngine.encryptInPlace(source, password: secret)
        let oldCipher = tryData(locked.url)
        try crash(locked.url, operation: "decrypt", step: "moved")
        let recovery = try TransactionRecovery.scan(parent)
        precondition(recovery.count == 1 && recovery[0].canRestore)
        try TransactionRecovery.recover(recovery[0])
        precondition(tryData(locked.url) == oldCipher && !LockEngine.exists(source))
        _ = try LockEngine.decryptInPlace(locked.url, password: secret)
        precondition(tryData(source) == block)
        print("PASS: real process termination before move/after move/after publication; restart recovery preserves originals and collisions")

        // A partly removed directory must never be presented as a complete original.
        let unsafe = root.appendingPathComponent(".easylock-transaction-\(UUID().uuidString)")
        try fm.createDirectory(at: unsafe, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        try fm.createDirectory(at: unsafe.appendingPathComponent("original"), withIntermediateDirectories: false)
        let record = LockEngine.Journal(operation: "encrypt", originalName: "lost", resultName: "lost.easylock", phase: "cleaning-original")
        try JSONEncoder().encode(record).write(to: unsafe.appendingPathComponent("recovery.json"))
        let unsafeItem = try TransactionRecovery.inspect(unsafe)
        precondition(!unsafeItem.canRestore && !unsafeItem.canDiscard)
        try expectFailure("partial cleanup is not a complete backup") { try TransactionRecovery.recover(unsafeItem) }
        print("ALL STREAM AND RECOVERY TESTS PASSED")
    }
    static func crash(_ source: URL, operation: String, step: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        process.arguments = [operation, source.path, step]
        try process.run(); process.waitUntilExit()
        precondition(process.terminationStatus == 86)
    }
    static func tryData(_ url: URL) -> Data { try! Data(contentsOf: url) }
    static func tryScan(_ url: URL) -> [TransactionRecovery.Item] { try! TransactionRecovery.scan(url) }
    static func expectFailure(_ label: String, _ work: () throws -> Void) throws {
        do { try work() } catch { print("PASS: \(label)"); return }
        fatalError("Expected failure: \(label)")
    }
}
