import Foundation
import Observation
import Darwin

/// A private, excluded-from-backup workspace. The lease prevents another process
/// from removing an active preview. Crashed sessions are removed on next acquisition.
final class PreviewWorkspace: @unchecked Sendable {
    let root: URL
    let folder: URL
    private var descriptor: Int32 = -1
    static var location: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EasyLock-PrivatePreview.noindex", isDirectory: true)
    }
    init(root: URL = PreviewWorkspace.location) throws {
        self.root = root
        folder = root.appendingPathComponent("session", isDirectory: true)
        if (try? root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            throw LockEngine.Failure.message("预览缓存目录不能是符号链接。")
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        var location = root
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try location.setResourceValues(values)
        let fd = Darwin.open(root.appendingPathComponent("lease").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw LockEngine.Failure.message("无法创建私密预览目录。") }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(fd)
            throw LockEngine.Failure.message("另一个预览尚未结束，请稍后重试。")
        }
        descriptor = fd
        do {
            try TransactionRecovery.removePreviewSession(in: root)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        } catch {
            Darwin.close(fd); descriptor = -1
            throw LockEngine.Failure.message("上次预览临时文件未能清理：\(folder.path)。\(error.localizedDescription)")
        }
    }
    func clean() throws {
        try TransactionRecovery.removePreviewSession(in: root)
    }
    deinit { if descriptor >= 0 { Darwin.close(descriptor) } }
}

@MainActor @Observable final class PrivatePreview {
    var item: LockedItem?
    var restored: URL?
    var busy = false
    var message: String?
    private var workspace: PreviewWorkspace?
    private var generation = UUID()
    private var control: OperationControl?
    private let workspaceRoot: URL
    var requested: Bool { item != nil }
    init(root: URL = PreviewWorkspace.location) {
        workspaceRoot = root
        // No plaintext is restored here; only leftovers from a terminated process are removed.
        do { let stale = try PreviewWorkspace(root: root); try stale.clean() }
        catch { message = "预览缓存检查：\(error.localizedDescription)" }
    }
    func begin(_ item: LockedItem) {
        guard !busy, self.item == nil else { return }
        self.item = item; restored = nil
    }
    func close() {
        generation = UUID(); control?.cancel(); item = nil; restored = nil
        if let workspace {
            do { try workspace.clean() }
            catch { message = "预览已关闭，但临时明文清理失败：\(workspace.folder.path)。\(error.localizedDescription)" }
            self.workspace = nil
        }
        // An in-flight worker retains its lease and cleans before becoming idle.
    }
    func open(password: String, recovery: String? = nil) async {
        guard !busy, let item else { return }
        busy = true; message = nil
        let token = generation
        let cancellation = OperationControl(); control = cancellation
        let source = item.resolve()
        let workspaceRoot = self.workspaceRoot
        do {
            let result = try await Task.detached { () throws -> (PreviewWorkspace, URL) in
                let access = source.startAccessingSecurityScopedResource()
                defer { if access { source.stopAccessingSecurityScopedResource() } }
                let workspace = try PreviewWorkspace(root: workspaceRoot)
                do {
                    try cancellation.check()
                    let result = try LockEngine.decryptCopy(source, into: workspace.folder, password: password, recoveryKey: recovery, control: cancellation)
                    try cancellation.check()
                    if let warning = result.warning { throw LockEngine.Failure.message(warning) }
                    return (workspace, result.url)
                } catch {
                    do { try workspace.clean() }
                    catch { throw LockEngine.Failure.message("预览临时明文清理失败：\(workspace.folder.path)。\(error.localizedDescription)") }
                    throw error
                }
            }.value
            if token == generation && self.item != nil { workspace = result.0; restored = result.1 }
            else { try result.0.clean() }
        } catch {
            if !(error is CancellationError) { message = error.localizedDescription }
        }
        control = nil; busy = false
    }
    func openWithTouchID() async {
        guard !busy, item != nil else { return }
        let token = generation
        busy = true
        do {
            let secret = try await TouchIDVault.unlock()
            busy = false
            guard token == generation, item != nil else { return }
            await open(password: secret)
        } catch {
            busy = false
            if token == generation && !TouchIDVault.isCancellation(error) { message = error.localizedDescription }
        }
    }
}
