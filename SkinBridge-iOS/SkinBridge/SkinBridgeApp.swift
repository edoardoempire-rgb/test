import SwiftUI

@main struct SkinBridgeApp: App {
    @StateObject private var model = BridgeViewModel()
    var body: some Scene {
        WindowGroup { ContentView().environmentObject(model).onOpenURL { model.open($0) } }
    }
}

struct ContentView: View {
    @EnvironmentObject var model: BridgeViewModel
    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, Color(red: 0.07, green: 0.09, blue: 0.15)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            switch model.screen {
            case .setup: SetupView()
            case .scan: ScanView()
            case .idle, .job: StatusView()
            }
        }.preferredColorScheme(.dark)
    }
}

private struct ScanView: View {
    @EnvironmentObject var model: BridgeViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            BrandHeader(label: "CARTA")
            Spacer()
            Image(systemName: "wallet.pass.fill").font(.system(size: 58)).foregroundStyle(Color(red: 0.68, green: 0.58, blue: 1))
            Text(model.headline).font(.system(size: 42, weight: .bold, design: .rounded)).tracking(-1.5)
            Text(model.detail).foregroundStyle(.secondary).font(.title3).lineSpacing(4)
            VStack(alignment: .leading, spacing: 12) {
                Label("Premi due volte il tasto laterale", systemImage: "1.circle.fill")
                Label("Autenticati con Face ID", systemImage: "2.circle.fill")
                Label("Tocca la carta da usare", systemImage: "3.circle.fill")
            }.font(.headline).padding(.vertical, 8)
            Button(model.scanReady ? "Usa carta mock e torna a Safari" : model.scanning ? "Rilevamento in corso…" : "Inizia rilevamento") { model.beginCardDetection() }.buttonStyle(BridgePrimaryButton()).disabled(model.scanning)
            Spacer()
            PrivacyNote()
        }.padding(26).foregroundStyle(.white)
    }
}

private struct StatusView: View {
    @EnvironmentObject var model: BridgeViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            BrandHeader(label: model.screen == .job ? "JOB IN ESECUZIONE" : "BRIDGE PRONTO")
            Spacer()
            ZStack { RoundedRectangle(cornerRadius: 26).fill(Color.white.opacity(0.06)); Image(systemName: model.busy ? "arrow.triangle.2.circlepath" : "iphone.and.arrow.forward").font(.system(size: 44)).foregroundStyle(Color(red: 0.68, green: 0.58, blue: 1)) }.frame(height: 150)
            Text(model.headline).font(.system(size: 42, weight: .bold, design: .rounded)).tracking(-1.6)
            Text(model.detail).foregroundStyle(.secondary).font(.title3).lineSpacing(4)
            if model.busy { ProgressView().tint(.white) }
            Spacer()
            PrivacyNote()
        }.padding(26).foregroundStyle(.white)
    }
}

private struct SetupView: View {
    @EnvironmentObject var model: BridgeViewModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                BrandHeader(label: "CONFIGURAZIONE GUIDATA")
                Text(model.headline).font(.system(size: 40, weight: .bold, design: .rounded)).tracking(-1.5)
                Text(model.detail).foregroundStyle(.secondary).font(.body).lineSpacing(4)
                VStack(spacing: 10) {
                    ForEach(model.setupItems) { item in
                        HStack(alignment: .top, spacing: 13) {
                            Image(systemName: item.ready ? "checkmark.circle.fill" : "exclamationmark.circle.fill").foregroundStyle(item.ready ? .green : .yellow).font(.title3)
                            VStack(alignment: .leading, spacing: 4) { Text(item.title).font(.headline); Text(item.detail).font(.subheadline).foregroundStyle(.secondary) }
                            Spacer()
                        }.padding(16).background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 17))
                    }
                }
                if !model.setupReady {
                    Button("1. Apri LocalDevVPN") { model.openLocalDevVPN() }.buttonStyle(BridgeSecondaryButton())
                    Button("2. Apri impostazioni dell'app") { model.openAppSettings() }.buttonStyle(BridgeSecondaryButton())
                    Button("3. Avvia pairing su questo iPhone") { model.startPairing() }.buttonStyle(BridgeSecondaryButton())
                    if let pin = model.pairingPIN {
                        VStack(spacing: 5) { Text("CODICE PAIRING").font(.caption.bold()).foregroundStyle(.secondary); Text(pin).font(.system(size: 34, weight: .bold, design: .monospaced)).tracking(5) }.frame(maxWidth: .infinity).padding(18).background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                    }
                    Text("Durante il pairing vai in Impostazioni › Privacy e sicurezza › Modalità sviluppatore › Pair with SkinBridge e conferma il codice mostrato.").font(.footnote).foregroundStyle(.secondary).lineSpacing(3)
                    Button("Ricontrolla") { Task { await model.refreshSetup() } }.buttonStyle(BridgeSecondaryButton())
                }
                Button("Torna a Safari") { model.finishSetup() }.buttonStyle(BridgePrimaryButton()).disabled(!model.setupReady)
                if model.busy { ProgressView().frame(maxWidth: .infinity).tint(.white) }
                PrivacyNote().padding(.top, 8)
            }.padding(26)
        }.foregroundStyle(.white)
    }
}

private struct BrandHeader: View {
    let label: String
    var body: some View { HStack { Text("W").font(.headline.bold()).frame(width: 32, height: 32).background(LinearGradient(colors: [.purple, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 10)); Text("SKINBRIDGE").font(.caption.bold()).tracking(2); Spacer(); Text(label).font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(.secondary) } }
}

private struct PrivacyNote: View {
    var body: some View { Label("Nessun PAN, CVV o token di pagamento", systemImage: "lock.shield.fill").font(.footnote).foregroundStyle(.secondary) }
}

private struct BridgePrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.fontWeight(.bold).frame(maxWidth: .infinity).padding(.vertical, 17).background(Color(red: 0.68, green: 0.58, blue: 1).opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 16)).foregroundStyle(.black) }
}
private struct BridgeSecondaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.fontWeight(.semibold).frame(maxWidth: .infinity).padding(.vertical, 15).background(Color.white.opacity(configuration.isPressed ? 0.04 : 0.08), in: RoundedRectangle(cornerRadius: 15)).foregroundStyle(.white) }
}
