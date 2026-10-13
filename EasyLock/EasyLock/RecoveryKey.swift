import Foundation
import CryptoKit

/// An optional second recipient for newly encrypted files. Only the public key is persisted.
enum RecoveryKey {
    static let magic = Data("EASYLOCK\u{0}04".utf8)
    static let prefixLength = magic.count + 16 + 32 + 32
    static let headerLength = prefixLength + 60 + 60
    static func generate() -> String {
        let data = Curve25519.KeyAgreement.PrivateKey().rawRepresentation
        return "ELRK1:" + data.base64EncodedString() + ":" + checksum(data)
    }
    private static func checksum(_ data: Data) -> String { SHA256.hash(data: data).prefix(4).map { String(format: "%02x", $0) }.joined() }
    static func privateKey(_ text: String) throws -> Curve25519.KeyAgreement.PrivateKey {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "ELRK1", let raw = Data(base64Encoded: String(parts[1])), raw.count == 32,
              parts[2] == checksum(raw) else { throw LockEngine.Failure.message("恢复密钥格式或校验码不正确，请完整输入保存的 ELRK1 密钥。") }
        return try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: raw)
    }
    static func publicKey(_ text: String) throws -> Data { try privateKey(text).publicKey.rawRepresentation }
    static func identifier(_ publicKey: Data) -> String { SHA256.hash(data: publicKey).prefix(6).map { String(format: "%02x", $0) }.joined() }
    static func sealHeader(password: String, recipient: Data) throws -> (Data, SymmetricKey) {
        let publicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: recipient)
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        let salt = try LockEngine.random(16)
        let prefix = magic + salt + recipient + ephemeral.publicKey.rawRepresentation
        let rawKey = try LockEngine.random(32)
        let passwordKey = SymmetricKey(data: try LockEngine.derive(password, salt: salt))
        let shared = try ephemeral.sharedSecretFromKeyAgreement(with: publicKey)
        let recoveryKey = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt, sharedInfo: Data("EasyLock recovery v4".utf8), outputByteCount: 32)
        let first = try AES.GCM.seal(rawKey, using: passwordKey, authenticating: prefix + Data("password".utf8)).combined!
        let second = try AES.GCM.seal(rawKey, using: recoveryKey, authenticating: prefix + Data("recovery".utf8)).combined!
        return (prefix + first + second, SymmetricKey(data: rawKey))
    }
    static func openHeader(_ header: Data, password: String, recovery: String?) throws -> SymmetricKey {
        guard header.count == headerLength, header.starts(with: magic) else { throw LockEngine.Failure.message("恢复文件头不完整。") }
        let prefix = Data(header.prefix(prefixLength))
        let salt = Data(header[magic.count..<magic.count+16])
        let recipient = Data(header[magic.count+16..<magic.count+48])
        let raw: Data
        do {
            if let recovery {
                let privateKey = try privateKey(recovery)
                guard privateKey.publicKey.rawRepresentation == recipient else { throw LockEngine.Failure.message("恢复密钥与此文件不匹配。请使用加密此文件时启用的密钥。") }
                let ephemeral = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: header[(magic.count+48)..<prefixLength])
                let shared = try privateKey.sharedSecretFromKeyAgreement(with: ephemeral)
                let key = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt, sharedInfo: Data("EasyLock recovery v4".utf8), outputByteCount: 32)
                raw = try AES.GCM.open(AES.GCM.SealedBox(combined: header.suffix(60)), using: key, authenticating: prefix + Data("recovery".utf8))
            } else {
                guard !password.isEmpty else { throw LockEngine.Failure.message("请输入文件加密密码。") }
                let key = SymmetricKey(data: try LockEngine.derive(password, salt: salt))
                raw = try AES.GCM.open(AES.GCM.SealedBox(combined: header[prefixLength..<prefixLength+60]), using: key, authenticating: prefix + Data("password".utf8))
            }
        } catch let error as LockEngine.Failure { throw error }
        catch { throw LockEngine.Failure.message("解密凭据不正确，或文件头已损坏。原件未修改。") }
        guard raw.count == 32 else { throw LockEngine.Failure.message("文件密钥无效。") }
        return SymmetricKey(data: raw)
    }
}
