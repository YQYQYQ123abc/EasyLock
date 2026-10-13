import Foundation

struct PasswordCredential: Codable, Sendable {
    let salt: Data
    let verifier: Data
    static func make(_ password: String) throws -> Self {
        guard password.count >= 10 else { throw LockEngine.Failure.message("主密码至少需要 10 个字符。") }
        let salt = try LockEngine.random(16)
        return Self(salt: salt, verifier: try LockEngine.derive(password, salt: salt))
    }
    func matches(_ password: String) throws -> Bool {
        guard !password.isEmpty, salt.count == 16, verifier.count == 32 else { return false }
        let candidate = try LockEngine.derive(password, salt: salt)
        return zip(candidate, verifier).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
    func save(to url: URL) throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        try LockEngine.synchronize(url)
        try LockEngine.synchronizeDirectory(url.deletingLastPathComponent())
    }
}
