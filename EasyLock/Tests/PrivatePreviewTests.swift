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
        // Stale and explicitly closed previews must remove read-only directories without following links.
        let outside = root.appendingPathComponent("original.txt")
        try Data("original".utf8).write(to: outside)
        try fm.setAttributes([.posixPermissions: 0o444], ofItemAtPath: outside.path)
        for stale in [true, false] {
            do {
                let workspace = try PreviewWorkspace(root: cache)
                let readOnly = workspace.folder.appendingPathComponent("readonly")
                try fm.createDirectory(at: readOnly, withIntermediateDirectories: false)
                try Data("plaintext".utf8).write(to: readOnly.appendingPathComponent("secret.txt"))
                try fm.createSymbolicLink(at: readOnly.appendingPathComponent("link"), withDestinationURL: outside)
                try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: readOnly.path)
                if !stale { try workspace.clean(); try workspace.clean() }
            }
            let next = try PreviewWorkspace(root: cache)
            let contents = try fm.contentsOfDirectory(atPath: next.folder.path)
            precondition(contents.isEmpty)
            try next.clean()
            let original = try Data(contentsOf: outside)
            precondition(original == Data("original".utf8))
            let attributes = try fm.attributesOfItem(atPath: outside.path)
            precondition((attributes[.posixPermissions] as! NSNumber).intValue == 0o444)
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
