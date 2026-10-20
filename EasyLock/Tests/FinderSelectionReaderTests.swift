import AppKit
@main struct FinderSelectionReaderTests {
    @MainActor static func main() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("EasyLock-service-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("带 空格的文件.txt")
        let folder = root.appendingPathComponent("文件夹", isDirectory: true)
        try Data("service fixture".utf8).write(to: file)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        board.writeObjects([file as NSURL, folder as NSURL])
        precondition(FinderSelectionReader.urls(from: board).map(\.path) == [file.path, folder.path])
        board.clearContents()
        board.setPropertyList([file.path, folder.path, file.path, "relative.txt"], forType: FinderSelectionReader.filenamesType)
        precondition(FinderSelectionReader.urls(from: board).map(\.path) == [file.path, folder.path])
        board.clearContents()
        board.writeObjects([URL(string: "https://example.com/test")! as NSURL])
        precondition(FinderSelectionReader.urls(from: board).isEmpty)
        board.clearContents()
        board.setString("/tmp/not-a-file-selection.txt", forType: .string)
        precondition(FinderSelectionReader.urls(from: board).isEmpty)
        print("PASS: Finder modern file URLs, legacy filenames, folders, Unicode, duplicate filtering and rejection of ordinary text/web URLs")
    }
}
