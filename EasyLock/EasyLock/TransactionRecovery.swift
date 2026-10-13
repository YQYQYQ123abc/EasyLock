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
        try FileManager.default.removeItem(at: item.folder)
        try LockEngine.synchronizeDirectory(current.source.deletingLastPathComponent())
    }
    static func discard(_ item: Item) throws {
        guard try inspect(item.folder).canDiscard else { throw LockEngine.Failure.message("恢复状态已变化，未清理任何文件。") }
        try FileManager.default.removeItem(at: item.folder)
        try LockEngine.synchronizeDirectory(item.folder.deletingLastPathComponent())
    }
}
