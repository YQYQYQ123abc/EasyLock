import Foundation
import Darwin

/// Conservative estimate, not a reservation: every actual write must still handle ENOSPC.
enum SpacePreflight {
    struct Estimate: Sendable {
        let sourceBytes: Int64
        let requiredBytes: Int64
        let availableBytes: Int64
        var description: String {
            "预计需要额外空间 \(ByteCountFormatter.string(fromByteCount: requiredBytes, countStyle: .file))，当前可用 \(ByteCountFormatter.string(fromByteCount: availableBytes, countStyle: .file))。"
        }
    }
    static func available(at folder: URL) throws -> Int64 {
        var info = statfs()
        guard statfs(folder.path, &info) == 0 else { throw FileMetadata.posix("无法检查磁盘空间", folder) }
        let bytes = UInt64(info.f_bavail).multipliedReportingOverflow(by: UInt64(info.f_bsize))
        guard !bytes.overflow, bytes.partialValue <= UInt64(Int64.max) else { throw LockEngine.Failure.message("无法确定磁盘可用空间。") }
        return Int64(bytes.partialValue)
    }
    static func required(content: Int64, metadata: Int64, entries: Int, encrypt: Bool) throws -> Int64 {
        guard content >= 0, metadata >= 0, entries >= 0 else { throw LockEngine.Failure.message("文件大小无效。") }
        // Account for per-entry allocation, framing and metadata. Avoid wrapping on hostile lengths.
        let base = content.addingReportingOverflow(metadata)
        let doubled = base.partialValue.multipliedReportingOverflow(by: encrypt ? 2 : 1)
        let overhead = Int64(entries).multipliedReportingOverflow(by: 16 * 1024)
        let sum = doubled.partialValue.addingReportingOverflow(overhead.partialValue)
        let padded = sum.partialValue.addingReportingOverflow(max(16 * 1024 * 1024, content / 100))
        guard !base.overflow, !doubled.overflow, !overhead.overflow, !sum.overflow, !padded.overflow else { throw LockEngine.Failure.message("文件大小超出支持范围。") }
        return padded.partialValue
    }
    static func check(content: Int64, metadata: Int64, entries: Int, at folder: URL, encrypt: Bool, availableBytes: Int64? = nil) throws -> Estimate {
        let needed = try required(content: content, metadata: metadata, entries: entries, encrypt: encrypt)
        let free = try availableBytes ?? available(at: folder)
        let estimate = Estimate(sourceBytes: content, requiredBytes: needed, availableBytes: free)
        guard free >= needed else { throw LockEngine.Failure.message("空间不足，尚未替换原文件。" + estimate.description) }
        return estimate
    }
    static func inspect(_ source: URL, control: OperationControl? = nil) throws -> Estimate {
        var urls = [source]
        if try FileMetadata.status(source).st_mode & S_IFMT == S_IFDIR {
            var failure: Error?
            guard let walker = FileManager.default.enumerator(at: source, includingPropertiesForKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey], errorHandler: { _, error in failure = error; return false }) else { throw LockEngine.Failure.message("无法读取目录。") }
            for case let url as URL in walker {
                try control?.check()
                urls.append(url)
                guard urls.count <= LockEngine.maximumEntries + 1 else { throw LockEngine.Failure.message("目录条目超过 10,000 个。") }
            }
            if let failure { throw failure }
        }
        var content: Int64 = 0; var metadata: Int64 = 0
        for url in urls {
            try control?.check()
            let values = try url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
            if values.isUbiquitousItem == true && values.ubiquitousItemDownloadingStatus == .notDownloaded {
                throw LockEngine.Failure.message("“\(url.lastPathComponent)”尚未下载到本机，请在 Finder 下载后再加密。")
            }
            let attributes = try FileMetadata.capture(url)
            metadata += Int64(attributes.attributes.values.reduce(0) { $0 + $1.count })
            guard metadata <= LockEngine.maximumBytes else { throw LockEngine.Failure.message("扩展属性总量超过 64 MB。") }
            let status = try FileMetadata.status(url)
            if status.st_mode & S_IFMT == S_IFREG {
                guard status.st_size >= 0, status.st_size <= Int64.max / Int64(LockEngine.maximumEntries + 1) else { throw LockEngine.Failure.message("文件大小超出支持范围。") }
                content += status.st_size
            }
            guard FileManager.default.isReadableFile(atPath: url.path) else { throw LockEngine.Failure.message("无法读取“\(url.lastPathComponent)”。") }
        }
        return try check(content: content, metadata: metadata, entries: urls.count, at: source.deletingLastPathComponent(), encrypt: true)
    }
    static func check(_ manifest: StreamArchive.Manifest, at folder: URL, encrypt: Bool = false) throws {
        let bytes = manifest.entries.reduce(Int64(0)) { $0 + Int64($1.metadata.attributes.values.reduce(0) { $0 + $1.count }) }
        _ = try check(content: manifest.bytes, metadata: bytes + Int64(manifest.metadata.attributes.values.reduce(0) { $0 + $1.count }), entries: manifest.entries.count + 1, at: folder, encrypt: encrypt)
    }
}
