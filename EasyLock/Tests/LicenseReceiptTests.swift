import Foundation
import CryptoKit

@main struct LicenseReceiptTests {
    static func main() throws {
        let key = Curve25519.Signing.PrivateKey()
        let device = "device-a"
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func envelope(id: String = "device-a", expires: Double = 1_800_600_000, seats: Int = 3) throws -> LicenseEnvelope {
            let value = LicenseReceipt(licenseID: "license-1", deviceID: id, seatLimit: seats, issuedAt: now.timeIntervalSince1970, expiresAt: expires, status: "active", devices: [.init(id: id, name: "Mac", lastSeen: now.timeIntervalSince1970)])
            let data = try JSONEncoder().encode(value)
            return LicenseEnvelope(payload: data, signature: try key.signature(for: data))
        }
        func rejected(_ value: LicenseEnvelope, publicKey: Data? = nil) {
            do { _ = try LicenseReceipt.verify(value, publicKey: publicKey ?? key.publicKey.rawRepresentation, deviceID: device, now: now); fatalError("accepted invalid receipt") }
            catch {}
        }
        let good = try envelope()
        let valid = try LicenseReceipt.verify(good, publicKey: key.publicKey.rawRepresentation, deviceID: device, now: now)
        precondition(valid.seatLimit == 3)
        rejected(try envelope(id: "another-device"))
        rejected(try envelope(expires: now.timeIntervalSince1970 - 1))
        rejected(try envelope(expires: now.timeIntervalSince1970 + 8 * 86400))
        rejected(try envelope(seats: 4))
        rejected(good, publicKey: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation)
        rejected(LicenseEnvelope(payload: good.payload + Data([0]), signature: good.signature))
        rejected(LicenseEnvelope(payload: good.payload, signature: Data(repeating: 0, count: 64)))
        if CommandLine.arguments.count == 4 {
            let raw = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
            let envelope = try JSONDecoder().decode(LicenseEnvelope.self, from: raw)
            let receipt = try LicenseReceipt.verify(envelope, publicKey: Data(base64Encoded: CommandLine.arguments[2])!, deviceID: CommandLine.arguments[3])
            precondition(receipt.status == "active")
            print("PASS: Python server receipt verified by Swift CryptoKit client")
        }
        print("PASS: valid, forged, tampered, expired, wrong-device and excessive-seat license receipts")
    }
}
