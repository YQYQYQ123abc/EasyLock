import Foundation

extension LockEngine {
    /// Restore beside a user-selected destination. The ciphertext is always retained.
    static func decryptCopy(_ source: URL, into parent: URL, password: String, recoveryKey: String? = nil, control: OperationControl? = nil) throws -> Result {
        let transaction = parent.appendingPathComponent(".easylock-transaction-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: transaction, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let restoredParent = transaction.appendingPathComponent("restored", isDirectory: true)
        var published: URL?
        do {
            try FileManager.default.createDirectory(at: restoredParent, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let restored: URL
            if try StreamArchive.isStream(source) {
                let input = try StreamArchive.reader(source)
                let manifest: StreamArchive.Manifest
                do { manifest = try StreamArchive.openManifest(input, password: password, recoveryKey: recoveryKey).0; try input.close() }
                catch { try? input.close(); throw error }
                try SpacePreflight.check(manifest, at: parent)
                let journal = Journal(operation: "copy", originalName: manifest.name, resultName: manifest.name, phase: "preparing")
                let path = transaction.appendingPathComponent("recovery.json")
                try JSONEncoder().encode(journal).write(to: path, options: .atomic)
                try synchronize(path); try synchronizeDirectory(transaction)
                restored = try StreamArchive.restore(source, into: restoredParent, password: password, recoveryKey: recoveryKey, control: control).1
            } else {
                guard recoveryKey == nil else { throw Failure.message("此旧版文件不支持恢复密钥，请使用原加密密码。") }
                let archive = try open(read(source), password: password)
                let total = archive.entries.reduce(Int64(0)) { $0 + Int64($1.contents?.count ?? 0) }
                _ = try SpacePreflight.check(content: total, metadata: Int64(maximumBytes), entries: archive.entries.count, at: parent, encrypt: false)
                let path = transaction.appendingPathComponent("recovery.json")
                try JSONEncoder().encode(Journal(operation: "copy", originalName: archive.name, resultName: archive.name, phase: "preparing")).write(to: path, options: .atomic)
                try synchronize(path); try synchronizeDirectory(transaction)
                restored = try restore(archive, into: restoredParent)
                try verify(archive, at: restored)
            }
            let target = parent.appendingPathComponent(restored.lastPathComponent)
            guard !exists(target) else { throw Failure.message("目标目录已有“\(target.lastPathComponent)”，请另选目录。没有覆盖任何文件。") }
            try control?.check()
            try moveExclusive(restored, to: target)
            published = target
            try synchronizeDirectory(parent)
            try FileManager.default.removeItem(at: transaction)
            return Result(url: target, warning: nil)
        } catch {
            if let published { return Result(url: published, warning: "文件已恢复，密文保留；临时目录尚需检查：\(transaction.path)") }
            do { try FileManager.default.removeItem(at: transaction) }
            catch { throw Failure.message("恢复已停止，密文未修改。临时明文清理失败，请检查：\(transaction.path)") }
            throw error
        }
    }
}
