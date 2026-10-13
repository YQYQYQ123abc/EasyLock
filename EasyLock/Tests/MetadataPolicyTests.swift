import Foundation
import Darwin

@main
struct MetadataPolicyTests {
    static func withSystemRecords(_ metadata: FileMetadata) -> FileMetadata {
        var attributes = metadata.attributes
        attributes["com.apple.macl"] = Data([1, 2, 3])
        attributes["com.apple.provenance"] = Data([4, 5, 6])
        return FileMetadata(permissions: metadata.permissions, owner: metadata.owner, group: metadata.group, flags: metadata.flags,
                            created: metadata.created, modified: metadata.modified, accessed: metadata.accessed, attributes: attributes, acl: metadata.acl)
    }
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("easylock-metadata-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let folder = root.appendingPathComponent("测试文件夹")
        try fm.createDirectory(at: folder.appendingPathComponent("子文件夹"), withIntermediateDirectories: true)
        let document = folder.appendingPathComponent("子文件夹/就业推荐表.docx")
        let bytes = Data([0x50, 0x4b, 0x03, 0x04, 0, 255, 127])
        try bytes.write(to: document)
        let tags = try PropertyListSerialization.data(fromPropertyList: ["重要\n6"], format: .binary, options: 0)
        try set(document, "com.apple.metadata:_kMDItemUserTags", tags)
        try set(document, "com.apple.ResourceFork", Data("resource fork".utf8))
        try set(document, "com.apple.quarantine", Data("0081;65a00000;EasyLockTests;".utf8))
        let original = try LockEngine.snapshot(folder)
        let entries = original.entries.map { entry in
            LockEngine.Entry(path: entry.path, directory: entry.directory, contents: entry.contents, metadata: withSystemRecords(entry.metadata!))
        }
        let archive = LockEngine.Archive(name: original.name, directory: true, entries: entries, metadata: withSystemRecords(original.metadata!))
        let destination = root.appendingPathComponent("restored")
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        let restored = try LockEngine.restore(archive, into: destination)
        try LockEngine.verify(archive, at: restored)
        let restoredDocument = restored.appendingPathComponent("子文件夹/就业推荐表.docx")
        let restoredBytes = try Data(contentsOf: restoredDocument)
        precondition(restoredBytes == bytes)
        let restoredMetadata = try FileMetadata.capture(restoredDocument)
        let sourceMetadata = try FileMetadata.capture(document)
        precondition(sourceMetadata.portableAttributes == restoredMetadata.portableAttributes)
        precondition(restoredMetadata.attributes["com.apple.quarantine"] != nil)
        precondition(restoredMetadata.attributes["com.apple.ResourceFork"] != nil)
        precondition(restoredMetadata.attributes["com.apple.metadata:_kMDItemUserTags"] == tags)
        precondition(!FileMetadata.systemManagedAttributes.contains("com.apple.quarantine"))
        precondition(!FileMetadata.systemManagedAttributes.contains("com.apple.ResourceFork"))
        precondition(!FileMetadata.systemManagedAttributes.contains("com.apple.FinderInfo"))
        print("PASS: host-managed records do not block nested directory restore; document bytes, quarantine, tags and resource fork remain intact")
    }
    static func set(_ url: URL, _ name: String, _ value: Data) throws {
        let result = value.withUnsafeBytes { setxattr(url.path, name, $0.baseAddress, value.count, 0, XATTR_NOFOLLOW) }
        guard result == 0 else { throw FileMetadata.posix("test xattr", url) }
    }
}
