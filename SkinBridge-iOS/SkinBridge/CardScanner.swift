import Foundation

#if SKINBRIDGE_REAL && canImport(AirliftFFI)
import AirliftFFI

final class CardScanner: @unchecked Sendable {
    static let shared = CardScanner()
    private let regexes = [
        try! NSRegularExpression(pattern: "/(?:Cards|Passes/Cards)/([-A-Za-z0-9_+=]{20,44})(?:\\.pkpass|\\.cache|\\.pkcache|/|\\s|\"|'|\\)|,|$)"),
        try! NSRegularExpression(pattern: "/([-A-Za-z0-9_+=]{20,44})\\.(?:pkpass|cache|pkcache)"),
        try! NSRegularExpression(pattern: "(?<![A-Za-z0-9+/_-])([A-Za-z0-9+/_-]{27}=)(?![A-Za-z0-9+/_-])"),
        try! NSRegularExpression(pattern: #"VerificationCheck\.([A-Za-z0-9+/_-]+={0,2})(?=\s|\)|,|$)"#)
    ]

    func detectFirst(timeout: TimeInterval = 45) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let context = ScanContext(continuation: continuation, regexes: regexes)
            let opaque = Unmanaged.passRetained(context).toOpaque()
            DispatchQueue.global(qos: .userInitiated).async {
                var error: UnsafeMutablePointer<CChar>?
                let path = PairingController.pairingFilePath()
                let rc = path.withCString { pairing in
                    al_syslog_stream_start(pairing, cardScanCallback, opaque, &error)
                }
                let message = error.map { String(cString: $0) }
                if let error { al_string_free(error) }
                context.finish(.failure(BridgeError.execution(message ?? "Rilevamento carta terminato (\(rc)).")))
                Unmanaged<ScanContext>.fromOpaque(opaque).release()
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                context.finish(.failure(BridgeError.execution("Nessuna carta rilevata. Riapri Wallet, seleziona la carta e riprova.")))
                al_syslog_stream_stop()
            }
        }
    }
}

private final class ScanContext: @unchecked Sendable {
    private let ignored: Set<String> = ["OM6NYhwXMZrAw0sRUjR62wmF4ZQ=", "M6nDwZrkYbFlsodLgCbvyFZQ1cc=", "kJL-D0rr-SZhbj2c8nK-OQ9hCMY=", "hwAtAmHKYwsQrJbT5cTNDsaxVME="]
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?
    let regexes: [NSRegularExpression]
    init(continuation: CheckedContinuation<String, Error>, regexes: [NSRegularExpression]) { self.continuation = continuation; self.regexes = regexes }
    func process(_ line: String) {
        let lower = line.lowercased()
        guard lower.contains("wallet") || lower.contains("pass") || lower.contains("card") || lower.contains("verificationcheck") else { return }
        for regex in regexes {
            for match in regex.matches(in: line, range: NSRange(line.startIndex..., in: line)) where match.numberOfRanges > 1 {
                guard let range = Range(match.range(at: 1), in: line) else { continue }
                let value = String(line[range])
                guard value.count >= 20, value.count <= 64, !value.contains("/"), !ignored.contains(value), !(value.count == 36 && value.filter({ $0 == "-" }).count == 4) else { continue }
                finish(.success(value)); al_syslog_stream_stop(); return
            }
        }
    }
    func finish(_ result: Result<String, Error>) {
        lock.lock(); guard let continuation else { lock.unlock(); return }; self.continuation = nil; lock.unlock()
        continuation.resume(with: result)
    }
}

private let cardScanCallback: ALSyslogLineCallback = { context, line in
    guard let context, let line else { return }
    Unmanaged<ScanContext>.fromOpaque(context).takeUnretainedValue().process(String(cString: line))
}
#endif
