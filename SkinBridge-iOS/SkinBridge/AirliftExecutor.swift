import Foundation

#if SKINBRIDGE_REAL && canImport(AirliftFFI)
import AirliftFFI
import UIKit

struct AirliftExecutor: JobExecutor {
    let name = "airlift"

    func compatibility() async -> Compatibility {
        guard #available(iOS 27.0, *) else { return Compatibility(supported: false, reason: "SkinBridge reale richiede iOS 27 o successivo.") }
        let pairing = PairingController.pairingFilePath()
        guard FileManager.default.fileExists(atPath: pairing) else { return Compatibility(supported: false, reason: "Completa il pairing on-device prima di continuare.") }
        guard NetworkStatus.loopbackTunnelUp(deviceIP: "10.7.0.1") else { return Compatibility(supported: false, reason: "Attiva LocalDevVPN in modalità loopback.") }
        return Compatibility(supported: true, reason: "Pairing e tunnel locale disponibili.")
    }

    func execute(_ job: JobPayload) async throws -> ExecutionResult {
        let check = await compatibility()
        guard check.supported else { throw BridgeError.incompatible(check.reason) }
        if job.action == "restore" {
            return try await Task.detached(priority: .userInitiated) { try restoreBlocking(job) }.value
        }
        guard let value = job.assetUrl, let url = URL(string: value) else { throw BridgeError.invalidPayload("URL della skin mancante.") }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode ?? 500 < 400, let image = UIImage(data: data) else { throw BridgeError.transport("Immagine skin non valida.") }
        let backup = try await Task.detached(priority: .userInitiated) {
            try ArtworkBackupStore.captureIfNeeded(
                cardRef: job.cardRef,
                reader: { source, output in try read(source: source, output: output) },
                emergencyWriter: { directory in try write(directory: directory, target: passDirectory(job.cardRef)) }
            )
            let stage = try stageAssets(CardArtwork.makeAssets(image))
            defer { try? FileManager.default.removeItem(at: stage) }
            try write(directory: stage, target: passDirectory(job.cardRef))
            try invalidateCaches(job.cardRef)
            try ManagedArtworkStore.save(data, cardRef: job.cardRef)
            return ArtworkBackupStore.exists(cardRef: job.cardRef)
        }.value
        return ExecutionResult(status: "succeeded", executor: name, message: "Skin scritta sul dispositivo. Chiudi e riapri Wallet per visualizzarla.", backupCreated: backup)
    }

    private func restoreBlocking(_ job: JobPayload) throws -> ExecutionResult {
        let backup = try ArtworkBackupStore.directory(cardRef: job.cardRef)
        try write(directory: backup, target: passDirectory(job.cardRef))
        try invalidateCaches(job.cardRef)
        return ExecutionResult(status: "succeeded", executor: name, message: "File originali ripristinati dal backup locale. Chiudi e riapri Wallet.", backupCreated: true)
    }

    private func passDirectory(_ cardRef: String) -> String { "/var/mobile/Library/Passes/Cards/\(cardRef).pkpass" }
    private func stageAssets(_ assets: [String: Data]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "skinbridge-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, data) in assets { try data.write(to: directory.appending(path: name), options: .atomic) }
        return directory
    }
    private func invalidateCaches(_ cardRef: String) throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "skinbridge-cache-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for leaf in ["FrontFace", "Preview", "PlaceHolder"] { try Data("invalidated".utf8).write(to: directory.appending(path: leaf)) }
        for suffix in [".cache", ".pkcache"] { try? write(directory: directory, target: "/var/mobile/Library/Passes/Cards/\(cardRef)\(suffix)") }
    }
    private func write(directory: URL, target: String) throws {
        var pointer: UnsafeMutablePointer<CChar>?
        let rc = PairingController.pairingFilePath().withCString { pairing in directory.path.withCString { source in target.withCString { destination in al_exploit_write_dir(pairing, source, destination, nil, nil, &pointer) } } }
        let message = pointer.map { String(cString: $0) }; if let pointer { al_string_free(pointer) }
        guard rc == 0 else { throw BridgeError.execution(message ?? "Scrittura Airlift fallita.") }
    }
    private func read(source: String, output: URL) throws {
        var pointer: UnsafeMutablePointer<CChar>?
        let rc = PairingController.pairingFilePath().withCString { pairing in source.withCString { sourceFile in output.path.withCString { outputFile in al_exploit_read_file(pairing, sourceFile, outputFile, nil, nil, &pointer) } } }
        let message = pointer.map { String(cString: $0) }; if let pointer { al_string_free(pointer) }
        guard rc == 0 else { throw BridgeError.execution(message ?? "Lettura backup Airlift fallita.") }
    }
}

