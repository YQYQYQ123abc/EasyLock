import AppKit

@MainActor
final class FinderService: NSObject, NSApplicationDelegate {
    var openMainWindow: (() -> Void)?

    func applicationWillTerminate(_ notification: Notification) { PasswordAppSupport.clearOwnedClipboard() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let files = urls.filter(\.isFileURL)
        ExternalFileRequests.shared.enqueue(files, kind: .openEncrypted)
        for url in urls where !url.isFileURL { ExternalFileRequests.shared.enqueueShortcut(url) }
        showMainWindow()
    }

    private func showMainWindow() {
        if let window = NSApp.windows.first(where: { $0.canBecomeMain && $0.sheetParent == nil }) {
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
        } else { openMainWindow?() }
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func encryptWithEasyLock(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty else {
            error.pointee = "请选择文件或文件夹。"
            return
        }
        ExternalFileRequests.shared.enqueue(urls, kind: .finderSelection)
        showMainWindow()
    }
}
