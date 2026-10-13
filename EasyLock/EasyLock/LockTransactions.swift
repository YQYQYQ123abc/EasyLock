import Foundation

extension LockEngine {
    struct Result {
        let url: URL
        let warning: String?
    }
    enum Checkpoint { case verified, sourceMoved, published }
    struct Journal: Codable {
        var version: Int? = 2
        let operation: String
        let originalName: String
        let resultName: String
        var phase: String
    }

    /// File coordination protects cooperating apps. Content is checked again after moving the source.
    static func encryptInPlace(_ source: URL, password: String, recoveryPublicKey: Data? = nil, control: OperationControl? = nil, checkpoint: ((Checkpoint) throws -> Void)? = nil) throws -> Result {
        try coordinated(source) { url in try encryptTransaction(url, password: password, recoveryPublicKey: recoveryPublicKey, control: control, checkpoint: checkpoint) }
    }

    static func decryptInPlace(_ source: URL, password: String, recoveryKey: String? = nil, control: OperationControl? = nil, checkpoint: ((Checkpoint) throws -> Void)? = nil) throws -> Result {
        try coordinated(source) { url in try decryptTransaction(url, password: password, recoveryKey: recoveryKey, control: control, checkpoint: checkpoint) }
    }

    private static func coordinated<T>(_ source: URL, work: (URL) throws -> T) throws -> T {
        let coordinator = NSFileCoordinator()
        var error: NSError?
        var result: Swift.Result<T, Error>?
        coordinator.coordinate(writingItemAt: source, options: .forMoving, error: &error) { url in
            result = Swift.Result { try work(url) }
        }
        if let error { throw error }
        guard let result else { throw Failure.message("无法获得文件访问权。") }
        return try result.get()
    }

