import Foundation
import Observation

/// Retains Finder grants until the UI accepts a request. Nothing is written to disk.
@MainActor @Observable
final class ExternalFileRequests {
    enum Kind { case openEncrypted, finderSelection }
    struct Request {
        let kind: Kind
        let urls: [URL]
        fileprivate let scoped: [URL]
    }
    static let shared = ExternalFileRequests()
    private var requests: [Request] = []
    private(set) var revision = 0
    private(set) var shortcut: String?
    func enqueueShortcut(_ url: URL) {
        guard url.scheme == "easylock", let route = url.host,
              ["library", "settings", "add-file", "add-folder"].contains(route),
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.port == nil, url.path.isEmpty || url.path == "/" else { return }
        shortcut = route; revision &+= 1
    }
    func consumeShortcut() -> String? {
        let value = shortcut; shortcut = nil
        if value != nil { revision &+= 1 }
        return value
    }
    var count: Int { requests.count }

    func enqueue(_ urls: [URL], kind: Kind) {
        var seen = Set<URL>()
        let local = urls.filter { $0.isFileURL && seen.insert($0.standardizedFileURL).inserted }
        guard !local.isEmpty else { return }
        // Coalesce repeated deliveries while the same request is still waiting.
        guard !requests.contains(where: { $0.kind == kind && $0.urls == local }) else { return }
        let scoped = local.filter { $0.startAccessingSecurityScopedResource() }
        requests.append(Request(kind: kind, urls: local, scoped: scoped))
        revision &+= 1
    }

    func consumeNext(_ handle: (Request) -> Void) {
        guard !requests.isEmpty else { return }
        let request = requests.removeFirst()
        defer {
            request.scoped.forEach { $0.stopAccessingSecurityScopedResource() }
            revision &+= 1
        }
        handle(request)
    }
}
