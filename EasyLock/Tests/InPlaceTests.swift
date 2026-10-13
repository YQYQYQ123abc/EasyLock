import Foundation
import Darwin
import CryptoKit

@main
struct InPlaceTests {
    static let password = "in-place roundtrip test password"
    static let fm = FileManager.default
    enum Injected: Error { case failure }

    static func main() throws {
        let root = fm.temporaryDirectory.appendingPathComponent("easylock-inplace-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let source = root.appendingPathComponent("原始文件.pdf")
        let bytes = Data((0..<8192).map { UInt8($0 % 256) })
        try bytes.write(to: source)
        try fm.setAttributes([.posixPermissions: 0o751], ofItemAtPath: source.path)
        try xattr(source, "com.easylock.test", Data("标签与二进制\0".utf8))
        try xattr(source, "com.apple.ResourceFork", Data("resource-fork-content".utf8))
        let tags = try PropertyListSerialization.data(fromPropertyList: ["重要\n6"], format: .binary, options: 0)
        try xattr(source, "com.apple.metadata:_kMDItemUserTags", tags)
        let chmodProcess = Process()
        chmodProcess.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmodProcess.arguments = ["+a", "\(NSUserName()) allow read,readattr,readextattr,readsecurity", source.path]
        try chmodProcess.run(); chmodProcess.waitUntilExit()
        precondition(chmodProcess.terminationStatus == 0)
        let captured = try FileMetadata.capture(source)
        precondition(captured.acl != nil, "ACL fixture missing")
        let original = try LockEngine.snapshot(source)
        let encrypted = try LockEngine.encryptInPlace(source, password: password)
        precondition(encrypted.warning == nil)
        precondition(!LockEngine.exists(source))
        precondition(encrypted.url.lastPathComponent == "原始文件.pdf.easylock")
        precondition(tryIsEncrypted(encrypted.url))
        precondition(tryData(encrypted.url).range(of: bytes) == nil)
        // Spoofing a PDF extension must never turn ciphertext into PDF content.
        let renamed = root.appendingPathComponent("改名.jpg")
        try fm.moveItem(at: encrypted.url, to: renamed)
        precondition(tryIsEncrypted(renamed))
        try mustFail("double encryption after extension change") { _ = try LockEngine.encryptInPlace(renamed, password: password) }
        try mustFail("incorrect password retains ciphertext") { _ = try LockEngine.decryptInPlace(renamed, password: "wrong") }
        precondition(LockEngine.exists(renamed))
        let restored = try LockEngine.decryptInPlace(renamed, password: password)
        precondition(restored.url.lastPathComponent == "原始文件.pdf")
        precondition(!LockEngine.exists(renamed))
        try LockEngine.verify(original, at: restored.url)
        precondition(tryData(restored.url) == bytes)
        let restoredMetadata = try FileMetadata.capture(restored.url)
        precondition(captured.matches(restoredMetadata))
        print("PASS: in-place file, byte identity, original extension, ACL, mode, dates, tags, resource fork, renamed ciphertext")

        // Ciphertext may be renamed to exactly the original name before decryption.
        let second = try LockEngine.encryptInPlace(source, password: password)
        try fm.moveItem(at: second.url, to: source)
        _ = try LockEngine.decryptInPlace(source, password: password)
        precondition(tryData(source) == bytes)
        print("PASS: ciphertext renamed to original filename")

        let directory = root.appendingPathComponent("文件夹.bundle")
        try fm.createDirectory(at: directory.appendingPathComponent("子目录/空目录"), withIntermediateDirectories: true)
        try bytes.write(to: directory.appendingPathComponent("子目录/内容.docx"))
        try Data().write(to: directory.appendingPathComponent(".hidden"))
        try xattr(directory, "com.easylock.folder", Data([1, 2, 3]))
        let directorySnapshot = try LockEngine.snapshot(directory)
        let lockedDirectory = try LockEngine.encryptInPlace(directory, password: password)
        precondition(!LockEngine.exists(directory))
        _ = try LockEngine.decryptInPlace(lockedDirectory.url, password: password)
        try LockEngine.verify(directorySnapshot, at: directory)
        print("PASS: nested directory, empty/hidden entries, package extension and directory metadata")

        let collision = root.appendingPathComponent("collision.txt")
        try bytes.write(to: collision)
        let occupied = collision.appendingPathExtension("easylock")
        try Data("do not overwrite".utf8).write(to: occupied)
        try mustFail("encrypt collision") { _ = try LockEngine.encryptInPlace(collision, password: password) }
        precondition(tryData(collision) == bytes && tryData(occupied) == Data("do not overwrite".utf8))
        try fm.removeItem(at: occupied)
        let collisionEncrypted = try LockEngine.encryptInPlace(collision, password: password)
        try Data("new user file".utf8).write(to: collision)
        try mustFail("decrypt collision") { _ = try LockEngine.decryptInPlace(collisionEncrypted.url, password: password) }
        precondition(tryData(collision) == Data("new user file".utf8))
        precondition(LockEngine.exists(collisionEncrypted.url))

        let rollback = root.appendingPathComponent("rollback.txt")
        try bytes.write(to: rollback)
        try mustFail("encryption rollback after original move") {
            _ = try LockEngine.encryptInPlace(rollback, password: password) { if $0 == .sourceMoved { throw Injected.failure } }
        }
        precondition(tryData(rollback) == bytes)
        precondition(!LockEngine.exists(rollback.appendingPathExtension("easylock")))
        let edited = Data("edited while encrypting".utf8)
        try mustFail("source changed before commit") {
            _ = try LockEngine.encryptInPlace(rollback, password: password) { if $0 == .verified { try edited.write(to: rollback) } }
        }
        precondition(tryData(rollback) == edited)
        let rollbackEncrypted = try LockEngine.encryptInPlace(rollback, password: password)
        let rollbackCipher = tryData(rollbackEncrypted.url)
        try mustFail("decryption rollback after ciphertext move") {
            _ = try LockEngine.decryptInPlace(rollbackEncrypted.url, password: password) { if $0 == .sourceMoved { throw Injected.failure } }
        }
        precondition(tryData(rollbackEncrypted.url) == rollbackCipher)
        precondition(!LockEngine.exists(rollback))

        let partial = root.appendingPathComponent("cleanup.txt")
        try bytes.write(to: partial)
        let partialResult = try LockEngine.encryptInPlace(partial, password: password) { if $0 == .published { throw Injected.failure } }
        precondition(partialResult.warning != nil)
        precondition(tryIsEncrypted(partialResult.url))
        let pending = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix(".easylock-transaction-") }
        precondition(pending.count == 1)
        precondition(tryData(pending[0].appendingPathComponent("original")) == bytes)
        print("PASS: partial publication retains verified ciphertext and original with explicit warning")

        let fake = root.appendingPathComponent("fake.easylock")
        try Data("not encrypted".utf8).write(to: fake)
        precondition(!tryIsEncrypted(fake))
        let hard = root.appendingPathComponent("hard-link")
        try fm.linkItem(at: source, to: hard)
        try mustFail("hard-link preservation guard") { _ = try LockEngine.encryptInPlace(source, password: password) }
        // A version-1 fixture has content but no metadata. It remains decryptable with a warning.
        let legacyArchive = LockEngine.Archive(name: "legacy.txt", directory: false, entries: [.init(path: "legacy.txt", directory: false, contents: bytes)])
        let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
        let salt = try LockEngine.random(16)
        let header = Data("EASYLOCK\u{0}01".utf8) + salt
        let key = SymmetricKey(data: try LockEngine.derive(password, salt: salt))
        let legacy = header + (try AES.GCM.seal(encoder.encode(legacyArchive), using: key, authenticating: header)).combined!
        let legacyURL = root.appendingPathComponent("legacy.easylock")
        try legacy.write(to: legacyURL)
        let legacyResult = try LockEngine.decryptInPlace(legacyURL, password: password)
        precondition(legacyResult.warning != nil)
        precondition(tryData(legacyResult.url) == bytes)
        print("PASS: legacy format restores contents with explicit metadata warning")
        print("ALL IN-PLACE TESTS PASSED")
    }
    static func xattr(_ url: URL, _ key: String, _ value: Data) throws {
        let result = value.withUnsafeBytes { setxattr(url.path, key, $0.baseAddress, value.count, 0, XATTR_NOFOLLOW) }
        guard result == 0 else { throw FileMetadata.posix("test xattr", url) }
    }
    static func tryData(_ url: URL) -> Data { try! Data(contentsOf: url) }
    static func tryIsEncrypted(_ url: URL) -> Bool { try! LockEngine.isEncrypted(url) }
    static func mustFail(_ name: String, operation: () throws -> Void) throws {
        do { try operation() } catch { print("PASS: \(name)"); return }
        fatalError("Expected failure: \(name)")
    }
}
