import Foundation

struct LockedItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var path: String
    var bookmark: Data?
    let date: Date
    let size: Int
    var originalRetained: Bool
    var inPlace: Bool? = nil
    var warning: String? = nil
    var url: URL { URL(fileURLWithPath: path) }
    func resolve() -> URL {
        guard let bookmark else { return url }
        var stale = false
        return (try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, bookmarkDataIsStale: &stale)) ?? url
    }
}

