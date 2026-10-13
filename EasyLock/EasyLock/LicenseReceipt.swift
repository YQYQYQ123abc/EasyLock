import Foundation
import CryptoKit

struct LicenseEnvelope: Codable { let payload: Data; let signature: Data }
struct LicenseReceipt: Codable {
    struct Device: Codable, Identifiable { let id: String; let name: String; let lastSeen: Double }
    let licenseID: String
    let deviceID: String
    let seatLimit: Int
    let issuedAt: Double
    let expiresAt: Double
    let status: String
    let devices: [Device]

    static func verify(_ envelope: LicenseEnvelope, publicKey: Data, deviceID: String, now: Date = .now) throws -> Self {
        guard envelope.payload.count <= 32768,
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey),
              key.isValidSignature(envelope.signature, for: envelope.payload) else { throw LicenseError.message("许可证签名验证失败。") }
        let value = try JSONDecoder().decode(Self.self, from: envelope.payload)
        let time = now.timeIntervalSince1970
        guard value.deviceID == deviceID, value.seatLimit == 3,
              ["active", "inactive"].contains(value.status),
              value.issuedAt.isFinite, value.expiresAt.isFinite,
              value.issuedAt <= time + 300, value.expiresAt > time,
              value.expiresAt > value.issuedAt, value.expiresAt - value.issuedAt <= 7 * 86400 + 1,
              value.devices.count <= 3, Set(value.devices.map(\.id)).count == value.devices.count,
              value.status != "active" || value.devices.contains(where: { $0.id == deviceID }) else { throw LicenseError.message("许可证已过期或不适用于本机，请联网刷新。") }
        return value
    }
}
enum LicenseError: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let text): text } }
}
