import Foundation

@main struct PrivatePreviewTests {
    @MainActor static func main() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("preview-test-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let cache = root.appendingPathComponent("cache.noindex")
        do {
            let first = try PreviewWorkspace(root: cache)
            let mode = try fm.attributesOfItem(atPath: cache.path)[.posixPermissions] as! NSNumber
            precondition(mode.intValue == 0o700)
            do { _ = try PreviewWorkspace(root: cache); preconditionFailure("lease allowed concurrent cleanup") }
            catch {}
            try Data("stale plaintext".utf8).write(to: first.folder.appendingPathComponent("old.txt"))
        }
        let preview = PrivatePreview(root: cache)
        precondition(!fm.fileExists(atPath: cache.appendingPathComponent("session").path))
        let folder = root.appendingPathComponent("文件夹", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("private preview content".utf8).write(to: folder.appendingPathComponent("说明.txt"))
        let password = "private-preview-test-password"
        let locked = try LockEngine.encryptInPlace(folder, password: password)
        let ciphertext = try Data(contentsOf: locked.url)
        let item = LockedItem(name: "文件夹", path: locked.url.path, date: Date(), size: ciphertext.count, originalRetained: false)
        preview.begin(item)
        await preview.open(password: "wrong-password")
        precondition(preview.restored == nil && preview.message != nil)
        precondition(!fm.fileExists(atPath: cache.appendingPathComponent("session").path))
        await preview.open(password: password)
        guard let restored = preview.restored else { preconditionFailure(preview.message ?? "no preview") }
        let plaintext = try String(contentsOf: restored.appendingPathComponent("说明.txt"), encoding: .utf8)
        precondition(plaintext == "private preview content")
        let after = try Data(contentsOf: locked.url)
        precondition(after == ciphertext && !fm.fileExists(atPath: folder.path))
        preview.close()
        precondition(preview.restored == nil && !fm.fileExists(atPath: restored.path))
        preview.begin(item)
        let task = Task { await preview.open(password: password) }
        while !preview.busy { await Task.yield() }
        preview.close()
        await task.value
        precondition(preview.restored == nil && !preview.busy && !preview.requested)
        precondition(!fm.fileExists(atPath: cache.appendingPathComponent("session").path))
        let finalCiphertext = try Data(contentsOf: locked.url)
        precondition(finalCiphertext == ciphertext)
        print("PASS: private preview lease, 0700 workspace, stale cleanup, wrong password, folder preview, retained ciphertext, close and cancellation cleanup")
    }
}
