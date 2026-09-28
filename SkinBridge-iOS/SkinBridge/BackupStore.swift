import Foundation

actor BackupStore {
    static let shared = BackupStore()
    private let root: URL
    init() {
        root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "WalletBackups", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    private func safe(_ cardRef: String) -> String { cardRef.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "_", options: .regularExpression) }
    func saveOriginal(_ data: Data, cardRef: String) throws {
        let url = root.appending(path: safe(cardRef) + ".original")
        if !FileManager.default.fileExists(atPath: url.path) { try data.write(to: url, options: [.atomic, .completeFileProtection]) }
    }
    func original(cardRef: String) throws -> Data {
        let url = root.appending(path: safe(cardRef) + ".original")
        guard FileManager.default.fileExists(atPath: url.path) else { throw BridgeError.execution("Nessun backup locale disponibile per questa carta.") }
        return try Data(contentsOf: url)
    }
    func hasOriginal(cardRef: String) -> Bool {
        FileManager.default.fileExists(atPath: root.appending(path: safe(cardRef) + ".original").path)
    }
}