private enum CardArtwork {
    static func makeAssets(_ image: UIImage) throws -> [String: Data] {
        guard let three = render(image, size: CGSize(width: 1536, height: 969)), let two = render(image, size: CGSize(width: 1024, height: 646)) else { throw BridgeError.execution("Impossibile elaborare la skin.") }
        var out: [String: Data] = [:]
        for name in ["cardBackgroundCombined", "diffuse", "background", "strip"] { out["\(name)@3x.png"] = three; out["\(name)@2x.png"] = two }
        let bounds = CGRect(x: 0, y: 0, width: 1536, height: 969)
        let pdf = UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in context.beginPage(); image.draw(in: bounds) }
        for name in ["cardBackgroundCombined.pdf", "background.pdf", "strip.pdf"] { out[name] = pdf }
        return out
    }
    private static func render(_ image: UIImage, size: CGSize) -> Data? {
        let scale = max(size.width / image.size.width, size.height / image.size.height)
        let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let origin = CGPoint(x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: origin, size: drawn)) }.pngData()
    }
}

private enum ManagedArtworkStore {
    static func save(_ data: Data, cardRef: String) throws {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "ManagedArtwork", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let safe = cardRef.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "_", options: .regularExpression)
        try data.write(to: root.appending(path: safe + ".png"), options: [.atomic, .completeFileProtection])
    }
}

private enum ArtworkBackupStore {
    private static let names = [
        "cardBackgroundCombined@3x.png", "cardBackgroundCombined@2x.png", "cardBackgroundCombined.pdf",
        "background@3x.png", "background@2x.png", "background.pdf",
        "diffuse@3x.png", "diffuse@2x.png",
        "strip@3x.png", "strip@2x.png", "strip.pdf"
    ]
    private static func root() throws -> URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "OriginalArtwork", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private static func safe(_ value: String) -> String { value.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "_", options: .regularExpression) }
    static func exists(cardRef: String) -> Bool { (try? directory(cardRef: cardRef)) != nil }
    static func directory(cardRef: String) throws -> URL {
        let url = try root().appending(path: safe(cardRef), directoryHint: .isDirectory)
        let files = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        guard !files.isEmpty else { throw BridgeError.execution("Nessun backup originale disponibile per questa carta.") }
        return url
    }
    static func captureIfNeeded(cardRef: String, reader: (String, URL) throws -> Void, emergencyWriter: (URL) throws -> Void) throws {
        if exists(cardRef: cardRef) { return }
        let final = try root().appending(path: safe(cardRef), directoryHint: .isDirectory)
        let staging = try root().appending(path: safe(cardRef) + ".staging-" + UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        var captured = 0
        for name in names {
            let output = staging.appending(path: name)
            do {
                try reader("/var/mobile/Library/Passes/Cards/\(cardRef).pkpass/\(name)", output)
                let values = try? output.resourceValues(forKeys: [.fileSizeKey])
                if (values?.fileSize ?? 0) > 0 {
                    try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: output.path)
                    captured += 1
                }
            } catch {
                if error.localizedDescription.contains("source restore failed") {
                    let values = try? output.resourceValues(forKeys: [.fileSizeKey])
                    guard (values?.fileSize ?? 0) > 0 else { throw error }
                    try emergencyWriter(staging)
                    captured += 1
                    break
                }
                continue
            }
        }
        guard captured > 0 else { try? FileManager.default.removeItem(at: staging); throw BridgeError.execution("Non sono riuscito a leggere l'artwork originale: nessuna modifica è stata applicata.") }
        try? FileManager.default.removeItem(at: final)
        try FileManager.default.moveItem(at: staging, to: final)
    }
}
#endif
