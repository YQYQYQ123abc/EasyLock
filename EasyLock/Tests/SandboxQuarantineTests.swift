import Foundation
import CoreServices
import Darwin

@main
struct SandboxQuarantineTests {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("easylock-sandbox-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let folder = root.appendingPathComponent("Xmind")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let document = folder.appendingPathComponent("就业推荐表.docx")
        let dsStore = folder.appendingPathComponent(".DS_Store")
        let contents = Data([0x50, 0x4b, 0x03, 0x04, 0, 0xff])
        for url in [document, dsStore] {
            try contents.write(to: url)
            // The real sandbox rejects this exact operation in the user's screenshot.
            let raw = Data("0081;65a00000;OriginalDownload;".utf8)
            let result = raw.withUnsafeBytes { setxattr(url.path, "com.apple.quarantine", $0.baseAddress, raw.count, 0, XATTR_NOFOLLOW) }
            guard result == -1 && errno == EPERM else { fatalError("Not running under the expected App Sandbox quarantine restriction") }
            let properties: [String: Any] = [kLSQuarantineTypeKey as String: kLSQuarantineTypeOtherDownload as String, kLSQuarantineTimeStampKey as String: Date()]
            try (url as NSURL).setResourceValue(properties, forKey: .quarantinePropertiesKey)
        }
        let password = "sandbox round-trip test"
        let before = try LockEngine.snapshot(folder)
        let encrypted = try LockEngine.encryptInPlace(folder, password: password)
        precondition(encrypted.warning == nil && !LockEngine.exists(folder))
        let restored = try LockEngine.decryptInPlace(encrypted.url, password: password)
        precondition(restored.warning == nil)
        try LockEngine.verify(before, at: restored.url)
        for url in [document, dsStore] {
            let metadata = try FileMetadata.capture(url)
            let bytes = try Data(contentsOf: url)
            precondition(bytes == contents && metadata.attributes[FileMetadata.quarantineAttribute]?.isEmpty == false)
        }
        // Also cover a single Office file as reported in the second screenshot.
        let single = try LockEngine.encryptInPlace(document, password: password)
        _ = try LockEngine.decryptInPlace(single.url, password: password)
        let recovery = RecoveryKey.generate()
        let protected = try LockEngine.encryptInPlace(document, password: password, recoveryPublicKey: RecoveryKey.publicKey(recovery))
        let copyParent = root.appendingPathComponent("alternate")
        try fm.createDirectory(at: copyParent, withIntermediateDirectories: false)
        let copy = try LockEngine.decryptCopy(protected.url, into: copyParent, password: "", recoveryKey: recovery)
        precondition(LockEngine.exists(protected.url))
        let copyBytes = try Data(contentsOf: copy.url)
        precondition(copyBytes == contents)
        _ = try LockEngine.decryptInPlace(protected.url, password: "", recoveryKey: recovery)
        print("PASS: sandbox recovery-key decryption and alternate-location copy preserve ciphertext and quarantine")
        let after = try Data(contentsOf: document)
        precondition(after == contents)
        print("PASS: actual signed App Sandbox reproduces EPERM for raw quarantine replay; fixed folder/.DS_Store/DOCX round trips succeed with quarantine retained")
    }
}
