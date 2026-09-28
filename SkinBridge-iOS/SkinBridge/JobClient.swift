import Foundation

struct JobClient {
    func fetch(api: URL, id: String) async throws -> JobEnvelope {
        let url = api.appending(path: "v1/jobs/\(id)")
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw BridgeError.transport("Impossibile scaricare il job.") }
        return try JSONDecoder().decode(JobResponse.self, from: data).envelope
    }

    func report(_ result: ExecutionResult, payload: JobPayload) async throws {
        guard let url = URL(string: payload.resultUrl) else { throw BridgeError.invalidPayload("Result URL non valido.") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(payload.resultToken, forHTTPHeaderField: "x-result-token")
        request.httpBody = try JSONEncoder().encode(result)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw BridgeError.transport("L'API ha rifiutato il risultato.") }
    }
}
