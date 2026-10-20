import SwiftUI
import AppKit

struct LocalFileEntry: Identifiable, Sendable {
    enum State: Sendable { case plain, encrypted, unavailable }
    let url: URL
    let folder: Bool
    let size: Int
    let state: State
    let reason: String?
    var id: URL { url }
}

@MainActor @Observable final class LocalFilesBrowser {
    private(set) var root: URL?
    private(set) var directory: URL?
    private(set) var entries: [LocalFileEntry] = []
    private(set) var loading = false
    var message: String?
    var selection = Set<URL>()
    private var access: ScopedFileAccess?
    private var revision = UUID()
    private var history: [URL] = []
    private var historyIndex = -1
    var canGoBack: Bool { historyIndex > 0 && !loading }
    var canGoForward: Bool { historyIndex + 1 < history.count && !loading }
    func back() async { await navigateHistory(-1) }
    func forward() async { await navigateHistory(1) }
    private func navigateHistory(_ offset: Int) async {
        let index = historyIndex + offset
        guard !loading, history.indices.contains(index) else { return }
        await load(history[index], recordHistory: false)
        if message == nil { historyIndex = index }
    }
    private let bookmarkKey = "localBrowserFolderBookmark"
    @ObservationIgnored private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func restore() async {
        guard root == nil, let data = defaults.data(forKey: bookmarkKey) else { return }
        var stale = false
        do {
            let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &stale)
            guard !stale else { message = "上次的目录授权已过期，请重新选择文件夹。"; return }
            await open(url)
        } catch { message = "无法恢复目录授权，请重新选择文件夹。" }
    }
    func open(_ url: URL) async {
        let candidate = url.standardizedFileURL
        let candidateAccess = ScopedFileAccess([candidate])
        defer { withExtendedLifetime(candidateAccess) {} }
        let token = UUID(); revision = token
        loading = true; message = nil
        do {
            let result = try await Task.detached { try Self.readDirectory(candidate) }.value
            guard revision == token else { return }
            // Commit the authorization, list, history and bookmark together only after a successful read.
            access = candidateAccess; root = candidate; directory = candidate
            entries = result; selection = []; history = [candidate]; historyIndex = 0
            do {
                let data = try candidate.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                defaults.set(data, forKey: bookmarkKey)
            } catch {
                defaults.removeObject(forKey: bookmarkKey)
                message = "此次可浏览，但下次启动需要重新授权。"
            }
        } catch {
            guard revision == token else { return }
            message = "无法读取“\(candidate.lastPathComponent)”：\(error.localizedDescription)"
        }
        if revision == token { loading = false }
    }

    func close() {
        revision = UUID(); root = nil; directory = nil; entries = []; selection = []
        access = nil; loading = false; message = nil; history = []; historyIndex = -1
    }
    func forget() { close(); defaults.removeObject(forKey: bookmarkKey) }
    func refresh() async { if let directory { await load(directory) } }
    func up() async {
        guard let directory, directory != root else { return }
        await load(directory.deletingLastPathComponent())
    }
    func load(_ url: URL, recordHistory: Bool = true) async {
        guard let root else { return }
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
        guard rootPath == "/" || path == rootPath || path.hasPrefix(rootPath + "/") else { return }
        let token = UUID(); revision = token
        let retainedAccess = access
        defer { withExtendedLifetime(retainedAccess) {} }
        let previousDirectory = directory
        let previousSelection = selection
        let sameDirectory = directory?.standardizedFileURL.path == url.standardizedFileURL.path
        loading = true; message = nil
        if !sameDirectory { selection = [] }

        do {
            let result = try await Task.detached { try Self.readDirectory(url) }.value
            guard revision == token else { return }
            entries = result; directory = url
            selection = sameDirectory ? previousSelection.intersection(Set(result.map(\.id))) : []
            if recordHistory && (history.indices.contains(historyIndex) ? history[historyIndex].standardizedFileURL.path : nil) != url.standardizedFileURL.path {
                history = Array(history.prefix(historyIndex + 1))
                if history.last?.standardizedFileURL.path != url.standardizedFileURL.path { history.append(url) }
                historyIndex = history.count - 1
            }
        } catch {
            guard revision == token else { return }
            directory = previousDirectory
            if !sameDirectory { selection = previousSelection }
            message = "无法读取“\(url.lastPathComponent)”：\(error.localizedDescription)"
        }
        if revision == token { loading = false }
    }
    nonisolated static func readDirectory(_ url: URL) throws -> [LocalFileEntry] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isPackageKey, .fileSizeKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        let children = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
        guard children.count <= 5000 else { throw NSError(domain: "EasyLock.LocalFiles", code: 1, userInfo: [NSLocalizedDescriptionKey: "此目录超过 5,000 项，请选择更具体的子文件夹。"]) }
        return children.map { child in
            do {
                let values = try child.resourceValues(forKeys: keys)
                let folder = values.isDirectory == true
                let reason: String?
                if values.isSymbolicLink == true { reason = "暂不支持符号链接" }
                else if values.isPackage == true { reason = "暂不支持应用程序或文件包" }
                else if !folder && values.isRegularFile != true { reason = "暂不支持此类型" }
                else if values.isUbiquitousItem == true && values.ubiquitousItemDownloadingStatus == .notDownloaded { reason = "请先在 Finder 下载到本机" }
                else { reason = nil }
                if let reason { return LocalFileEntry(url: child, folder: folder, size: values.fileSize ?? 0, state: .unavailable, reason: reason) }
                let encrypted = try (!folder && LockEngine.isEncrypted(child))
                if !encrypted && child.pathExtension.lowercased() == "easylock" {
                    return LocalFileEntry(url: child, folder: folder, size: values.fileSize ?? 0, state: .unavailable, reason: "无法识别此密文，请导入加密文件检查")
                }
                return LocalFileEntry(url: child, folder: folder, size: values.fileSize ?? 0, state: encrypted ? .encrypted : .plain, reason: nil)
            } catch { return LocalFileEntry(url: child, folder: false, size: 0, state: .unavailable, reason: "无读取权限或文件已移动") }
        }.sorted {
            if $0.folder != $1.folder { return $0.folder }
            return $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
        }
    }
}