    private static func makeTransaction(beside source: URL) throws -> URL {
        let folder = source.deletingLastPathComponent().appendingPathComponent(".easylock-transaction-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return folder
    }
    private static func journal(_ value: Journal, at transaction: URL) throws {
        let path = transaction.appendingPathComponent("recovery.json")
        try JSONEncoder().encode(value).write(to: path, options: .atomic)
        try synchronize(path)
        try synchronizeDirectory(transaction)
        try synchronizeDirectory(transaction.deletingLastPathComponent())
    }

    private static func encryptTransaction(_ source: URL, password: String, recoveryPublicKey: Data?, control: OperationControl?, checkpoint: ((Checkpoint) throws -> Void)?) throws -> Result {
        guard !(try isEncrypted(source)) else { throw Failure.message("此文件已经加密，即使后缀已被修改也需要先解密。") }
        let output = source.appendingPathExtension("easylock")
        guard !exists(output) else { throw Failure.message("同名 .easylock 文件已存在，原件未修改。") }
        control?.update("检查可用空间")
        _ = try SpacePreflight.inspect(source, control: control)
        let archive = try StreamArchive.snapshot(source, control: control)
        try SpacePreflight.check(archive, at: source.deletingLastPathComponent(), encrypt: true)
        let transaction = try makeTransaction(beside: source)
        let original = transaction.appendingPathComponent("original")
        let encrypted = transaction.appendingPathComponent("encrypted")
        let verification = transaction.appendingPathComponent("verification", isDirectory: true)
        var record = Journal(operation: "encrypt", originalName: source.lastPathComponent, resultName: output.lastPathComponent, phase: "preparing")
        var moved = false
        var published = false
        do {
            try journal(record, at: transaction)
            try StreamArchive.seal(archive, source: source, to: encrypted, password: password, recoveryPublicKey: recoveryPublicKey, control: control)
            try FileManager.default.createDirectory(at: verification, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            _ = try StreamArchive.restore(encrypted, into: verification, password: password, control: control)
            // No original is removed unless a full restore including metadata succeeded.
            try FileManager.default.removeItem(at: verification)
            try checkpoint?(.verified)
            try control?.check()
            control?.update("正在安全替换，请稍候")
            record.phase = "moving-original"
            try journal(record, at: transaction)
            try moveExclusive(source, to: original)
            moved = true
            try synchronizeDirectory(transaction)
            try synchronizeDirectory(source.deletingLastPathComponent())
            try checkpoint?(.sourceMoved)
            try StreamArchive.verify(archive, at: original, control: nil)
            record.phase = "publishing-ciphertext"
            try journal(record, at: transaction)
            try moveExclusive(encrypted, to: output)
            published = true
            try synchronizeDirectory(output.deletingLastPathComponent())
            try checkpoint?(.published)
            record.phase = "ciphertext-published"
            try journal(record, at: transaction)
        } catch {
            // Before publication, put the complete original back. Never overwrite a newly-created path.
            if moved && !published {
                do {
                    try moveExclusive(original, to: source)
                    try synchronizeDirectory(source.deletingLastPathComponent())
                    try synchronizeDirectory(transaction)
                    try? FileManager.default.removeItem(at: transaction)
                }
                catch { throw Failure.message("操作中止，原件保存在：\(exists(original) ? original.path : source.path)。原位置被占用或无法回滚，请先恢复原件。") }
            } else if !moved {
                do { try FileManager.default.removeItem(at: transaction) }
                catch { throw Failure.message("操作已中止，原件未替换，但临时目录清理失败：\(transaction.path)。请检查其中的恢复文件。") }
            }
            if published {
                return Result(url: output, warning: "密文已保存，但原件仍保存在恢复目录：\(transaction.path)。请处理后再视为已保护。")
            }
            throw error
        }
        do {
            record.phase = "cleaning-original"
            try journal(record, at: transaction)
            try FileManager.default.removeItem(at: original)
            try FileManager.default.removeItem(at: transaction)
            try synchronizeDirectory(source.deletingLastPathComponent())
            return Result(url: output, warning: nil)
        } catch {
            return Result(url: output, warning: "密文已验证，但原件清理未完成。恢复目录：\(transaction.path)。其中可能仍有明文。")
        }
    }

    private static func decryptTransaction(_ source: URL, password: String, recoveryKey: String?, control: OperationControl?, checkpoint: ((Checkpoint) throws -> Void)?) throws -> Result {
        try control?.check()
        let cipherSize = try FileMetadata.status(source).st_size
        let fingerprint = try StreamArchive.hash(source, control: control) { count in control?.update("检查密文", count, cipherSize) }
        let streamed = try StreamArchive.isStream(source)
        guard streamed || recoveryKey == nil else { throw Failure.message("此旧版文件不支持恢复密钥，请使用原密码。") }
        let archive = streamed ? nil : try open(read(source), password: password)
        var streamManifest: StreamArchive.Manifest?
        if streamed {
            let input = try StreamArchive.reader(source)
            defer { try? input.close() }
            streamManifest = try StreamArchive.openManifest(input, password: password, recoveryKey: recoveryKey).0
        }
        let name = streamManifest?.name ?? archive!.name
        let directory = streamManifest?.directory ?? archive!.directory

        let parent = source.deletingLastPathComponent()
        if let streamManifest { try SpacePreflight.check(streamManifest, at: parent) }
        else if let archive {
            _ = try SpacePreflight.check(content: archive.entries.reduce(0) { $0 + Int64($1.contents?.count ?? 0) }, metadata: Int64(maximumBytes), entries: archive.entries.count, at: parent, encrypt: false)
        }
        let output = parent.appendingPathComponent(name, isDirectory: directory)
        if exists(output) {
            let a = try FileMetadata.status(source)
            let b = try FileMetadata.status(output)
            guard a.st_dev == b.st_dev && a.st_ino == b.st_ino else { throw Failure.message("原名称“\(name)”已被占用。请先移走同名项目，再解密。") }
        }
        let transaction = try makeTransaction(beside: source)
        let encrypted = transaction.appendingPathComponent("encrypted-original")
        let restoredParent = transaction.appendingPathComponent("restored", isDirectory: true)
        var record = Journal(operation: "decrypt", originalName: source.lastPathComponent, resultName: output.lastPathComponent, phase: "preparing")
        var moved = false
        var published = false
        do {
            try journal(record, at: transaction)
            try FileManager.default.createDirectory(at: restoredParent, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let restored: URL
            if streamed {
                restored = try StreamArchive.restore(source, into: restoredParent, password: password, recoveryKey: recoveryKey, control: control).1
                guard restored.lastPathComponent == name else { throw Failure.message("密文在解密期间发生变化，已取消替换。") }
            } else {
                restored = try restore(archive!, into: restoredParent)
                try verify(archive!, at: restored)
            }
            try checkpoint?(.verified)
            try control?.check()
            control?.update("正在安全替换，请稍候")
            record.phase = "moving-ciphertext"
            try journal(record, at: transaction)
            try moveExclusive(source, to: encrypted)
            moved = true
            try synchronizeDirectory(transaction)
            try synchronizeDirectory(source.deletingLastPathComponent())
            try checkpoint?(.sourceMoved)
            guard try StreamArchive.hash(encrypted, control: nil) == fingerprint else { throw Failure.message("密文在解密期间发生变化，已取消替换。") }
            record.phase = "publishing-original"
            try journal(record, at: transaction)
            try moveExclusive(restored, to: output)
            published = true
            try synchronizeDirectory(output.deletingLastPathComponent())
            try checkpoint?(.published)
            record.phase = "original-restored"
            try journal(record, at: transaction)
        } catch {
            if moved && !published {
                do {
                    try moveExclusive(encrypted, to: source)
                    try synchronizeDirectory(source.deletingLastPathComponent())
                    try synchronizeDirectory(transaction)
                    try? FileManager.default.removeItem(at: transaction)
                }
                catch { throw Failure.message("解密中止，密文仍在：\(exists(encrypted) ? encrypted.path : source.path)。原位置无法回滚，请先恢复该文件。") }
            } else if !moved {
                do { try FileManager.default.removeItem(at: transaction) }
                catch { throw Failure.message("操作已中止，原件未替换，但临时目录清理失败：\(transaction.path)。请检查其中的恢复文件。") }
            }
            if published { return Result(url: output, warning: "原文件已恢复，旧密文仍保存在：\(transaction.path)。") }
            throw error
        }
        do {
            record.phase = "cleaning-ciphertext"
            try journal(record, at: transaction)
            try FileManager.default.removeItem(at: transaction)
            try synchronizeDirectory(source.deletingLastPathComponent())
            return Result(url: output, warning: !streamed && archive?.metadata == nil ? "已恢复旧版文件内容。旧版密文未保存权限、标签等元数据，无法补回这些信息。" : nil)
        } catch { return Result(url: output, warning: "原文件已恢复，旧密文清理失败：\(transaction.path)。") }
    }
}
