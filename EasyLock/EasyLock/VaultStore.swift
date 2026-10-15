import SwiftUI
import AppKit
import ServiceManagement
import UniformTypeIdentifiers

struct BatchOutcome: Identifiable {
    let id = UUID()
    let name: String
    let status: String
    let detail: String
}

@MainActor @Observable
final class VaultStore {
    let panels = PanelCoordinator()
    let preview = PrivatePreview()
    private(set) var nativePanelActive = false
    var canPresentPicker: Bool {
        !preview.requested && !preview.busy && !busy && !loadingDrop && !panels.occupied && !nativePanelActive && pendingURLs.isEmpty && !showUnlock && !showResults && notice == nil
    }
    private func runNativePanel(_ panel: NSSavePanel) -> NSApplication.ModalResponse {
        guard !nativePanelActive else { return .abort }
        nativePanelActive = true
        defer { nativePanelActive = false }
        return panel.runModal()
    }
    var items: [LockedItem] = []
    var selection = Set<UUID>()
    var busy = false
    var progress = ""
    var operationUpdate: OperationControl.Update?
    var cancellationRequested = false
    var batchCompleted = 0
    var batchTotal = 0
    var outcomes: [BatchOutcome] = []
    var showResults = false
    var recoveries: [TransactionRecovery.Item] = []
    var recoveryErrors: [String] = []
    private var recoveryFolders: [String: Data] = [:]
    private var recoveryAccess: [String: Data] = [:]
    private var operationControl: OperationControl?
    private var batchID = UUID()
    private var phaseStarted = Date()
    var phaseEstimate: String {
        guard let update = operationUpdate, update.total > 0, update.completed > 0 else { return "" }
        let elapsed = Date().timeIntervalSince(phaseStarted)
        guard elapsed > 3, update.completed < update.total else { return "" }
        let seconds = elapsed * Double(update.total - update.completed) / Double(update.completed)
        return seconds < 60 ? "本阶段约剩余 \(max(1, Int(seconds))) 秒" : "本阶段约剩余 \(Int(ceil(seconds / 60))) 分钟"
    }
    var notice: String?
    var password = ""
    var configured = false
    var guestDecrypt = false
    var recoveryPublicKey: Data?
    var preflightText = ""
    var inspectingSources = false
    var preflightFailed = false
    var autoLockMinutes = UserDefaults.standard.object(forKey: "autoLockMinutes") as? Int ?? 5
    private let autoLock = AutoLockController()
    private var sessionEpoch = UUID()
    var sessionRevision = 0
    private var credential: PasswordCredential?
    private var credentialURL: URL { indexURL.deletingLastPathComponent().appendingPathComponent("credential.json") }
    private var recoveryPublicURL: URL { indexURL.deletingLastPathComponent().appendingPathComponent("recovery-public.key") }
    var pendingURLs: [URL] = []
    var showUnlock = false
    private(set) var loadingDrop = false
    var touchIDEnabled = UserDefaults.standard.bool(forKey: "touchIDEnabled")
    var touchIDAvailable = TouchIDVault.availability.available
    var touchIDReason = TouchIDVault.availability.reason
    var loginEnabled = SMAppService.mainApp.status == .enabled
    private let indexURL: URL
    private var directoryBookmarks: [String: Data] = UserDefaults.standard.dictionary(forKey: "directoryBookmarks") as? [String: Data] ?? [:]
    private var monitors: [UUID: FileRenameMonitor] = [:]

