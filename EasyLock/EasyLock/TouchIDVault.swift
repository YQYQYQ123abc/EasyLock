import Foundation
import Security
import LocalAuthentication

/// The system keychain releases the saved password only after current-set biometric verification.
/// No fingerprint data is accessed. Each unlock uses a fresh LAContext (no reuse window).
enum TouchIDVault {
    static var availability: (available: Bool, reason: String) {
        let context = LAContext()
        var error: NSError?
        let available = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        return (available && context.biometryType == .touchID, error?.localizedDescription ?? "请在系统设置中配置 Touch ID。")
    }

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "com.Only-You.EasyLock") + ".biometric-password",
         kSecAttrAccount as String: "master-password",
         kSecUseDataProtectionKeychain as String: true,
         kSecAttrSynchronizable as String: false]
    }

    static func enable(password: String) async throws {
        guard !password.isEmpty else { throw LockEngine.Failure.message("请先用主密码解锁应用。") }
        let availability = Self.availability
        guard availability.available else { throw LockEngine.Failure.message(availability.reason) }
        let context = LAContext()
        context.localizedFallbackTitle = ""
        defer { context.invalidate() }
        let accepted = try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "允许 EasyLock 使用 Touch ID 解锁主密码")
        guard accepted else { throw LockEngine.Failure.message("Touch ID 验证未完成。") }
        try await Task.detached {
            var error: Unmanaged<CFError>?
            guard let control = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .biometryCurrentSet, &error) else {
                throw error?.takeRetainedValue() as Error? ?? LockEngine.Failure.message("无法创建 Touch ID 密钥保护。")
            }
            // An explicit enable replaces only this app's biometric item.
            try remove()
            var item = query
            item[kSecAttrAccessControl as String] = control
            item[kSecValueData as String] = Data(password.utf8)
            item[kSecAttrLabel as String] = "EasyLock Touch ID 解锁"
            let status = SecItemAdd(item as CFDictionary, nil)
            guard status == errSecSuccess else { throw failure(status) }
        }.value
    }

    static func unlock() async throws -> String {
        let availability = Self.availability
        guard availability.available else { throw LockEngine.Failure.message(availability.reason) }
        return try await Task.detached {
            let context = LAContext()
            context.localizedReason = "使用 Touch ID 解锁 EasyLock 加密密码"
            context.localizedFallbackTitle = ""
            defer { context.invalidate() }
            var request = query
            request[kSecUseAuthenticationContext as String] = context
            request[kSecReturnData as String] = true
            request[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            let status = SecItemCopyMatching(request as CFDictionary, &result)
            guard status == errSecSuccess else { throw failure(status) }
            guard let data = result as? Data, let password = String(data: data, encoding: .utf8), !password.isEmpty else {
                throw LockEngine.Failure.message("Touch ID 保存的凭据无效，请用主密码解锁后重新启用。")
            }
            return password
        }.value
    }

    static func disable() async throws { try await Task.detached { try remove() }.value }

    private static func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw failure(status) }
    }

    private static func failure(_ status: OSStatus) -> Error {
        if status == errSecUserCanceled { return NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        if status == errSecItemNotFound {
            return LockEngine.Failure.message("Touch ID 凭据不存在或因指纹变更而失效，请使用主密码并重新启用 Touch ID。")
        }
        if status == errSecMissingEntitlement {
            return LockEngine.Failure.message("当前构建没有可用的钥匙串签名权限，请在 Xcode 中使用开发者签名运行。主密码仍可正常使用。")
        }
        return LockEngine.Failure.message("Touch ID 钥匙串访问失败：\(SecCopyErrorMessageString(status, nil) as String? ?? String(status))。请使用主密码。")
    }

    static func isCancellation(_ error: Error) -> Bool {
        let value = error as NSError
        if value.domain == NSOSStatusErrorDomain { return value.code == Int(errSecUserCanceled) }
        return value.domain == LAError.errorDomain && [LAError.userCancel.rawValue, LAError.appCancel.rawValue, LAError.systemCancel.rawValue, LAError.userFallback.rawValue].contains(value.code)
    }
}
