import Foundation
import Darwin
import CoreServices

/// Metadata stored inside the authenticated payload, never on the visible encrypted file.
struct FileMetadata: Codable, Equatable {
    struct Timestamp: Codable, Equatable {
        let seconds: Int
        let nanoseconds: Int
        init(_ value: timespec) { seconds = value.tv_sec; nanoseconds = value.tv_nsec }
        var native: timespec { timespec(tv_sec: seconds, tv_nsec: nanoseconds) }
    }
    let permissions: UInt16
    let owner: UInt32
    let group: UInt32
    let flags: UInt32
    let created: Timestamp
    let modified: Timestamp
    let accessed: Timestamp
    let attributes: [String: Data]
    let acl: String?

    // These are host-managed security records, not portable document metadata.
    // Keep captured bytes in the archive for compatibility, but never remove/replay them.
    // Quarantine is handled separately via the public resource API, never removed.
    static let systemManagedAttributes: Set<String> = ["com.apple.macl", "com.apple.provenance"]
    static let quarantineAttribute = "com.apple.quarantine"
    var portableAttributes: [String: Data] {
        attributes.filter { !Self.systemManagedAttributes.contains($0.key) && $0.key != Self.quarantineAttribute }
    }

    private func preserveQuarantine(on url: URL, current: FileMetadata) throws {
        // Sandboxed processes cannot replay an older (possibly less restrictive) quarantine flag.
        // Keep any system-generated quarantine as-is. Never strip it from a restored file.
        guard attributes[Self.quarantineAttribute] != nil, current.attributes[Self.quarantineAttribute] == nil else { return }
        let properties: [String: Any] = [
            kLSQuarantineTypeKey as String: kLSQuarantineTypeOtherDownload as String,
            kLSQuarantineAgentNameKey as String: "EasyLock",
            kLSQuarantineTimeStampKey as String: Date()
        ]
        do { try (url as NSURL).setResourceValue(properties, forKey: .quarantinePropertiesKey) }
        catch { throw LockEngine.Failure.message("系统无法保留文件的下载隔离状态，已中止替换：\(url.lastPathComponent)（\(error.localizedDescription)）") }
        guard getxattr(url.path, Self.quarantineAttribute, nil, 0, 0, XATTR_NOFOLLOW) > 0 else {
            throw LockEngine.Failure.message("下载隔离状态校验失败，原件不会被替换。")
        }
    }

    static func status(_ url: URL) throws -> stat {
        var result = stat()
        guard lstat(url.path, &result) == 0 else { throw posix("无法读取文件状态", url) }
        return result
    }

