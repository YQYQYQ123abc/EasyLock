import AppKit
import CryptoKit
import Observation
import Security

#if EASYLOCK_ENABLE_LICENSING && !EASYLOCK_APP_STORE
@MainActor @Observable final class LicenseStore {
    var receipt: LicenseReceipt?
    var busy = false
    var message: String?
    private var privateKey: Curve25519.Signing.PrivateKey?
    private var secret = ""
    private let endpoint: URL?
    private let verifyKey: Data?
    var configured: Bool { endpoint != nil && verifyKey?.count == 32 }
    var deviceID: String { privateKey.map { SHA256.hash(data: $0.publicKey.rawRepresentation).map { String(format: "%02x", $0) }.joined() } ?? "" }
    var active: Bool { receipt?.status == "active" && (receipt?.expiresAt ?? 0) > Date.now.timeIntervalSince1970 }
    private let cache = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("EasyLock/license-receipt.json")
    init() {
        let raw = Bundle.main.object(forInfoDictionaryKey: "EasyLockLicenseEndpoint") as? String ?? ""
        if let url = URL(string: raw), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil { endpoint = url } else { endpoint = nil }
        verifyKey = Data(base64Encoded: Bundle.main.object(forInfoDictionaryKey: "EasyLockLicensePublicKey") as? String ?? "")
        guard configured else { return }
        do {
            if let raw = try readSecret("device-key") { privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: raw) }
            else { let key = Curve25519.Signing.PrivateKey(); try writeSecret(key.rawRepresentation, account: "device-key"); privateKey = key }
            secret = String(data: try readSecret("license") ?? Data(), encoding: .utf8) ?? ""
            if let data = try? Data(contentsOf: cache), let envelope = try? JSONDecoder().decode(LicenseEnvelope.self, from: data), let verifyKey {
                receipt = try LicenseReceipt.verify(envelope, publicKey: verifyKey, deviceID: deviceID)
            }
        } catch { message = error.localizedDescription }
    }
    func perform(_ action: String, license: String? = nil, target: String? = nil) async {
        guard !busy, let endpoint, let verifyKey, let privateKey else { message = "许可证服务尚未开放。"; return }
        let code = (license ?? secret).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { message = "请输入许可证。"; return }
        busy = true; defer { busy = false }
        do {
            var fields: [String: Any] = ["action": action, "license": code, "publicKey": privateKey.publicKey.rawRepresentation.base64EncodedString(), "timestamp": Date.now.timeIntervalSince1970, "nonce": UUID().uuidString, "deviceName": Host.current().localizedName ?? "我的 Mac"]
            if let target { fields["targetDeviceID"] = target }
            let payload = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
            let envelope = LicenseEnvelope(payload: payload, signature: try privateKey.signature(for: payload))
            var request = URLRequest(url: endpoint); request.httpMethod = "POST"; request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONEncoder().encode(envelope)
            let config = URLSessionConfiguration.ephemeral
            let session = URLSession(configuration: config, delegate: RejectLicenseRedirects(), delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw LicenseError.message("授权服务响应无效。") }
            guard http.statusCode == 200 else { throw LicenseError.message(http.statusCode == 409 ? "已激活 3 台 Mac，请先解绑旧设备。" : "授权请求失败（\(http.statusCode)），请检查许可证或稍后重试。") }
            var data = Data()
            for try await byte in bytes {
                guard data.count < 65536 else { throw LicenseError.message("授权响应过大。") }
                data.append(byte)
            }
            let reply = try JSONDecoder().decode(LicenseEnvelope.self, from: data)
            let verified = try LicenseReceipt.verify(reply, publicKey: verifyKey, deviceID: deviceID)
            try writeSecret(Data(code.utf8), account: "license")
            secret = code
            try FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: cache, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cache.path)
            receipt = verified; message = action == "deactivate" ? "设备已解绑。" : "许可证已验证。"
        } catch { message = error.localizedDescription }
    }
    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.Only-You.EasyLock.license", kSecAttrAccount as String: account, kSecUseDataProtectionKeychain as String: true]
    }
    private func readSecret(_ account: String) throws -> Data? {
        var q = query(account); q[kSecReturnData as String] = true
        var result: CFTypeRef?; let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw LicenseError.message("无法访问本机许可证钥匙串（\(status)）。") }
        return result as? Data
    }
    private func writeSecret(_ data: Data, account: String) throws {
        let q = query(account)
        let status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var added = q; added[kSecValueData as String] = data; added[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(added as CFDictionary, nil) == errSecSuccess else { throw LicenseError.message("无法保存本机许可证。") }
        } else if status != errSecSuccess { throw LicenseError.message("无法更新本机许可证。") }
    }
}
private final class RejectLicenseRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
#endif
