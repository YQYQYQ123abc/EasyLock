import Foundation
@main struct BrowserNavigationTests {
    @MainActor static func main() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("EasyLock-navigation-" + UUID().uuidString)
        let a = root.appendingPathComponent("A"), b = root.appendingPathComponent("B")
        try fm.createDirectory(at: a, withIntermediateDirectories: true)
        try fm.createDirectory(at: b, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("file.txt")
        try Data("unchanged".utf8).write(to: file)
        let domain = "EasyLock-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain); try? fm.removeItem(at: root) }
        let browser = LocalFilesBrowser(defaults: defaults)
        await browser.open(root)
        precondition(browser.entries.count == 3)
        let selected = browser.entries.first { $0.url.lastPathComponent == "file.txt" }!.id
        browser.selection = [selected]
        await browser.refresh()
        precondition(browser.selection == [selected])
        await browser.load(a)
        precondition(browser.canGoBack)
        await browser.back()
        precondition(browser.directory?.lastPathComponent == root.lastPathComponent && browser.canGoForward)
        await browser.forward()
        precondition(browser.directory?.lastPathComponent == "A")
        await browser.back()
        await browser.load(b)
        precondition(!browser.canGoForward)
        await browser.load(root.appendingPathComponent("missing"))
        precondition(browser.directory?.lastPathComponent == "B" && browser.message != nil)
        let savedBookmark = defaults.data(forKey: "localBrowserFolderBookmark")
        await browser.open(root.appendingPathComponent("missing-root"))
        precondition(browser.root == root.standardizedFileURL && browser.directory?.lastPathComponent == "B")
        precondition(defaults.data(forKey: "localBrowserFolderBookmark") == savedBookmark && browser.canGoBack)
        await browser.refresh()
        precondition(browser.message == nil && browser.directory?.lastPathComponent == "B")
        await browser.back()
        precondition(browser.directory?.lastPathComponent == root.lastPathComponent)
        browser.close()
        await browser.open(root.appendingPathComponent("missing-first-root"))
        precondition(browser.root == nil && browser.directory == nil && browser.entries.isEmpty && !browser.loading)
        browser.close()
        precondition(browser.entries.isEmpty && !browser.canGoBack && !browser.canGoForward && browser.message == nil)
        print("PASS: refresh preserves selection; back/forward; navigation truncates forward history; failed navigation retains directory; close clears state")
    }
}
