import Foundation
@main struct LocalFilesBrowserTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("EasyLock-browser-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("private original".utf8).write(to: root.appendingPathComponent("普通文件.txt"))
        try Data("EASYLOCK\u{0}04".utf8).write(to: root.appendingPathComponent("改过后缀.bin"))
        try Data("not encrypted".utf8).write(to: root.appendingPathComponent("误改.easylock"))
        try Data("hidden".utf8).write(to: root.appendingPathComponent(".hidden"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("目录"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("链接"), withDestinationURL: root.appendingPathComponent("普通文件.txt"))
        let entries = try LocalFilesBrowser.readDirectory(root)
        precondition(entries.count == 5)
        precondition(entries.first?.folder == true)
        precondition(entries.first { $0.url.lastPathComponent == "普通文件.txt" }?.state == .plain)
        precondition(entries.first { $0.url.lastPathComponent == "改过后缀.bin" }?.state == .encrypted)
        precondition(entries.first { $0.url.lastPathComponent == "误改.easylock" }?.state == .unavailable)
        precondition(entries.first { $0.url.lastPathComponent == "链接" }?.state == .unavailable)
        let original = try Data(contentsOf: root.appendingPathComponent("普通文件.txt"))
        precondition(original == Data("private original".utf8))
        let password = "Browser-test-password-2026!"
        for name in ["普通文件.txt", "目录"] {
            let source = root.appendingPathComponent(name)
            if name == "目录" { try original.write(to: source.appendingPathComponent("内容.txt")) }
            let encrypted = try LockEngine.encryptInPlace(source, password: password)
            let afterEncryption = try LocalFilesBrowser.readDirectory(root)
            precondition(!afterEncryption.contains { $0.url.lastPathComponent == source.lastPathComponent })
            precondition(afterEncryption.first { $0.url.lastPathComponent == encrypted.url.lastPathComponent }?.state == .encrypted)
            let restored = try LockEngine.decryptInPlace(encrypted.url, password: password)
            let afterDecryption = try LocalFilesBrowser.readDirectory(root)
            precondition(afterDecryption.first { $0.url.lastPathComponent == restored.url.lastPathComponent }?.state == .plain)
            precondition(!afterDecryption.contains { $0.url.lastPathComponent == encrypted.url.lastPathComponent })
            let contentURL = name == "目录" ? restored.url.appendingPathComponent("内容.txt") : restored.url
            let restoredBytes = try Data(contentsOf: contentURL)
            precondition(restoredBytes == original)
        }
        print("PASS: file/folder encryption-decryption listing refresh and byte preservation")
        print("PASS: local listing, folders first, encrypted header despite renamed suffix, invalid suffix, symlink blocking, hidden files and unchanged originals")
    }
}
