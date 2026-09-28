import Foundation

struct JobEnvelope: Codable {
    let payload: JobPayload
    let signature: String
    let keyId: String
}

struct JobResponse: Codable {
    let envelope: JobEnvelope
    let status: String
}

struct JobPayload: Codable {
    let v: Int
    let jobId: String
    let action: String
    let cardRef: String
    let assetUrl: String?
    let callbackUrl: String
    let resultUrl: String
    let resultToken: String
    let issuedAt: String
    let expiresAt: String
    let nonce: String
}

struct ExecutionResult: Codable {
    let status: String
    let executor: String
    let message: String
    let backupCreated: Bool
}

struct Compatibility {
    let supported: Bool
    let reason: String
}

struct SetupItem: Identifiable {
    let id: String
    let title: String
    let detail: String
    let ready: Bool
}

enum BridgeError: LocalizedError {
    case invalidLink, invalidSignature, expired, invalidPayload(String), transport(String), incompatible(String), execution(String)
    var errorDescription: String? {
        switch self {
        case .invalidLink: "Deep link non valido."
        case .invalidSignature: "Firma del job non valida."
        case .expired: "Il job è scaduto."
        case .invalidPayload(let value), .transport(let value), .incompatible(let value), .execution(let value): value
        }
    }
}
