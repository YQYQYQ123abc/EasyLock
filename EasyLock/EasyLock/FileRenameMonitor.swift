import Foundation
import Darwin

/// Monitors only registered, authorized files while EasyLock is running.
/// It does not intercept file opens in other applications.
@MainActor
final class FileRenameMonitor {
    private var source: DispatchSourceFileSystemObject?

    init?(url: URL, onRename: @escaping @MainActor (URL) -> Void) {
        let access = url.startAccessingSecurityScopedResource()
        let descriptor = open(url.path, O_EVTONLY | O_NOFOLLOW)
        guard descriptor >= 0 else {
            if access { url.stopAccessingSecurityScopedResource() }
            return nil
        }
        let watcher = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.rename], queue: .main)
        watcher.setEventHandler {
            var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            guard fcntl(descriptor, F_GETPATH, &buffer) == 0 else { return }
            let movedURL = URL(fileURLWithPath: String(cString: buffer)).standardizedFileURL
            Task { @MainActor in onRename(movedURL) }
        }
        watcher.setCancelHandler {
            close(descriptor)
            if access { url.stopAccessingSecurityScopedResource() }
        }
        source = watcher
        watcher.resume()
    }
    deinit { source?.cancel() }
}
