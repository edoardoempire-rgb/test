import CryptoKit
import Foundation

enum JobVerifier {
    static let publicKeyBase64 = "L0kDZm2ynYPAhFweDg4dbY3K1NJEtXb1sJP6HL+YX/k="
    static let expectedKeyId = "poc-ed25519-2026-01"

    static func verify(_ envelope: JobEnvelope, now: Date = Date()) throws {
        guard envelope.keyId == expectedKeyId,
              let keyData = Data(base64Encoded: publicKeyBase64),
              let signature = Data(base64Encoded: envelope.signature) else { throw BridgeError.invalidSignature }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(envelope.payload)
        let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
        guard key.isValidSignature(signature, for: data) else { throw BridgeError.invalidSignature }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let issued = formatter.date(from: envelope.payload.issuedAt),
              let expires = formatter.date(from: envelope.payload.expiresAt),
              expires > now, issued <= now.addingTimeInterval(30),
              expires.timeIntervalSince(issued) <= 300 else { throw BridgeError.expired }
        guard envelope.payload.v == 1,
              ["apply", "restore"].contains(envelope.payload.action),
              envelope.payload.cardRef.range(of: #"^[A-Za-z0-9._+=-]{3,128}$"#, options: .regularExpression) != nil
        else { throw BridgeError.invalidPayload("Payload non valido.") }
    }
}
