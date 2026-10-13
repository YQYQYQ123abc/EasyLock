import Foundation
import CryptoKit
import CommonCrypto
import Security
import Darwin

/// Authenticated, versioned archives. Bounded reads include resource forks and metadata.
enum LockEngine {
    static let maximumBytes = 64 * 1024 * 1024
    static let maximumEntries = 10_000
    private static let magic = Data("EASYLOCK\u{0}02".utf8)
    private static let legacyMagic = Data("EASYLOCK\u{0}01".utf8)

    struct Entry: Codable {
        let path: String
        let directory: Bool
        let contents: Data?
        var metadata: FileMetadata? = nil
    }
    struct Archive: Codable {
        let name: String
        let directory: Bool
        let entries: [Entry]
        var metadata: FileMetadata? = nil
    }
    enum Failure: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
    }

    static func random(_ count: Int) throws -> Data {
        var data = Data(count: count)
        let result = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        guard result == errSecSuccess else { throw Failure.message("无法生成安全随机数。") }
        return data
    }

    static func derive(_ password: String, salt: Data) throws -> Data {
        let bytes = Array(password.utf8)
        var output = Data(count: 32)
        let status = output.withUnsafeMutableBytes { out in
            salt.withUnsafeBytes { saltBytes in
                bytes.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), passwordBytes.baseAddress!.assumingMemoryBound(to: Int8.self), bytes.count, saltBytes.baseAddress!.assumingMemoryBound(to: UInt8.self), salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 600_000, out.baseAddress!.assumingMemoryBound(to: UInt8.self), 32)
                }
            }
        }
        guard status == kCCSuccess else { throw Failure.message("密码密钥生成失败。") }
        return output
    }

    static func snapshot(_ source: URL, originalName: String? = nil) throws -> Archive {
        let fm = FileManager.default
        let rootMetadata = try FileMetadata.capture(source)
        let root = try FileMetadata.status(source)
        let isDirectory = root.st_mode & S_IFMT == S_IFDIR
        let canonical = source.resolvingSymlinksInPath().standardizedFileURL
        var urls = [canonical]
        if isDirectory {
            var enumerationError: Error?
            guard let walker = fm.enumerator(at: canonical, includingPropertiesForKeys: nil, options: [], errorHandler: { _, error in enumerationError = error; return false }) else { throw Failure.message("无法读取文件夹。") }
            urls = []
            for case let url as URL in walker {
                urls.append(url)
                guard urls.count <= maximumEntries else { throw Failure.message("最多支持 10,000 个目录条目。") }
            }
            if let enumerationError { throw enumerationError }
        }
        var total = rootMetadata.attributes.values.reduce(0) { $0 + $1.count }
        let name = originalName ?? source.lastPathComponent
        var entries: [Entry] = []
        for url in urls.sorted(by: { $0.path < $1.path }) {
            let metadata = isDirectory ? try FileMetadata.capture(url) : rootMetadata
            let info = try FileMetadata.status(url)
            let directory = info.st_mode & S_IFMT == S_IFDIR
            let path = isDirectory ? url.standardizedFileURL.pathComponents.dropFirst(canonical.pathComponents.count).joined(separator: "/") : name
            if isDirectory { total += metadata.attributes.values.reduce(0) { $0 + $1.count } }
            guard total <= maximumBytes else { throw Failure.message("文件与扩展属性总大小超过 64 MB。") }
            var contents: Data?
            if !directory {
                contents = try boundedRead(url, limit: maximumBytes - total)
                total += contents!.count
            }
            entries.append(Entry(path: path, directory: directory, contents: contents, metadata: metadata))
        }
        let archive = Archive(name: name, directory: isDirectory, entries: entries, metadata: rootMetadata)
        try validate(archive)
        return archive
    }

    static func seal(_ source: URL, password: String) throws -> Data {
        try seal(snapshot(source), password: password)
    }

    static func seal(_ archive: Archive, password: String) throws -> Data {
        guard !password.isEmpty else { throw Failure.message("请输入加密密码。") }
        try validate(archive)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let plain = try encoder.encode(archive)
        guard plain.count <= maximumBytes + 8 * 1024 * 1024 else { throw Failure.message("目录元数据过大。") }
        let salt = try random(16)
        let header = magic + salt
        let key = SymmetricKey(data: try derive(password, salt: salt))
        let box = try AES.GCM.seal(plain, using: key, authenticating: header)
        guard let combined = box.combined else { throw Failure.message("加密失败。") }
        return header + combined
    }

    static func isEncrypted(_ url: URL) throws -> Bool {
        let info = try FileMetadata.status(url)
        guard info.st_mode & S_IFMT == S_IFREG else { return false }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let header = try handle.read(upToCount: magic.count) ?? Data()
        return header == magic || header == legacyMagic || header == StreamArchive.magic || header == RecoveryKey.magic
    }

    static func open(_ data: Data, password: String) throws -> Archive {
        guard !password.isEmpty, data.count > magic.count + 16 + 28,
              data.count <= maximumBytes + 9 * 1024 * 1024,
              (data.starts(with: magic) || data.starts(with: legacyMagic)) else { throw Failure.message("不是有效的 EasyLock 文件，或版本不受支持。") }
        let headerSize = magic.count + 16
        let header = data.prefix(headerSize)
        let salt = Data(data[magic.count..<headerSize])
        let key = SymmetricKey(data: try derive(password, salt: salt))
        let plain: Data
        do {
            plain = try AES.GCM.open(AES.GCM.SealedBox(combined: data.dropFirst(headerSize)), using: key, authenticating: header)
        } catch { throw Failure.message("密码不正确，或加密文件已损坏。原文件未被修改。") }
        let archive = try PropertyListDecoder().decode(Archive.self, from: plain)
        try validate(archive)
        if data.starts(with: magic) {
            guard archive.metadata != nil, archive.entries.allSatisfy({ $0.metadata != nil }) else { throw Failure.message("加密文件的元数据不完整。") }
        }
        return archive
    }

    static func saveEncrypted(_ data: Data, to output: URL, password: String) throws {
        let fm = FileManager.default
        let staging = output.deletingLastPathComponent().appendingPathComponent(".easylock-" + UUID().uuidString)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: staging) }
        let temporary = staging.appendingPathComponent("encrypted")
        try data.write(to: temporary, options: .withoutOverwriting)
        try synchronize(temporary)
        _ = try open(read(temporary), password: password)
        // moveItem fails if the destination exists; never combine atomic + withoutOverwriting.
        try moveExclusive(temporary, to: output)
    }

    static func read(_ url: URL) throws -> Data {
        try boundedRead(url, limit: maximumBytes + 9 * 1024 * 1024)
    }

    private static func boundedRead(_ url: URL, limit: Int) throws -> Data {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { throw FileMetadata.posix("无法读取文件", url) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var status = stat()
        guard fstat(descriptor, &status) == 0, status.st_mode & S_IFMT == S_IFREG else { throw Failure.message("不支持链接或特殊文件。") }
        guard status.st_size <= limit else { throw Failure.message("文件与扩展属性总大小超过 64 MB。") }
        var data = Data()
        while let part = try handle.read(upToCount: min(1024 * 1024, limit - data.count + 1)), !part.isEmpty {
            data.append(part)
            guard data.count <= limit else { throw Failure.message("文件在读取期间增长，已取消操作。") }
        }
        return data
    }

    static func moveExclusive(_ source: URL, to destination: URL) throws {
        guard renamex_np(source.path, destination.path, UInt32(RENAME_EXCL)) == 0 else { throw FileMetadata.posix("无法原地替换（可能有同名文件或权限不足）", destination) }
    }

    static func exists(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0
    }

    static func synchronizeDirectory(_ url: URL) throws {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_DIRECTORY)
        guard descriptor >= 0 else { throw FileMetadata.posix("无法同步目录", url) }
        defer { Darwin.close(descriptor) }
        guard fsync(descriptor) == 0 else { throw FileMetadata.posix("无法同步目录", url) }
    }

    static func synchronize(_ url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.synchronize()
    }

    private static func safePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\0") && path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
    static func validate(_ archive: Archive) throws {
        guard safePath(archive.name), !archive.name.contains("/"), archive.entries.count <= maximumEntries else { throw Failure.message("加密文件目录无效。") }
        var paths = Set<String>()
        let filePaths = Set(archive.entries.filter { !$0.directory }.map(\.path))
        for entry in archive.entries {
            guard safePath(entry.path), paths.insert(entry.path).inserted,
                  (entry.directory ? entry.contents == nil : entry.contents != nil) else { throw Failure.message("加密文件包含无效路径。") }
            var parent = (entry.path as NSString).deletingLastPathComponent
            while !parent.isEmpty {
                guard !filePaths.contains(parent) else { throw Failure.message("加密文件的目录与文件路径冲突。") }
                parent = (parent as NSString).deletingLastPathComponent
            }
        }
        if !archive.directory {
            guard archive.entries.count == 1, archive.entries[0].path == archive.name, !archive.entries[0].directory else { throw Failure.message("加密文件结构无效。") }
        }
    }

    /// Stage privately, then publish with a non-overwriting move. Ciphertext is always retained.
    static func restore(_ archive: Archive, into parent: URL) throws -> URL {
        try validate(archive)
        let fm = FileManager.default
        let target = parent.appendingPathComponent(archive.name)
        guard !exists(target) else { throw Failure.message("“\(archive.name)”已存在，请选择其他恢复位置。") }
        let staging = parent.appendingPathComponent(".easylock-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: staging) }
        let root = staging.appendingPathComponent(archive.name, isDirectory: archive.directory)
        if archive.directory { try fm.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]) }
        for entry in archive.entries.sorted(by: { $0.path.count < $1.path.count }) {
            let destination = archive.directory ? root.appendingPathComponent(entry.path) : root
            if entry.directory {
                try fm.createDirectory(at: destination, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            } else {
                try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                try entry.contents!.write(to: destination, options: .withoutOverwriting)
                try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            }
        }
        for entry in archive.entries.sorted(by: { $0.path.count > $1.path.count }) {
            let destination = archive.directory ? root.appendingPathComponent(entry.path) : root
            try entry.metadata?.apply(to: destination)
        }
        try archive.metadata?.apply(to: root)
        for entry in archive.entries where !entry.directory {
            let file = archive.directory ? root.appendingPathComponent(entry.path) : root
            let handle = try FileHandle(forReadingFrom: file)
            do { try handle.synchronize(); try handle.close() }
            catch { try? handle.close(); throw error }
        }
        if archive.metadata != nil { try verify(archive, at: root) }
        try moveExclusive(root, to: target)
        return target
    }

    static func verify(_ expected: Archive, at root: URL) throws {
        let actual = try snapshot(root, originalName: expected.name)
        guard expected.directory == actual.directory, expected.entries.count == actual.entries.count,
              expected.metadata?.matches(actual.metadata!) ?? true else { throw Failure.message("原件发生变化或元数据无法完整恢复，已取消替换。") }
        let actualEntries = Dictionary(uniqueKeysWithValues: actual.entries.map { ($0.path, $0) })
        for entry in expected.entries {
            guard let other = actualEntries[entry.path], entry.directory == other.directory, entry.contents == other.contents,
                  entry.metadata?.matches(other.metadata!) ?? true else { throw Failure.message("内容或元数据校验失败，已取消替换。") }
        }
        // Verification reads must not leave a changed access timestamp on the restored item.
        for entry in expected.entries {
            try entry.metadata?.applyTimes(to: expected.directory ? root.appendingPathComponent(entry.path) : root)
        }
        try expected.metadata?.applyTimes(to: root)
    }
}
