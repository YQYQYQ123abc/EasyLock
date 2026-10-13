import Foundation
import CryptoKit
import Darwin

/// Version 3: encrypted manifest, fixed-size authenticated chunks, authenticated terminator.
/// AAD binds every frame to the archive header and its sequence number; EOF is mandatory.
enum StreamArchive {
    static let magic = Data("EASYLOCK\u{0}03".utf8)
    static let chunkSize = 1024 * 1024
    static let manifestLimit = 72 * 1024 * 1024
    struct Entry: Codable {
        let path: String
        let directory: Bool
        let size: Int64
        let digest: Data
        let metadata: FileMetadata
    }
    struct Manifest: Codable {
        let name: String
        let directory: Bool
        let metadata: FileMetadata
        let entries: [Entry]
        var bytes: Int64 { entries.reduce(0) { $0 + $1.size } }
        func location(_ entry: Entry, at root: URL) -> URL { directory ? root.appendingPathComponent(entry.path) : root }
    }
    static func reader(_ url: URL) throws -> FileHandle {
        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw FileMetadata.posix("无法读取文件", url) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
            Darwin.close(fd); throw LockEngine.Failure.message("不支持链接或特殊文件。")
        }
        return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }
    static func exact(_ handle: FileHandle, _ count: Int) throws -> Data {
        var result = Data()
        while result.count < count {
            let part = try handle.read(upToCount: count - result.count) ?? Data()
            guard !part.isEmpty else { throw LockEngine.Failure.message("加密文件不完整，原件未修改。") }
            result.append(part)
        }
        return result
    }
    static func hash(_ url: URL, control: OperationControl?, progress: ((Int64) -> Void)? = nil) throws -> (Int64, Data) {
        let handle = try reader(url); defer { try? handle.close() }
        var digest = SHA256(); var size: Int64 = 0
        while true {
            try control?.check()
            let part = try handle.read(upToCount: chunkSize) ?? Data()
            if part.isEmpty { break }
            digest.update(data: part); size += Int64(part.count); progress?(size)
        }
        return (size, Data(digest.finalize()))
    }
    static func snapshot(_ root: URL, name: String? = nil, control: OperationControl? = nil, phase: String = "检查文件") throws -> Manifest {
        try control?.check(); control?.update(phase)
        let metadata = try FileMetadata.capture(root)
        let directory = try FileMetadata.status(root).st_mode & S_IFMT == S_IFDIR
        var urls = [root]
        if directory {
            var failure: Error?
            guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, errorHandler: { _, error in failure = error; return false }) else { throw LockEngine.Failure.message("无法读取目录。") }
            urls = []
            for case let url as URL in walker {
                try control?.check()
                // Reject symlinks before descending or reading any linked content.
                _ = try FileMetadata.status(url)
                urls.append(url)
                guard urls.count <= LockEngine.maximumEntries else { throw LockEngine.Failure.message("最多支持 10,000 个目录条目。") }
            }
            if let failure { throw failure }
        }
        var entries: [Entry] = []
        var metadataBytes = metadata.attributes.values.reduce(0) { $0 + $1.count }
        let archiveName = name ?? root.lastPathComponent
        var total: Int64 = 0
        for url in urls.sorted(by: { $0.path < $1.path }) {
            let info = try FileMetadata.status(url)
            guard info.st_size >= 0, info.st_size < Int64.max / Int64(LockEngine.maximumEntries) else { throw LockEngine.Failure.message("文件大小超出支持范围。") }
            if info.st_mode & S_IFMT == S_IFREG { total += info.st_size }
        }
        var completed: Int64 = 0
        for url in urls.sorted(by: { $0.path < $1.path }) {
            try control?.check()
            let meta = directory ? try FileMetadata.capture(url) : metadata
            if directory { metadataBytes += meta.attributes.values.reduce(0) { $0 + $1.count } }
            guard metadataBytes <= LockEngine.maximumBytes else { throw LockEngine.Failure.message("扩展属性总量超过 64 MB，已停止操作。") }
            let isDirectory = try FileMetadata.status(url).st_mode & S_IFMT == S_IFDIR
            let path = directory ? url.standardizedFileURL.pathComponents.dropFirst(root.standardizedFileURL.pathComponents.count).joined(separator: "/") : archiveName
            let value = isDirectory ? (Int64(0), Data()) : try hash(url, control: control) { count in control?.update(phase, completed + count, total) }
            completed += value.0
            entries.append(Entry(path: path, directory: isDirectory, size: value.0, digest: value.1, metadata: meta))
        }
        let manifest = Manifest(name: archiveName, directory: directory, metadata: metadata, entries: entries)
        try validate(manifest)
        return manifest
    }
    static func validate(_ manifest: Manifest) throws {
        try LockEngine.validate(.init(name: manifest.name, directory: manifest.directory, entries: manifest.entries.map {
            .init(path: $0.path, directory: $0.directory, contents: $0.directory ? nil : Data())
        }))
        var total: Int64 = 0
        for entry in manifest.entries {
            guard entry.size >= 0, entry.size <= Int64.max / Int64(LockEngine.maximumEntries),
                  entry.directory ? entry.size == 0 && entry.digest.isEmpty : entry.digest.count == 32 else { throw LockEngine.Failure.message("文件清单无效。") }
            total += entry.size
        }
    }
    static func number(_ value: UInt64) -> Data {
        var value = value.bigEndian
        return withUnsafeBytes(of: &value) { Data($0) }
    }
    static func frame(_ plain: Data, header: Data, index: UInt64, key: SymmetricKey, to handle: FileHandle) throws {
        let nonce = try AES.GCM.Nonce(data: Data(repeating: 0, count: 4) + number(index))
        let sealed = try AES.GCM.seal(plain, using: key, nonce: nonce, authenticating: header + number(index))
        let data = sealed.ciphertext + sealed.tag
        try handle.write(contentsOf: number(UInt64(data.count)))
        try handle.write(contentsOf: data)
    }
    static func unframe(_ handle: FileHandle, header: Data, index: UInt64, key: SymmetricKey, limit: Int) throws -> Data {
        let length = try exact(handle, 8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        guard length >= 16, length <= UInt64(limit + 16) else { throw LockEngine.Failure.message("加密分块长度无效。") }
        let data = try exact(handle, Int(length))
        do {
            let nonce = try AES.GCM.Nonce(data: Data(repeating: 0, count: 4) + number(index))
            let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: data.dropLast(16), tag: data.suffix(16))
            return try AES.GCM.open(box, using: key, authenticating: header + number(index))
        } catch { throw LockEngine.Failure.message("密码不正确，或加密文件已损坏。原件未修改。") }
    }
    static func seal(_ manifest: Manifest, source: URL, to output: URL, password: String, recoveryPublicKey: Data? = nil, control: OperationControl?) throws {
        guard !password.isEmpty else { throw LockEngine.Failure.message("请输入密码。") }
        let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
        let encoded = try encoder.encode(manifest)
        guard encoded.count <= manifestLimit else { throw LockEngine.Failure.message("目录元数据过大。") }
        let header: Data; let key: SymmetricKey
        if let recoveryPublicKey { (header, key) = try RecoveryKey.sealHeader(password: password, recipient: recoveryPublicKey) }
        else {
            let salt = try LockEngine.random(16)
            header = magic + salt
            key = SymmetricKey(data: try LockEngine.derive(password, salt: salt))
        }
        let fd = Darwin.open(output.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw FileMetadata.posix("无法写入密文", output) }
        let writer = FileHandle(fileDescriptor: fd, closeOnDealloc: true); defer { try? writer.close() }
        try writer.write(contentsOf: header)
        try frame(encoded, header: header, index: 0, key: key, to: writer)
        let total = manifest.bytes
        var index: UInt64 = 1; var done: Int64 = 0
        for entry in manifest.entries where !entry.directory {
            let input = try reader(manifest.location(entry, at: source)); defer { try? input.close() }
            var remaining = entry.size; var digest = SHA256()
            while remaining > 0 {
                try control?.check()
                let part = try exact(input, Int(min(Int64(chunkSize), remaining)))
                digest.update(data: part)
                try frame(part, header: header, index: index, key: key, to: writer)
                index += 1; remaining -= Int64(part.count); done += Int64(part.count)
                control?.update("加密内容", done, total)
            }
            guard (try input.read(upToCount: 1) ?? Data()).isEmpty, Data(digest.finalize()) == entry.digest else { throw LockEngine.Failure.message("文件在处理期间发生变化，已取消替换。") }
        }
        try control?.check()
        try frame(Data(), header: header, index: index, key: key, to: writer)
        try writer.synchronize()
    }
    static func openManifest(_ input: FileHandle, password: String, recoveryKey: String? = nil) throws -> (Manifest, Data, SymmetricKey) {
        let version = try exact(input, magic.count)
        let header: Data; let key: SymmetricKey
        if version == RecoveryKey.magic {
            header = try version + exact(input, RecoveryKey.headerLength - version.count)
            key = try RecoveryKey.openHeader(header, password: password, recovery: recoveryKey)
        } else {
            guard version == magic else { throw LockEngine.Failure.message("不是受支持的分块文件。") }
            guard recoveryKey == nil else { throw LockEngine.Failure.message("此文件未启用恢复密钥，请使用原加密密码。") }
            guard !password.isEmpty else { throw LockEngine.Failure.message("请输入密码。") }
            header = try version + exact(input, 16)
            key = SymmetricKey(data: try LockEngine.derive(password, salt: Data(header.suffix(16))))
        }
        let manifest = try PropertyListDecoder().decode(Manifest.self, from: unframe(input, header: header, index: 0, key: key, limit: manifestLimit))
        try validate(manifest)
        return (manifest, header, key)
    }
    /// Writes only inside a private transaction folder; no user-visible path is published here.
    static func restore(_ source: URL, into parent: URL, password: String, recoveryKey: String? = nil, control: OperationControl?) throws -> (Manifest, URL) {
        let input = try reader(source); defer { try? input.close() }
        let (manifest, header, key) = try openManifest(input, password: password, recoveryKey: recoveryKey)
        let root = parent.appendingPathComponent(manifest.name)
        guard !LockEngine.exists(root) else { throw LockEngine.Failure.message("恢复目标已存在。") }
        let fm = FileManager.default
        if manifest.directory { try fm.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]) }
        for entry in manifest.entries.filter(\.directory).sorted(by: { $0.path.count < $1.path.count }) {
            try fm.createDirectory(at: manifest.location(entry, at: root), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        let total = manifest.bytes
        var index: UInt64 = 1; var done: Int64 = 0
        for entry in manifest.entries where !entry.directory {
            try control?.check()
            let destination = manifest.location(entry, at: root)
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let fd = Darwin.open(destination.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
            guard fd >= 0 else { throw FileMetadata.posix("无法恢复文件", destination) }
            let output = FileHandle(fileDescriptor: fd, closeOnDealloc: true); defer { try? output.close() }
            var remaining = entry.size; var digest = SHA256()
            while remaining > 0 {
                try control?.check()
                let expected = Int(min(Int64(chunkSize), remaining))
                let part = try unframe(input, header: header, index: index, key: key, limit: expected)
                guard part.count == expected else { throw LockEngine.Failure.message("加密分块不完整。") }
                try output.write(contentsOf: part); digest.update(data: part)
                remaining -= Int64(part.count); done += Int64(part.count); index += 1
                control?.update("恢复并校验内容", done, total)
            }
            guard Data(digest.finalize()) == entry.digest else { throw LockEngine.Failure.message("文件内容校验失败。") }
            try output.synchronize()
        }
        guard try unframe(input, header: header, index: index, key: key, limit: 0).isEmpty,
              (try input.read(upToCount: 1) ?? Data()).isEmpty else { throw LockEngine.Failure.message("加密文件结束标记无效。") }
        for entry in manifest.entries.sorted(by: { $0.path.count > $1.path.count }) { try entry.metadata.apply(to: manifest.location(entry, at: root)) }
        try manifest.metadata.apply(to: root)
        try verify(manifest, at: root, control: control)
        // Persist metadata as well as bytes before moving the original.
        for entry in manifest.entries where !entry.directory {
            let handle = try reader(manifest.location(entry, at: root))
            defer { try? handle.close() }
            try handle.synchronize()
        }
        // Persist directory entries as well as data before moving the original.
        for entry in manifest.entries where entry.directory { try LockEngine.synchronizeDirectory(manifest.location(entry, at: root)) }
        if manifest.directory { try LockEngine.synchronizeDirectory(root) }
        try LockEngine.synchronizeDirectory(parent)
        return (manifest, root)
    }
    static func verify(_ expected: Manifest, at root: URL, control: OperationControl?) throws {
        let actual = try snapshot(root, name: expected.name, control: control, phase: "核对内容与属性")
        guard expected.directory == actual.directory, expected.entries.count == actual.entries.count, expected.metadata.matches(actual.metadata) else { throw LockEngine.Failure.message("文件或属性发生变化，已停止替换。") }
        for (a, b) in zip(expected.entries, actual.entries) {
            guard a.path == b.path, a.directory == b.directory, a.size == b.size, a.digest == b.digest, a.metadata.matches(b.metadata) else { throw LockEngine.Failure.message("内容或属性校验失败，已停止替换。") }
        }
        for entry in expected.entries { try entry.metadata.applyTimes(to: expected.location(entry, at: root)) }
        try expected.metadata.applyTimes(to: root)
    }
    static func isStream(_ url: URL) throws -> Bool {
        let input = try reader(url); defer { try? input.close() }
        let version = try input.read(upToCount: magic.count)
        return version == magic || version == RecoveryKey.magic
    }
}
