import Foundation
import UniformTypeIdentifiers

@main
struct FileDropTests {
    @MainActor
    static func load(_ providers: [NSItemProvider]) async -> ([URL], Int) {
        await withCheckedContinuation { continuation in
            if !FileDropReader.begin(providers, completion: { continuation.resume(returning: ($0, $1)) }) {
                continuation.resume(returning: ([], 0))
            }
        }
    }
    @MainActor
    static func main() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("easylock-drop-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let file = root.appendingPathComponent("附件 空格.docx")
        try Data("sample".utf8).write(to: file)
        let inputs = [file, root, file]
        let providers = inputs.map { NSItemProvider(object: $0 as NSURL) }
        let (urls, failures) = await load(providers)
        precondition(failures == 0 && urls.count == 2)
        precondition(urls[0].standardizedFileURL == file.standardizedFileURL)
        precondition(urls[1].standardizedFileURL == root.standardizedFileURL)
        let invalid = NSItemProvider()
        invalid.registerDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier, visibility: .all) { callback in
            callback(Data("https://example.com/not-local".utf8), nil)
            return nil
        }
        let (invalidURLs, invalidFailures) = await load([invalid])
        precondition(invalidURLs.isEmpty && invalidFailures == 1)
        let (unsupported, _) = await load([NSItemProvider(object: "plain text" as NSString)])
        precondition(unsupported.isEmpty)
        print("PASS: file/folder drops preserve original URLs, Unicode/spaces, order, deduplication; remote URLs and plain text rejected")
    }
}
