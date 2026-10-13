import Foundation
import CryptoKit

@main
struct ReleaseSafetyTests {
    static let fm = FileManager.default
    static let password = "release safety test password"
    static func main() throws {
        let root = fm.temporaryDirectory.appendingPathComponent("easylock-release-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: root) }
        let key = RecoveryKey.generate()
        let publicKey = try RecoveryKey.publicKey(key)
        try fail("mistyped recovery key") { _ = try RecoveryKey.publicKey(key + "x") }
        let source = root.appendingPathComponent("recovery.json")
        let bytes = Data((0..<2_200_000).map { UInt8(truncatingIfNeeded: $0) })
        try bytes.write(to: source)
        let original = try StreamArchive.snapshot(source)
        let locked = try LockEngine.encryptInPlace(source, password: password, recoveryPublicKey: publicKey)
        precondition(!LockEngine.exists(source))
        let ciphertext = try Data(contentsOf: locked.url)
        precondition(ciphertext.starts(with: RecoveryKey.magic))
        try fail("wrong password for recovery-capable archive") { _ = try LockEngine.decryptInPlace(locked.url, password: "wrong") }
        try fail("wrong recovery recipient") { _ = try LockEngine.decryptInPlace(locked.url, password: "", recoveryKey: RecoveryKey.generate()) }
        let destination = root.appendingPathComponent("副本")
        try fm.createDirectory(at: destination, withIntermediateDirectories: false)
        let copy = try LockEngine.decryptCopy(locked.url, into: destination, password: "", recoveryKey: key)
        precondition(copy.warning == nil && LockEngine.exists(locked.url))
        precondition(data(copy.url) == bytes && data(locked.url) == ciphertext)
        try fail("copy restore never overwrites destination") { _ = try LockEngine.decryptCopy(locked.url, into: destination, password: password) }
        precondition(data(copy.url) == bytes && data(locked.url) == ciphertext)
        _ = try LockEngine.decryptInPlace(locked.url, password: password)
        try StreamArchive.verify(original, at: source, control: nil)
        let second = try LockEngine.encryptInPlace(source, password: "different new password", recoveryPublicKey: publicKey)
        _ = try LockEngine.decryptInPlace(second.url, password: "", recoveryKey: key)
        precondition(data(source) == bytes)
        print("PASS: password and independent recovery both restore v4; same recovery key works across password changes")
        print("PASS: copy restore handles reserved-looking filenames, keeps ciphertext and refuses collisions")

        // Both key slots participate in frame AAD, including the slot not used to open the archive.
        for offset in [RecoveryKey.prefixLength + 15, RecoveryKey.headerLength - 1, RecoveryKey.magic.count + 20] {
            var damaged = ciphertext; damaged[offset] ^= 1
            let bad = root.appendingPathComponent("bad.easylock")
            try damaged.write(to: bad)
            let target = root.appendingPathComponent("tampered-\(offset)")
            try fm.createDirectory(at: target, withIntermediateDirectories: false)
            try fail("tampered v4 key slots/header password path") { _ = try LockEngine.decryptCopy(bad, into: target, password: password) }
            try fail("tampered v4 key slots/header recovery path") { _ = try LockEngine.decryptCopy(bad, into: target, password: "", recoveryKey: key) }
            precondition(data(bad) == damaged)
        }
        let legacy3 = try LockEngine.encryptInPlace(source, password: password)
        try fail("v3 does not pretend to support recovery") { _ = try LockEngine.decryptInPlace(legacy3.url, password: "", recoveryKey: key) }
        _ = try LockEngine.decryptInPlace(legacy3.url, password: password)
        print("PASS: legacy v3 remains readable with original password")

        let credentialFile = root.appendingPathComponent("credential.json")
        let credential = try PasswordCredential.make(password)
        try credential.save(to: credentialFile)
        let saved = try JSONDecoder().decode(PasswordCredential.self, from: Data(contentsOf: credentialFile))
        precondition(tryMatch(saved, password))
        precondition(!tryMatch(saved, "wrong"))
        let replacement = try PasswordCredential.make("replacement password")
        try replacement.save(to: credentialFile)
        let reloaded = try JSONDecoder().decode(PasswordCredential.self, from: Data(contentsOf: credentialFile))
        precondition(tryMatch(reloaded, "replacement password") && !tryMatch(reloaded, password))
        print("PASS: persisted password verifier replacement and wrong-password rejection")

        let estimate = try SpacePreflight.check(content: 100, metadata: 50, entries: 1, at: root, encrypt: true, availableBytes: 100_000_000)
        precondition(estimate.requiredBytes > 300)
        try fail("insufficient space preflight") { _ = try SpacePreflight.check(content: 100, metadata: 0, entries: 1, at: root, encrypt: true, availableBytes: 1) }
        try fail("overflow in space estimate") { _ = try SpacePreflight.required(content: Int64.max, metadata: 1, entries: 1, encrypt: true) }
        let before = data(source)
        _ = try SpacePreflight.inspect(source)
        precondition(data(source) == before)
        print("PASS: conservative disk estimate, insufficient space, overflow and source preservation")
        print("ALL RELEASE SAFETY TESTS PASSED")
    }
    static func data(_ url: URL) -> Data { try! Data(contentsOf: url) }
    static func tryMatch(_ value: PasswordCredential, _ input: String) -> Bool { try! value.matches(input) }
    static func fail(_ label: String, _ work: () throws -> Void) throws {
        do { try work() } catch { print("PASS: \(label)"); return }
        fatalError("Expected rejection: \(label)")
    }
}
