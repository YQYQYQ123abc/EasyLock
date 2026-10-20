import Foundation
import Darwin

enum TransactionRecovery {
    struct Item: Identifiable, Sendable {
        var id: String { folder.path }
        let folder: URL
        let source: URL
        let result: URL
        let operation: String
        let phase: String
        let canRestore: Bool
        let canDiscard: Bool
        var explanation: String {
            if canRestore { return operation == "encrypt" ? "原件仍在恢复目录，可放回原位置。已有密文会保留。" : "原密文仍在恢复目录，可放回原位置。已恢复的文件会保留。" }
            if canDiscard { return operation == "copy" ? "恢复副本任务未完成，原密文未被移动。可以清理临时副本后重新恢复。" : "原位置仍有文件，可以清理尚未提交的临时副本。" }
            return "存在同名项目或清理已开始。已保留所有剩余数据，请在 Finder 中检查，避免覆盖。"
        }
    }
    static func component(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\0")
    }
    static func inspect(_ folder: URL) throws -> Item {
        let info = try FileMetadata.status(folder)
        guard folder.lastPathComponent.hasPrefix(".easylock-transaction-"), info.st_mode & S_IFMT == S_IFDIR,
              info.st_uid == getuid(), info.st_mode & 0o077 == 0 else { throw LockEngine.Failure.message("恢复目录权限或类型不正确。") }
        let input = try StreamArchive.reader(folder.appendingPathComponent("recovery.json"))
        defer { try? input.close() }
        let data = try input.read(upToCount: 64 * 1024) ?? Data()
        guard (try input.read(upToCount: 1) ?? Data()).isEmpty else { throw LockEngine.Failure.message("恢复记录过大。") }
        let record = try JSONDecoder().decode(LockEngine.Journal.self, from: data)
        guard ["encrypt", "decrypt", "copy"].contains(record.operation), component(record.originalName), component(record.resultName) else { throw LockEngine.Failure.message("恢复记录无效。") }
        let parent = folder.deletingLastPathComponent()
        let source = parent.appendingPathComponent(record.originalName)
        let backup = folder.appendingPathComponent(record.operation == "encrypt" ? "original" : "encrypted-original")
        let hasBackup = LockEngine.exists(backup)
        // A recursive cleanup may have removed part of a folder: never restore it as complete.
        let safePhase = ["moving-original", "publishing-ciphertext", "moving-ciphertext", "publishing-original"].contains(record.phase)
            || (record.version == 2 && ["ciphertext-published", "original-restored"].contains(record.phase))
        return Item(folder: folder, source: source, result: parent.appendingPathComponent(record.resultName), operation: record.operation, phase: record.phase,
                    canRestore: hasBackup && !LockEngine.exists(source) && safePhase,
                    canDiscard: !hasBackup && (LockEngine.exists(source) || record.operation == "copy") && ["preparing", "recovered"].contains(record.phase))
    }
    static func scan(_ parent: URL) throws -> [Item] {
        try FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(".easylock-transaction-") }
            .map { folder in
                (try? inspect(folder)) ?? Item(folder: folder, source: folder, result: folder, operation: "unknown", phase: "invalid", canRestore: false, canDiscard: false)
            }.sorted { $0.folder.path < $1.folder.path }
    }
    static func recover(_ item: Item) throws {
        let current = try inspect(item.folder)
        guard current.canRestore else { throw LockEngine.Failure.message("恢复状态已变化，未修改任何文件。请刷新后检查。") }
        let backup = item.folder.appendingPathComponent(current.operation == "encrypt" ? "original" : "encrypted-original")
        _ = try FileMetadata.capture(backup)
        try LockEngine.moveExclusive(backup, to: current.source)
        try LockEngine.synchronizeDirectory(current.source.deletingLastPathComponent())
        try LockEngine.synchronizeDirectory(item.folder)
        let journal = LockEngine.Journal(operation: current.operation, originalName: current.source.lastPathComponent, resultName: current.result.lastPathComponent, phase: "recovered")
        let path = item.folder.appendingPathComponent("recovery.json")
        try JSONEncoder().encode(journal).write(to: path, options: .atomic)
        try LockEngine.synchronize(path)
        // Never remove the published result. Only disposable transaction artifacts remain.
        try removeDisposableTree(item.folder)
        try LockEngine.synchronizeDirectory(current.source.deletingLastPathComponent())
    }
    /// Only call after transaction state validation, or for the disposable verification copy.
    /// Walk by descriptor so links cannot redirect permission changes outside the temporary tree.
    static func removeDisposableTree(_ url: URL) throws {
        let parent = url.deletingLastPathComponent()
        guard url.lastPathComponent.hasPrefix(".easylock-transaction-") ||
                (url.lastPathComponent == "verification" && parent.lastPathComponent.hasPrefix(".easylock-transaction-")) else {
            throw LockEngine.Failure.message("拒绝清理非事务临时目录。")
        }
        let descriptor = open(parent.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw FileMetadata.posix("无法访问临时目录的上级文件夹", parent) }
        defer { close(descriptor) }
        try removeEntry(url.lastPathComponent, parent: descriptor, display: url)
    }
    /// The caller holds the preview workspace lease. Only its fixed session child is disposable.
    static func removePreviewSession(in root: URL) throws {
        let descriptor = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw FileMetadata.posix("无法访问预览临时目录", root) }
        defer { close(descriptor) }
        var owner = stat()
        guard fstat(descriptor, &owner) == 0, owner.st_uid == getuid() else {
            throw LockEngine.Failure.message("预览临时目录所有者已变化，已停止清理。")
        }
        var info = stat()
        if fstatat(descriptor, "session", &info, AT_SYMLINK_NOFOLLOW) != 0 {
            if errno == ENOENT { return }
            throw FileMetadata.posix("无法检查预览临时目录", root)
        }
        try removeEntry("session", parent: descriptor, display: root.appendingPathComponent("session"))
    }
    private static func removeEntry(_ name: String, parent: Int32, display: URL) throws {
        var info = stat()
        guard fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else { throw FileMetadata.posix("无法检查临时项目", display) }
        if info.st_mode & S_IFMT == S_IFDIR {
            let descriptor = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            guard descriptor >= 0 else { throw FileMetadata.posix("无法打开临时目录", display) }
            defer { close(descriptor) }
            var opened = stat()
            guard fstat(descriptor, &opened) == 0, opened.st_uid == getuid(), opened.st_ino == info.st_ino, opened.st_dev == info.st_dev else {
                throw LockEngine.Failure.message("临时目录所有者或状态已变化，已停止清理。")
            }
            guard fchmod(descriptor, (opened.st_mode & 0o777) | 0o700) == 0 else { throw FileMetadata.posix("无法清理只读临时目录", display) }
            let duplicate = dup(descriptor)
            guard duplicate >= 0 else { throw FileMetadata.posix("无法读取临时目录", display) }
            guard let stream = fdopendir(duplicate) else { close(duplicate); throw FileMetadata.posix("无法枚举临时目录", display) }
            defer { closedir(stream) }
            while true {
                errno = 0
                guard let entry = readdir(stream) else {
                    if errno != 0 { throw FileMetadata.posix("读取临时目录失败", display) }
                    break
                }
                let child = withUnsafePointer(to: &entry.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) { String(cString: $0) }
                }
                if child != "." && child != ".." { try removeEntry(child, parent: descriptor, display: display.appendingPathComponent(child)) }
            }
            guard unlinkat(parent, name, AT_REMOVEDIR) == 0 else { throw FileMetadata.posix("无法移除临时目录", display) }
        } else {
            guard unlinkat(parent, name, 0) == 0 else { throw FileMetadata.posix("无法移除临时副本", display) }
        }
    }
    static func discard(_ item: Item) throws {
        guard try inspect(item.folder).canDiscard else { throw LockEngine.Failure.message("恢复状态已变化，未清理任何文件。") }
        try removeDisposableTree(item.folder)
        try LockEngine.synchronizeDirectory(item.folder.deletingLastPathComponent())
    }
}
