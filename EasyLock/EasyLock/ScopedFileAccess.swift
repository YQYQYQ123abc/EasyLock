import Foundation

/// Keeps a user-selected grant alive through confirmation and asynchronous processing.
final class ScopedFileAccess {
    private let active: [URL]
    init(_ urls: [URL]) { active = urls.filter { $0.startAccessingSecurityScopedResource() } }
    deinit { active.forEach { $0.stopAccessingSecurityScopedResource() } }
}
