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
    @Published var onboardingMode = false
    @Published var setupActionTitle = "Continua automaticamente"
    @Published var setupActionEnabled = true
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
            onboardingMode = false
            screen = .setup
            setupCallback = callback(from: url)
            Task { await refreshSetup() }
            return
        }
        if url.host == "onboard" {
            guard let callback = callback(from: url) else { headline = "Callback non valida"; return }
            onboardingMode = true
            setupCallback = callback
            scanCallback = callback
            screen = .setup
            Task {
                await refreshSetup()
                if setupReady { advanceToCardScan() }
            }
            return
        }
        if url.host == "scan" {
            onboardingMode = false
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
        let state = localSetupState()
        setupItems = [
            SetupItem(id: "helper", title: "SkinBridge", detail: "Installato e raggiungibile da Safari.", ready: true),
            SetupItem(id: "signature", title: "Sicurezza job", detail: "Verifica Ed25519 e scadenza attive.", ready: true),
            SetupItem(id: "vpn", title: "VPN locale", detail: mock ? "Non necessaria nella demo mock." : state.vpn ? "LocalDevVPN attiva." : "SkinBridge aprirà LocalDevVPN per te.", ready: state.vpn),
            SetupItem(id: "pairing", title: "Pairing iPhone", detail: mock ? "Non necessario nella demo mock." : state.paired ? "Pairing locale già disponibile." : "SkinBridge avvierà il pairing e aprirà le Impostazioni.", ready: state.paired)
        ]
        setupReady = mock || check.supported
        setupActionEnabled = platformSupported
        setupActionTitle = !platformSupported ? "iOS non compatibile" : setupReady ? (onboardingMode ? "Continua alla carta" : "Torna a Safari") : !state.vpn ? "Attiva LocalDevVPN" : !state.paired ? "Avvia pairing guidato" : "Ricontrolla automaticamente"
        headline = setupReady ? "iPhone pronto" : "Completa la preparazione"
        detail = !platformSupported ? check.reason : setupReady ? (onboardingMode ? "La preparazione è completa. Ora colleghiamo la carta." : "Puoi tornare a Safari.") : !state.vpn ? "Tocca il pulsante: apriremo LocalDevVPN. Attivala e torna qui; SkinBridge riprenderà da sola." : !state.paired ? "La VPN è attiva. Avvia il pairing: apriremo le Impostazioni e ti mostreremo il codice da confermare." : check.reason
        busy = false
    }

    func continueAutomaticSetup() {
        guard !busy else { return }
        guard platformSupported else {
            detail = "Il core reale richiede iOS 27 o successivo."
            return
        }
        let state = localSetupState()
        if setupReady {
            if onboardingMode { advanceToCardScan() } else { finishSetup() }
            return
        }
        if !state.vpn {
            detail = "In LocalDevVPN attiva il collegamento, poi torna a SkinBridge. Riprenderemo automaticamente."
            openLocalDevVPN()
            return
        }
        if !state.paired {
            startPairing()
            return
        }
        Task {
            await refreshSetup()
            if setupReady && onboardingMode { advanceToCardScan() }
        }
    }

    func onAppBecameActive() {
        guard screen == .setup, onboardingMode, !busy, platformSupported else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            await refreshSetup()
            if setupReady {
                advanceToCardScan()
            } else {
                let state = localSetupState()
                if state.vpn && !state.paired { startPairing() }
            }
        }
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
        headline = "Pairing in corso"
        detail = "Apro le Impostazioni. Seleziona Pair with SkinBridge e conferma il codice mostrato qui."
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
                if setupReady && onboardingMode { advanceToCardScan() }
            } catch {
                detail = "Pairing non completato: \(error.localizedDescription)"
                busy = false
            }
        }
        Task {
            try? await Task.sleep(for: .milliseconds(900))
            if busy { openAppSettings() }
        }
        #else
        detail = "Il pairing reale non è incluso nel build mock. Per la demo puoi continuare senza questo passaggio."
        #endif
    }

    func completeCardScan() {
        guard scanReady, let callback = scanCallback,
              var components = URLComponents(url: callback, resolvingAgainstBaseURL: false) else { return }
        components.queryItems = completedCallbackItems(components.queryItems, card: "mock-card-001")
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
                components.queryItems = self.completedCallbackItems(components.queryItems, card: card)
                scanning = false
                if let url = components.url { _ = await UIApplication.shared.open(url) }
            } catch {
                scanning = false; headline = "Carta non rilevata"; detail = error.localizedDescription
            }
        }
        #else
        completeCardScan()
        #endif
    }

    private func advanceToCardScan() {
        screen = .scan
        scanReady = executor.name == "mock"
        headline = scanReady ? "Ultimo passaggio" : "Collega la carta"
        detail = scanReady ? "La build mock userà un riferimento opaco di prova e tornerà automaticamente a Safari." : "Avvia il rilevamento, poi premi due volte il tasto laterale, autenticati e seleziona la carta."
    }

    private func completedCallbackItems(_ existing: [URLQueryItem]?, card: String) -> [URLQueryItem] {
        var items = existing ?? []
        items.removeAll { ["bridge", "setup", "card"].contains($0.name) }
        if onboardingMode {
            items.append(URLQueryItem(name: "bridge", value: "ready"))
            items.append(URLQueryItem(name: "setup", value: "ready"))
        }
        items.append(URLQueryItem(name: "card", value: card))
        return items
    }

    private func localSetupState() -> (vpn: Bool, paired: Bool) {
        #if SKINBRIDGE_REAL && canImport(AirliftFFI)
        let pairing = PairingController.pairingFilePath()
        let attributes = try? FileManager.default.attributesOfItem(atPath: pairing)
        let bytes = attributes?[.size] as? NSNumber
        return (NetworkStatus.loopbackTunnelUp(deviceIP: "10.7.0.1"), (bytes?.intValue ?? 0) > 0)
        #else
        return (true, true)
        #endif
    }

    private var platformSupported: Bool {
        if executor.name == "mock" { return true }
        if #available(iOS 27.0, *) { return true }
        return false
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