    static func capture(_ url: URL) throws -> FileMetadata {
        let info = try status(url)
        let kind = info.st_mode & S_IFMT
        guard kind == S_IFREG || kind == S_IFDIR else { throw LockEngine.Failure.message("不支持链接或特殊文件，原件未修改。") }
        guard kind != S_IFREG || info.st_nlink == 1 else { throw LockEngine.Failure.message("文件存在硬链接，为避免破坏链接关系，已取消操作。") }
        guard info.st_uid == getuid() else { throw LockEngine.Failure.message("此文件属于其他用户，无法保证完整恢复所有权。原件未修改。") }
        let supportedFlags = UInt32(UF_HIDDEN | UF_NODUMP)
        guard info.st_flags & ~supportedFlags == 0 else { throw LockEngine.Failure.message("文件具有锁定、云占位或其他特殊标志，暂不支持原地加密。") }
        var attributes: [String: Data] = [:]
        let count = listxattr(url.path, nil, 0, XATTR_NOFOLLOW)
        guard count >= 0, count <= LockEngine.maximumBytes else { throw posix("无法读取扩展属性", url) }
        if count > 0 {
            var names = [CChar](repeating: 0, count: count)
            guard listxattr(url.path, &names, count, XATTR_NOFOLLOW) == count else { throw posix("扩展属性在读取期间发生变化", url) }
            for nameBytes in names.split(separator: 0) {
                let name = String(decoding: nameBytes.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                let size = getxattr(url.path, name, nil, 0, 0, XATTR_NOFOLLOW)
                guard size >= 0, size <= LockEngine.maximumBytes else { throw LockEngine.Failure.message("扩展属性过大或无法读取，原件未修改。") }
                var value = Data(count: size)
                let read = value.withUnsafeMutableBytes { getxattr(url.path, name, $0.baseAddress, size, 0, XATTR_NOFOLLOW) }
                guard read == size else { throw posix("无法完整读取扩展属性", url) }
                attributes[name] = value
                guard attributes.values.reduce(0, { $0 + $1.count }) <= LockEngine.maximumBytes else { throw LockEngine.Failure.message("扩展属性超过大小限制。") }
            }
        }
        var aclText: String?
        if let acl = acl_get_file(url.path, ACL_TYPE_EXTENDED) {
            defer { acl_free(UnsafeMutableRawPointer(acl)) }
            var entry: acl_entry_t?
            if acl_get_entry(acl, Int32(ACL_FIRST_ENTRY.rawValue), &entry) == 0 {
                guard let text = acl_to_text(acl, nil) else { throw posix("无法读取访问控制列表", url) }
                defer { acl_free(text) }
                aclText = String(cString: text)
            }
        } else if errno != ENOENT { throw posix("无法读取访问控制列表", url) }
        return FileMetadata(permissions: info.st_mode & 0o7777, owner: info.st_uid, group: info.st_gid, flags: info.st_flags,
                            created: Timestamp(info.st_birthtimespec), modified: Timestamp(info.st_mtimespec), accessed: Timestamp(info.st_atimespec), attributes: attributes, acl: aclText)
    }

    func apply(to url: URL) throws {
        // Restore portable metadata exactly without tampering with host security records.
        let current = try Self.capture(url)
        for key in current.portableAttributes.keys where portableAttributes[key] == nil {
            guard removexattr(url.path, key, XATTR_NOFOLLOW) == 0 else { throw Self.posix("无法移除临时文件的扩展属性 \(key)", url) }
        }
        for (key, value) in portableAttributes {
            if current.attributes[key] == value { continue }
            let result = value.withUnsafeBytes { setxattr(url.path, key, $0.baseAddress, value.count, 0, XATTR_NOFOLLOW) }
            guard result == 0 else { throw Self.posix("无法恢复扩展属性 \(key)", url) }
        }
        try preserveQuarantine(on: url, current: current)
        if current.owner != owner || current.group != group {
            guard chown(url.path, owner, group) == 0 else { throw Self.posix("无法恢复文件所有权", url) }
        }
        if current.permissions != permissions {
            guard chmod(url.path, mode_t(permissions)) == 0 else { throw Self.posix("无法恢复文件权限", url) }
        }
        if let acl, current.acl != acl {
            guard let native = acl_from_text(acl) else { throw Self.posix("访问控制列表无效", url) }
            defer { acl_free(UnsafeMutableRawPointer(native)) }
            guard acl_set_file(url.path, ACL_TYPE_EXTENDED, native) == 0 else { throw Self.posix("无法恢复访问控制列表", url) }
        } else if acl == nil && current.acl != nil {
            guard let empty = acl_init(0) else { throw Self.posix("无法创建访问控制列表", url) }
            defer { acl_free(UnsafeMutableRawPointer(empty)) }
            guard acl_set_file(url.path, ACL_TYPE_EXTENDED, empty) == 0 else { throw Self.posix("无法清理继承的访问权限", url) }
        }
        if current.flags != flags {
            guard chflags(url.path, flags) == 0 else { throw Self.posix("无法恢复文件标志", url) }
        }
        try applyTimes(to: url)
    }

    func applyTimes(to url: URL) throws {
        var specification = attrlist()
        specification.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        specification.commonattr = attrgroup_t(ATTR_CMN_CRTIME)
        var birth = created.native
        guard setattrlist(url.path, &specification, &birth, MemoryLayout<timespec>.size, UInt32(FSOPT_NOFOLLOW)) == 0 else { throw Self.posix("无法恢复创建时间", url) }
        let times = [accessed.native, modified.native]
        guard utimensat(AT_FDCWD, url.path, times, AT_SYMLINK_NOFOLLOW) == 0 else { throw Self.posix("无法恢复文件时间", url) }
    }

    /// Reads may legitimately update access time; compare all other restorable metadata.
    func matches(_ other: FileMetadata) -> Bool {
        permissions == other.permissions && owner == other.owner && group == other.group && flags == other.flags && created == other.created && modified == other.modified && portableAttributes == other.portableAttributes && acl == other.acl
            && (attributes[Self.quarantineAttribute] == nil || other.attributes[Self.quarantineAttribute]?.isEmpty == false)
    }

    static func posix(_ message: String, _ url: URL) -> Error {
        LockEngine.Failure.message("\(message)：\(url.lastPathComponent)（\(String(cString: strerror(errno)))）")
    }
}
