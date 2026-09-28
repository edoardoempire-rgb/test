import Foundation
import UIKit
import Combine

@MainActor final class BridgeViewModel: ObservableObject {
    enum Screen: Equatable { case idle, setup, scan, job }
    @Published var headline = "In attesa di Safari"
    @Published var detail = "Apri un job dalla PWA per avviare il bridge."
    @Published var busy = false
    @Published var screen: Screen = .idle
    @Published var setupItems: [SetupItem] = []
    @Published var setupReady = false
    @Published var scanReady = false
    @Published var scanning = false
    @Published var pairingPIN: String?
    private var setupCallback: URL?
    private var scanCallback: URL?
    private let client = JobClient()
    private let executor = ExecutorFactory.make()

    func open(_ url: URL) {
        guard url.scheme == "skinbridge" else { headline = "Link non valido"; detail = BridgeError.invalidLink.localizedDescription; return }
        if url.host == "ping" {
            guard let callback = callback(from: url) else { headline = "Callback non valida"; return }
            UIApplication.shared.open(callback)
            return
        }
        if url.host == "setup" {
            screen = .setup
            setupCallback = callback(from: url)
            Task { await refreshSetup() }
            return
        }
        if url.host == "scan" {
            screen = .scan
            scanCallback = callback(from: url)
            scanReady = executor.name == "mock"
            headline = scanReady ? "Simulazione rilevamento" : "Apri Wallet"
            detail = scanReady ? "Nel build mock useremo un riferimento opaco di prova. Nessun dato Wallet viene letto." : "Premi due volte il tasto laterale, autenticati e seleziona la carta da personalizzare."
            return
        }
        guard url.host == "job",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let apiValue = components.queryItems?.first(where: { $0.name == "api" })?.value,
              let api = URL(string: apiValue),
              let id = components.queryItems?.first(where: { $0.name == "job" })?.value else {
            headline = "Link non valido"; detail = BridgeError.invalidLink.localizedDescription; return
        }
        screen = .job
        busy = true; headline = "Verifico il job"; detail = "Firma, scadenza e compatibilità…"
        Task { await run(api: api, id: id) }
    }

    func refreshSetup() async {
        busy = true
        let check = await executor.compatibility()
        let mock = executor.name == "mock"
        setupItems = [
            SetupItem(id: "helper", title: "SkinBridge", detail: "Installato e raggiungibile da Safari.", ready: true),
            SetupItem(id: "signature", title: "Sicurezza job", detail: "Verifica Ed25519 e scadenza attive.", ready: true),
            SetupItem(id: "vpn", title: "VPN locale", detail: mock ? "Non necessaria nella demo mock." : "Attiva LocalDevVPN prima del test reale.", ready: mock),
            SetupItem(id: "pairing", title: "Pairing iPhone", detail: mock ? "Non necessario nella demo mock." : check.reason, ready: check.supported)
        ]
        setupReady = mock || check.supported
        headline = setupReady ? "iPhone pronto" : "Completa la preparazione"
        detail = setupReady ? "Puoi tornare a Safari e provare il round-trip." : check.reason
        busy = false
    }

    func finishSetup() {
        guard setupReady, let callback = setupCallback else { return }
        UIApplication.shared.open(callback)
    }

    func openLocalDevVPN() {
        if let url = URL(string: "localdevvpn://") { UIApplication.shared.open(url) }
    }

    func openAppSettings() {
        let developerMode = URL(string: "App-Prefs:root=Privacy&path=DEVELOPER_MODE")!
        if UIApplication.shared.canOpenURL(developerMode) { UIApplication.shared.open(developerMode) }
        else if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }

    func startPairing() {
        #if SKINBRIDGE_REAL && canImport(AirliftFFI)
        busy = true
        pairingPIN = nil
        Task {
            while busy {
                pairingPIN = PairingController.shared.pairingPIN
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        Task {
            do {
                _ = try await PairingController.shared.startAndWait()
                await refreshSetup()
            } catch {
                detail = "Pairing non completato: \(error.localizedDescription)"
                busy = false
            }
        }
        #else
        detail = "Il pairing reale non è incluso nel build mock. Per la demo puoi continuare senza questo passaggio."
        #endif
    }

    func completeCardScan() {
        guard scanReady, let callback = scanCallback,
              var components = URLComponents(url: callback, resolvingAgainstBaseURL: false) else { return }
        var items = components.queryItems ?? []
        items.removeAll { $0.name == "card" }
        items.append(URLQueryItem(name: "card", value: "mock-card-001"))
        components.queryItems = items
        if let url = components.url { UIApplication.shared.open(url) }
    }

    func beginCardDetection() {
        if scanReady { completeCardScan(); return }
        #if SKINBRIDGE_REAL && canImport(AirliftFFI)
        scanning = true
        headline = "Sto ascoltando Wallet"
        detail = "Ora premi due volte il tasto laterale, autenticati e tocca la carta."
        Task {
            do {
                let card = try await CardScanner.shared.detectFirst()
                guard let callback = scanCallback, var components = URLComponents(url: callback, resolvingAgainstBaseURL: false) else { return }
                var items = components.queryItems ?? []; items.removeAll { $0.name == "card" }; items.append(URLQueryItem(name: "card", value: card)); components.queryItems = items
                scanning = false
                if let url = components.url { UIApplication.shared.open(url) }
            } catch {
                scanning = false; headline = "Carta non rilevata"; detail = error.localizedDescription
            }
        }
        #else
        completeCardScan()
        #endif
    }

    private func run(api: URL, id: String) async {
        var payload: JobPayload?
        do {
            let envelope = try await client.fetch(api: api, id: id)
            payload = envelope.payload
            try JobVerifier.verify(envelope)
            let check = await executor.compatibility()
            guard check.supported else { throw BridgeError.incompatible(check.reason) }
            headline = envelope.payload.action == "apply" ? "Applico la skin" : "Ripristino il backup"
            detail = "Executor: \(executor.name)"
            let result = try await executor.execute(envelope.payload)
            try await client.report(result, payload: envelope.payload)
            headline = "Operazione completata"; detail = result.message
            callback(envelope.payload)
        } catch {
            let incompatible: Bool
            if let bridgeError = error as? BridgeError, case .incompatible(_) = bridgeError { incompatible = true } else { incompatible = false }
            let result = ExecutionResult(status: incompatible ? "incompatible" : "failed", executor: executor.name, message: error.localizedDescription, backupCreated: false)
            if let payload { try? await client.report(result, payload: payload); callback(payload) }
            headline = incompatible ? "Non compatibile" : "Operazione fallita"; detail = error.localizedDescription
        }
        busy = false
    }

    private func callback(_ payload: JobPayload) {
        guard var components = URLComponents(string: payload.callbackUrl) else { return }
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "job", value: payload.jobId)]
        if let url = components.url { UIApplication.shared.open(url) }
    }

    private func callback(from url: URL) -> URL? {
        guard let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "callback" })?.value,
              let callback = URL(string: value), ["https", "http"].contains(callback.scheme) else { return nil }
        return callback
    }
}
