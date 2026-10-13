import Foundation

@main
struct EngineTests {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("easylock-test-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let source = root.appendingPathComponent("私人资料")
        try fm.createDirectory(at: source.appendingPathComponent("空文件夹"), withIntermediateDirectories: true)
        let payload = Data("private content \u{0} 你好".utf8)
        try payload.write(to: source.appendingPathComponent("记录.txt"))
        try Data().write(to: source.appendingPathComponent("empty"))
        let password = "correct horse battery staple"
        let sealed = try LockEngine.seal(source, password: password)
        precondition(sealed.range(of: payload) == nil, "Plaintext leaked")
        let encrypted = root.appendingPathComponent("test.easylock")
        try LockEngine.saveEncrypted(sealed, to: encrypted, password: password)
        try mustFail("no overwrite") { try LockEngine.saveEncrypted(sealed, to: encrypted, password: password) }
        let archive = try LockEngine.open(LockEngine.read(encrypted), password: password)
        let output = root.appendingPathComponent("output")
        try fm.createDirectory(at: output, withIntermediateDirectories: true)
        let restored = try LockEngine.restore(archive, into: output)
        precondition(tryData(restored.appendingPathComponent("记录.txt")) == payload)
        precondition(fm.fileExists(atPath: restored.appendingPathComponent("空文件夹").path))
        precondition(tryData(restored.appendingPathComponent("empty")).isEmpty)
        try mustFail("wrong password") { _ = try LockEngine.open(sealed, password: "incorrect") }
        var damaged = sealed; damaged[damaged.count - 1] ^= 1
        try mustFail("tampered ciphertext") { _ = try LockEngine.open(damaged, password: password) }
        try mustFail("truncated ciphertext") { _ = try LockEngine.open(Data(sealed.prefix(20)), password: password) }
        try mustFail("restore collision") { _ = try LockEngine.restore(archive, into: output) }
        precondition(tryData(restored.appendingPathComponent("记录.txt")) == payload)
        let malicious = LockEngine.Archive(name: "safe", directory: true, entries: [.init(path: "../escape", directory: false, contents: payload)])
        try mustFail("path traversal") { _ = try LockEngine.restore(malicious, into: output) }
        let file = source.appendingPathComponent("记录.txt")
        let fileArchive = try LockEngine.open(LockEngine.seal(file, password: password), password: password)
        _ = try LockEngine.restore(fileArchive, into: output)
        precondition(tryData(output.appendingPathComponent("记录.txt")) == payload)
        try fm.createSymbolicLink(at: source.appendingPathComponent("link"), withDestinationURL: file)
        try mustFail("symbolic link") { _ = try LockEngine.seal(source, password: password) }
        let large = root.appendingPathComponent("too-large")
        fm.createFile(atPath: large.path, contents: nil)
        let largeHandle = try FileHandle(forWritingTo: large)
        try largeHandle.truncate(atOffset: UInt64(LockEngine.maximumBytes + 1))
        try largeHandle.close()
        try mustFail("size limit") { _ = try LockEngine.seal(large, password: password) }
        let duplicate = LockEngine.Archive(name: "safe", directory: true, entries: [.init(path: "same", directory: true, contents: nil), .init(path: "same", directory: false, contents: payload)])
        try mustFail("duplicate archive paths") { try LockEngine.validate(duplicate) }
        precondition(tryData(file) == payload, "Source modified")
        print("PASS: directory and file round trips, Unicode, empty files/directories, ciphertext privacy, wrong password, tampering, truncation, overwrite prevention, path traversal, symlink rejection, source preservation")
    }
    static func tryData(_ url: URL) -> Data { try! Data(contentsOf: url) }
    static func mustFail(_ name: String, operation: () throws -> Void) throws {
        do { try operation() } catch { print("PASS: \(name)"); return }
        fatalError("Expected failure: \(name)")
    }
}