    init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("EasyLock", isDirectory: true)
        indexURL = folder.appendingPathComponent("library.json")
        configured = UserDefaults.standard.data(forKey: "passwordVerifier") != nil
        if FileManager.default.fileExists(atPath: credentialURL.path) {
            configured = true
            credential = try? JSONDecoder().decode(PasswordCredential.self, from: Data(contentsOf: credentialURL))
        } else if let salt = UserDefaults.standard.data(forKey: "passwordSalt"), let verifier = UserDefaults.standard.data(forKey: "passwordVerifier") {
            credential = PasswordCredential(salt: salt, verifier: verifier)
        }
        if let key = try? Data(contentsOf: recoveryPublicURL), key.count == 32 { recoveryPublicKey = key }
        autoLock.minutes = autoLockMinutes
        autoLock.onLock = { [weak self] in self?.lockSession() }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            if FileManager.default.fileExists(atPath: indexURL.path) {
                items = try JSONDecoder().decode([LockedItem].self, from: Data(contentsOf: indexURL))
            }
        } catch { notice = "无法读取文件记录。加密文件不受影响，可重新导入。\n\(error.localizedDescription)" }
        refreshMonitors()
        let recoveryIndex = folder.appendingPathComponent("recovery-folders.json")
        if FileManager.default.fileExists(atPath: recoveryIndex.path) {
            do { recoveryFolders = try JSONDecoder().decode([String: Data].self, from: Data(contentsOf: recoveryIndex)) }
            catch { recoveryErrors = ["无法读取恢复位置记录，请使用“检查恢复目录”手动选择原文件所在目录。"] }
        }
        // Include directories authorized by older versions; new tasks record exact parents.
        for (path, bookmark) in directoryBookmarks where recoveryFolders[path] == nil { recoveryFolders[path] = bookmark }
        WidgetSummary.publish(count: items.count)
        Task { await scanRecoveries() }
    }

    func authenticate(_ input: String, confirmation: String) async -> Bool {
        guard !busy, !input.isEmpty else { return false }
        if !configured && (input.count < 10 || input != confirmation) { notice = "请使用至少 10 个字符的密码，并确保两次输入一致。"; return false }
        busy = true; progress = "正在验证密码…"
        let epoch = sessionEpoch
        defer { busy = false }
        do {
            if configured {
                guard let credential else { throw LockEngine.Failure.message("本机密码设置无法读取，请使用独立解密入口恢复文件。") }
                guard try await Task.detached(operation: { try credential.matches(input) }).value else { throw LockEngine.Failure.message("密码不正确。") }
            } else {
                let new = try await Task.detached { try PasswordCredential.make(input) }.value
                guard epoch == sessionEpoch else { return false }
                try new.save(to: credentialURL)
                credential = new; configured = true
            }
            guard epoch == sessionEpoch else { return false }
            password = input; guestDecrypt = false; autoLock.touch()
            return true
        } catch { notice = error.localizedDescription; return false }
    }

    func changeMasterPassword(current: String, new: String, confirmation: String, recovery: String? = nil) async -> Bool {
        guard !busy, new.count >= 10, new == confirmation else { notice = "新密码至少 10 个字符，且两次输入必须一致。"; return false }
        busy = true; progress = "正在更新主密码…"
        let epoch = sessionEpoch
        defer { busy = false }
        do {
            if let recovery {
                guard let publicKey = recoveryPublicKey, try RecoveryKey.publicKey(recovery) == publicKey else { throw LockEngine.Failure.message("恢复密钥与本机设置不匹配。仍可用对应的密钥独立解密文件。") }
            } else {
                guard let credential, try await Task.detached(operation: { try credential.matches(current) }).value else { throw LockEngine.Failure.message("当前主密码不正确。") }
            }
            let updated = try await Task.detached { try PasswordCredential.make(new) }.value
            guard epoch == sessionEpoch else { return false }
            // Remove stale biometric credentials before changing the verifier.
            try await TouchIDVault.disable()
            touchIDEnabled = false; UserDefaults.standard.set(false, forKey: "touchIDEnabled")
            guard epoch == sessionEpoch else { return false }
            try updated.save(to: credentialURL)
            credential = updated; configured = true; password = new
            UserDefaults.standard.removeObject(forKey: "passwordVerifier")
            UserDefaults.standard.removeObject(forKey: "passwordSalt")
            guestDecrypt = false; autoLock.touch()
            notice = "主密码已更改，仅影响应用登录和以后加密的文件。已有密文仍需原密码或其对应恢复密钥；Touch ID 需重新启用。"
            return true
        } catch { notice = error.localizedDescription; return false }
    }

    func enableRecovery(_ key: String, confirmation: String) -> Bool {
        guard !password.isEmpty, !busy, key == confirmation.trimmingCharacters(in: .whitespacesAndNewlines) else { notice = "请重新输入已保存的完整恢复密钥进行确认。"; return false }
        do {
            let publicKey = try RecoveryKey.publicKey(key)
            try publicKey.write(to: recoveryPublicURL, options: .atomic)
            try LockEngine.synchronize(recoveryPublicURL)
            try LockEngine.synchronizeDirectory(recoveryPublicURL.deletingLastPathComponent())
            recoveryPublicKey = publicKey
            notice = "恢复密钥已启用，仅适用于之后新加密的文件。旧文件仍需原密码，或先解密再重新加密。"
            return true
        } catch { notice = error.localizedDescription; return false }
    }

    func exportRecovery(_ key: String) -> Bool {
        let panel = NSSavePanel()
        panel.title = "保存恢复密钥"
        panel.nameFieldStringValue = "EasyLock-Recovery-Key.txt"
        panel.message = "请保存在独立、安全的位置。持有此密钥的人可以解密对应文件；应用无法重新显示此密钥。"
        guard runNativePanel(panel) == .OK, let url = panel.url else { return false }
        do {
            let text = "EasyLock 恢复密钥（请妥善保管）\n\n\(key)\n\n仅适用于启用该密钥后加密的文件。请勿与密文一起分享。更换密钥不会更新旧文件，请保留旧密钥。\n"
            try Data(text.utf8).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return true
        } catch { notice = error.localizedDescription; return false }
    }

    func setAutoLockMinutes(_ value: Int) {
        autoLockMinutes = value; autoLock.minutes = value; autoLock.touch()
        UserDefaults.standard.set(value, forKey: "autoLockMinutes")
    }

    func inspectPendingSources() async {
        guard !inspectingSources else { return }
        let sources = pendingURLs
        inspectingSources = true; preflightText = "正在检查磁盘空间…"; preflightFailed = false
        defer { inspectingSources = false }
        do {
            let checks = try await Task.detached {
                try sources.map { url in
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    return (url.lastPathComponent, try SpacePreflight.inspect(url))
                }
            }.value
            guard pendingURLs == sources else { return }
            preflightText = checks.map { "\($0.0)：\($0.1.description)" }.joined(separator: "\n")
        } catch { preflightFailed = true; preflightText = error.localizedDescription }
    }

    func refreshTouchIDAvailability() {
        let status = TouchIDVault.availability
        touchIDAvailable = status.available
        touchIDReason = status.reason
    }

    func setTouchID(_ enabled: Bool) async {
        guard !busy else { return }
        busy = true; progress = enabled ? "正在启用 Touch ID…" : "正在关闭 Touch ID…"
        defer { busy = false; refreshTouchIDAvailability() }
        do {
            if enabled { try await TouchIDVault.enable(password: password) }
            else { try await TouchIDVault.disable() }
            touchIDEnabled = enabled
            UserDefaults.standard.set(enabled, forKey: "touchIDEnabled")
        } catch {
            if !TouchIDVault.isCancellation(error) { notice = error.localizedDescription }
        }
    }

    func unlockWithTouchID(decrypt: Bool = false, destination: URL? = nil) async {
        guard !busy, touchIDEnabled else { return }
        busy = true; progress = "等待 Touch ID 验证…"
        let epoch = sessionEpoch
        do {
            let secret = try await TouchIDVault.unlock()
            guard let credential, try await Task.detached(operation: { try credential.matches(secret) }).value else {
                throw LockEngine.Failure.message("Touch ID 对应的主密码已失效，请用主密码解锁后重新启用。")
            }
            guard epoch == sessionEpoch else { busy = false; return }
            autoLock.touch()
            password = secret
            busy = false
            if decrypt { await decryptSelected(with: secret, destination: destination) }
        } catch {
            busy = false
            if !TouchIDVault.isCancellation(error) { notice = error.localizedDescription }
        }
        refreshTouchIDAvailability()
    }

    func lockSession() {
        preview.close()
        PasswordAppSupport.clearOwnedClipboard()
        sessionEpoch = UUID(); sessionRevision += 1
        password = ""; selection.removeAll(); pendingURLs = []
        guestDecrypt = false; showUnlock = false; showResults = false; notice = nil
        if busy { operationControl?.cancel(); cancellationRequested = true }
    }

    func chooseSources(foldersOnly: Bool = false) {
        guard canPresentPicker else { return }
        let panel = NSOpenPanel()
        panel.title = foldersOnly ? "选择要加密的文件夹" : "选择要加密的文件"
        panel.prompt = foldersOnly ? "选择文件夹" : "选择文件"
        panel.message = foldersOnly ? "选中文件夹后点击“选择文件夹”，将加密整个目录。" : "支持多选。要添加整个目录，请使用“添加文件夹”。"
        panel.canChooseDirectories = foldersOnly
        panel.canChooseFiles = !foldersOnly
        panel.allowedContentTypes = foldersOnly ? [.folder] : [.item]
        panel.treatsFilePackagesAsDirectories = foldersOnly
        panel.allowsMultipleSelection = true
        if runNativePanel(panel) == .OK { prepareSources(panel.urls) }
    }

    func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        guard canPresentPicker else { return false }
        loadingDrop = true
        let accepted = FileDropReader.begin(providers) { [weak self] urls, failures in
            guard let self else { return }
            self.loadingDrop = false
            if !urls.isEmpty { self.prepareSources(urls) }
            if failures > 0 { self.notice = "有 \(failures) 个拖入项目无法读取。请从 Finder 拖入本地文件或文件夹。" }
        }
        if !accepted { loadingDrop = false }
        return accepted
    }

    func prepareSources(_ urls: [URL]) {
        guard !busy else { notice = "请等待当前操作完成。"; return }
        let encrypted = urls.filter { url in
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            return (try? LockEngine.isEncrypted(url)) == true
        }
        if !encrypted.isEmpty {
            receive(encrypted)
            if encrypted.count != urls.count {
                let ordinary = urls.filter { !encrypted.contains($0) }
                ExternalFileRequests.shared.enqueue(ordinary, kind: .finderSelection)
                notice = "已识别出加密文件，先处理解密。其余普通文件已排队，关闭当前解密窗口或完成任务后继续确认加密。"
            }
        } else { pendingURLs = urls }
    }

    /// Selecting a file alone does not authorize creating/renaming its siblings in App Sandbox.
    /// Ask for its containing folder, never for a different output location.
    private func authorizedFolder(for url: URL) -> URL? {
        let parent = url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
        for (_, data) in directoryBookmarks {
            var stale = false
            if let resolved = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &stale),
               !stale, (parent.path + "/").hasPrefix(resolved.resolvingSymlinksInPath().standardizedFileURL.path + "/") {
                return resolved
            }
        }
        let panel = NSOpenPanel()
        panel.title = "允许 EasyLock 原地替换文件"
        panel.message = "请允许访问“\(parent.lastPathComponent)”文件夹。加密与解密均在原位置完成，不另选保存位置。"
        panel.directoryURL = parent
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = false
        panel.prompt = "允许访问所在文件夹"
        guard runNativePanel(panel) == .OK, let selected = panel.url else { return nil }
        let selectedPath = selected.resolvingSymlinksInPath().standardizedFileURL.path
        guard (parent.path + "/").hasPrefix(selectedPath + "/") else {
            notice = "请选择文件所在的文件夹或其上级文件夹。"; return nil
        }
        let access = selected.startAccessingSecurityScopedResource()
        defer { if access { selected.stopAccessingSecurityScopedResource() } }
        do {
            directoryBookmarks[selectedPath] = try selected.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(directoryBookmarks, forKey: "directoryBookmarks")
        } catch { notice = "此次可继续操作，但无法记住所选文件夹的授权：\(error.localizedDescription)" }
        return selected
    }

    func cancelBatch() {
        cancellationRequested = true
        operationControl?.cancel()
    }

    private func rememberRecoveryParent(_ source: URL) throws {
        let parent = source.deletingLastPathComponent()
        recoveryFolders[parent.path] = try parent.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        let url = indexURL.deletingLastPathComponent().appendingPathComponent("recovery-folders.json")
        try JSONEncoder().encode(recoveryFolders).write(to: url, options: .atomic)
        try LockEngine.synchronize(url)
        try LockEngine.synchronizeDirectory(url.deletingLastPathComponent())
    }

    func scanRecoveries() async {
        guard !busy else { return }
        busy = true; progress = "检查未完成的任务…"
        defer { busy = false; refreshMonitors() }
        recoveryAccess = [:]
        var found: [TransactionRecovery.Item] = []
        var errors: [String] = []
        for (path, bookmark) in recoveryFolders {
            var stale = false
            do {
                let parent = try URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, bookmarkDataIsStale: &stale)
                let access = parent.startAccessingSecurityScopedResource()
                defer { if access { parent.stopAccessingSecurityScopedResource() } }
                recoveryAccess[parent.path] = bookmark
                let pending = try await Task.detached { try TransactionRecovery.scan(parent) }.value
                found += pending
                // Publication can finish just before a crash prevents library registration.
                let candidates = try await Task.detached {
                    try FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil).filter {
                        $0.pathExtension.lowercased() == "easylock" && (try? LockEngine.isEncrypted($0)) == true
                    }
                }.value
                for url in candidates where !items.contains(where: { $0.resolve().standardizedFileURL == url.standardizedFileURL }) {
                    let hasOriginal = LockEngine.exists(url.deletingPathExtension()) || pending.contains(where: { $0.result == url })
                    do {
                        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                        try register(url, size: size, originalRetained: hasOriginal, warning: hasOriginal ? "发现原文件或未完成的恢复任务，请检查是否仍有明文。" : nil)
                    } catch { errors.append("\(url.lastPathComponent)：已找到密文，但无法加入列表，请重新导入。") }
                }
                if stale { errors.append("\(path)：目录授权已过期，请重新选择该目录。") }
            } catch { errors.append("\(path)：暂时无法检查，可能未连接磁盘或需要重新授权。") }
        }
        recoveries = found
        recoveryErrors = errors
    }

    func chooseRecoveryFolder() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.title = "检查恢复目录"
        panel.message = "选择中断任务的原文件所在目录。只检查此目录中的 EasyLock 恢复记录。"
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        guard runNativePanel(panel) == .OK, let parent = panel.url else { return }
        let access = parent.startAccessingSecurityScopedResource()
        defer { if access { parent.stopAccessingSecurityScopedResource() } }
        do {
            try rememberRecoveryParent(parent.appendingPathComponent("placeholder"))
            Task { await scanRecoveries() }
        } catch { notice = error.localizedDescription }
    }

    func recover(_ item: TransactionRecovery.Item, discard: Bool = false) async {
        guard !busy else { return }
        let parent = item.folder.deletingLastPathComponent()
        guard let data = recoveryAccess[parent.path] ?? recoveryFolders[parent.path] else { notice = "请重新选择恢复目录。"; return }
        do {
            var stale = false
            let authorized = try URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &stale)
            let access = authorized.startAccessingSecurityScopedResource()
            defer { if access { authorized.stopAccessingSecurityScopedResource() } }
            busy = true; progress = "正在恢复任务…"
            do {
                try await Task.detached {
                    if discard { try TransactionRecovery.discard(item) }
                    else { try TransactionRecovery.recover(item) }
                }.value
                if !discard {
                    notice = "已将任务开始前的文件放回原位置。已发布的密文或解密文件均保留，请检查后决定保留哪些副本。"
                    // Any surviving ciphertext remains usable and visible after recovery.
                    for url in [item.source, item.result] where (try? LockEngine.isEncrypted(url)) == true {
                        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                        try register(url, size: size, originalRetained: true, warning: "中断任务已恢复，原文件或其他副本仍保留。")
                    }
                }
            } catch { notice = error.localizedDescription }
            busy = false
        } catch { notice = error.localizedDescription }
        await scanRecoveries()
        refreshMonitors()
    }

    func encryptPending() async {
        guard !busy, !password.isEmpty, !pendingURLs.isEmpty else { return }
        let sources = pendingURLs; pendingURLs = []
        let epoch = sessionEpoch
        busy = true
        await panels.closeAndWait()
        guard epoch == sessionEpoch else { busy = false; return }
        var accepted: [URL] = []
        for source in sources.sorted(by: { $0.path.count < $1.path.count }) {
            let path = source.standardizedFileURL.path
            if !accepted.contains(where: { path == $0.standardizedFileURL.path || path.hasPrefix($0.standardizedFileURL.path + "/") }) { accepted.append(source) }
        }
        await runBatch(accepted.map { ($0, $0.lastPathComponent, nil) }, secret: password, decrypt: false)
    }

    private func runBatch(_ sources: [(URL, String, UUID?)], secret: String, decrypt: Bool, destination: URL? = nil, recovery: String? = nil) async {
        busy = true; monitors.removeAll()
        outcomes = []; batchCompleted = 0; batchTotal = sources.count
        cancellationRequested = false; batchID = UUID()
        let token = batchID
        let publicKey = recoveryPublicKey
        let activeEpoch = sessionEpoch
        let control = OperationControl { [weak self] update in
            Task { @MainActor [weak self] in
                guard let self, self.busy, self.batchID == token else { return }
                if self.operationUpdate?.phase != update.phase { self.phaseStarted = Date() }
                self.operationUpdate = update
            }
        }
        operationControl = control
        for (index, source) in sources.enumerated() {
            let (url, name, itemID) = source
            if control.isCancelled {
                outcomes.append(BatchOutcome(name: name, status: "未处理", detail: "批量任务已取消，文件未修改。"))
                continue
            }
            operationUpdate = nil
            progress = "\(decrypt ? "解密" : "加密") \(index + 1)/\(sources.count) · \(name)"
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                guard let parent = destination ?? authorizedFolder(for: url) else { throw LockEngine.Failure.message("未授权所在文件夹，文件未修改。") }
                let parentAccess = parent.startAccessingSecurityScopedResource()
                defer { if parentAccess { parent.stopAccessingSecurityScopedResource() } }
                // This durable bookmark is saved before creating any transaction artifacts.
                try rememberRecoveryParent(destination?.appendingPathComponent("placeholder") ?? url)
                let unresolved = try await Task.detached { try TransactionRecovery.scan(url.deletingLastPathComponent()) }.value
                guard decrypt || !unresolved.contains(where: { $0.source == url || $0.result == url }) else {
                    throw LockEngine.Failure.message("此项目有尚未处理的恢复任务，请先到“安全与设置”中检查。")
                }
                try control.check()
                let result = try await Task.detached {
                    if decrypt {
                        if let destination { return try LockEngine.decryptCopy(url, into: destination, password: secret, recoveryKey: recovery, control: control) }
                        return try LockEngine.decryptInPlace(url, password: secret, recoveryKey: recovery, control: control)
                    }
                    return try LockEngine.encryptInPlace(url, password: secret, recoveryPublicKey: publicKey, control: control)
                }.value
                var detail = result.warning ?? (destination != nil ? "已恢复到所选目录，原密文保留。" : decrypt ? "已恢复原名称、内容与保存的属性。" : "已在原位置加密。")
                var warning = result.warning != nil
                do {
                    if decrypt && destination == nil {
                        items.removeAll { $0.id == itemID }
                        if let itemID { selection.remove(itemID) }
                        try save()
                    } else if decrypt, let itemID, let index = items.firstIndex(where: { $0.id == itemID }) {
                        items[index].originalRetained = true
                        items[index].warning = "已恢复明文副本：\(result.url.path)。当前列表保留的是密文。"
                        try save()
                    } else if !decrypt {
                        let size = (try? result.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                        try register(result.url, size: size, originalRetained: result.warning != nil, inPlace: true, warning: result.warning)
                    }
                } catch { detail += " 文件已保存，但列表更新失败：\(result.url.path)"; warning = true }
                outcomes.append(BatchOutcome(name: name, status: warning ? "需要处理" : "成功", detail: detail))
            } catch is CancellationError {
                outcomes.append(BatchOutcome(name: name, status: "已取消", detail: "已中止并保留任务开始前的文件。"))
            } catch {
                outcomes.append(BatchOutcome(name: name, status: "失败", detail: error.localizedDescription))
            }
            batchCompleted = index + 1
        }
        batchID = UUID(); operationControl = nil; operationUpdate = nil
        busy = false; cancellationRequested = false; batchTotal = 0
        refreshMonitors()
        await scanRecoveries()
        showResults = activeEpoch == sessionEpoch
    }

    func register(_ url: URL, size: Int, originalRetained: Bool, inPlace: Bool? = nil, warning: String? = nil) throws {
        if let index = items.firstIndex(where: { $0.resolve().standardizedFileURL.path == url.standardizedFileURL.path }) {
            if let warning {
                items[index].warning = warning
                items[index].originalRetained = originalRetained
                try save()
            }
            return
        }
        let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        let name = url.pathExtension.lowercased() == "easylock" ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent
        items.insert(LockedItem(name: name, path: url.path, bookmark: bookmark, date: Date(), size: size, originalRetained: originalRetained, inPlace: inPlace, warning: warning), at: 0)
        try save()
    }

    func importFiles() {
        guard canPresentPicker else { return }
        let panel = NSOpenPanel()
        panel.title = "导入 EasyLock 加密文件"
        panel.message = "可选择任何后缀的文件。EasyLock 按文件内容识别密文，修改后缀不能绕过密码。"
        panel.allowsMultipleSelection = true
        if runNativePanel(panel) == .OK { receive(panel.urls) }
    }

    func receive(_ urls: [URL]) {
        guard !busy else { notice = "请等待当前任务完成后再导入。"; return }
        var imported = Set<UUID>()
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                guard try LockEngine.isEncrypted(url) else { throw LockEngine.Failure.message("文件内容不是 EasyLock 密文。仅改成 .easylock 后缀并不会加密。") }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                try register(url, size: size, originalRetained: false)
                if let item = items.first(where: { $0.resolve().standardizedFileURL.path == url.standardizedFileURL.path }) { imported.insert(item.id) }
            } catch { notice = error.localizedDescription }
        }
        selection = imported
        if !imported.isEmpty {
            if password.isEmpty { guestDecrypt = true; autoLock.touch() }
            showUnlock = true
        }
        refreshMonitors()
    }

    func decryptSelected(with secret: String, destination: URL? = nil, recovery: String? = nil) async {
        guard !busy, (!secret.isEmpty || recovery != nil), !selection.isEmpty else { return }
        showUnlock = false
        let selected = items.filter { selection.contains($0.id) }
        let epoch = sessionEpoch
        busy = true
        await panels.closeAndWait()
        guard epoch == sessionEpoch else { busy = false; return }
        await runBatch(selected.map { ($0.resolve(), $0.name, $0.id) }, secret: secret, decrypt: true, destination: destination, recovery: recovery)
    }

    func chooseRestoreFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "选择恢复位置（保留原密文）"
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.prompt = "恢复到此目录"
        return runNativePanel(panel) == .OK ? panel.url : nil
    }

    func independentDecrypt() {
        guard !busy else { return }
        guestDecrypt = true
        importFiles()
    }

    func refreshMonitors() {
        guard !busy else { return }
        monitors.removeAll()
        for item in items {
            monitors[item.id] = FileRenameMonitor(url: item.resolve()) { [weak self] url in
                self?.fileRenamed(id: item.id, to: url)
            }
        }
    }

    private func fileRenamed(id: UUID, to url: URL) {
        guard !busy, let index = items.firstIndex(where: { $0.id == id }),
              items[index].path != url.path else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            guard try LockEngine.isEncrypted(url) else { return }
            items[index].path = url.path
            items[index].bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            try save()
            if url.pathExtension.lowercased() != "easylock" {
                selection = [id]
                showUnlock = true
                notice = "“\(url.lastPathComponent)”仍是加密文件。修改后缀只会改变系统选择的打开方式，不会恢复内容，请在 EasyLock 中解密。"
                NSApp.activate(ignoringOtherApps: true)
            }
        } catch { notice = "文件已改名，但更新访问记录失败。请重新导入：\(error.localizedDescription)" }
    }

    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            if enabled && !loginEnabled { notice = "请在系统设置的登录项中允许 EasyLock 启动。" }
        } catch { notice = error.localizedDescription; loginEnabled = SMAppService.mainApp.status == .enabled }
    }

    func save() throws { try JSONEncoder().encode(items).write(to: indexURL, options: .atomic); WidgetSummary.publish(count: items.count) }
}
