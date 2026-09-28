import Foundation

protocol JobExecutor {
    var name: String { get }
    func compatibility() async -> Compatibility
    func execute(_ job: JobPayload) async throws -> ExecutionResult
}

struct MockExecutor: JobExecutor {
    let name = "mock"
    func compatibility() async -> Compatibility { Compatibility(supported: true, reason: "Mock executor attivo") }
    func execute(_ job: JobPayload) async throws -> ExecutionResult {
        try await Task.sleep(for: .milliseconds(650))
        if job.action == "apply" {
            try await BackupStore.shared.saveOriginal(Data("mock-original-\(job.cardRef)".utf8), cardRef: job.cardRef)
            guard let value = job.assetUrl, let url = URL(string: value) else { throw BridgeError.invalidPayload("Asset URL mancante.") }
            let (_, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode ?? 500 < 400 else { throw BridgeError.transport("Download skin fallito.") }
            return ExecutionResult(status: "succeeded", executor: name, message: "Round-trip mock completato; Wallet non è stato modificato.", backupCreated: true)
        }
        _ = try await BackupStore.shared.original(cardRef: job.cardRef)
        return ExecutionResult(status: "succeeded", executor: name, message: "Ripristino mock completato.", backupCreated: true)
    }
}

enum ExecutorFactory {
    static func make() -> any JobExecutor {
        #if SKINBRIDGE_REAL && canImport(AirliftFFI)
        return AirliftExecutor()
        #else
        return MockExecutor()
        #endif
    }
}
