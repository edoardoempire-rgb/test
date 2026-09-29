import Foundation
import NetworkExtension

@MainActor
final class LocalTunnelManager {
    static let shared = LocalTunnelManager()
    private let providerBundleIdentifier = "com.walletskins.skinbridge.tunnel"
    private var manager: NETunnelProviderManager?

    private init() {}

    func start() async throws {
        let manager = try await loadManager()
        if manager.connection.status == .connected || manager.connection.status == .connecting { return }

        let configuration = NETunnelProviderProtocol()
        configuration.providerBundleIdentifier = providerBundleIdentifier
        configuration.serverAddress = "SkinBridge — solo su questo iPhone"
        configuration.providerConfiguration = ["mode": "loopback"]
        manager.protocolConfiguration = configuration
        manager.localizedDescription = "SkinBridge Local Tunnel"
        manager.isEnabled = true
        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()
        try manager.connection.startVPNTunnel()

        for _ in 0..<30 {
            if manager.connection.status == .connected { return }
            if manager.connection.status == .invalid || manager.connection.status == .disconnected {
                throw TunnelError.notConnected
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw TunnelError.timedOut
    }

    func isConnected() async -> Bool {
        guard let manager = try? await loadManager() else { return false }
        return manager.connection.status == .connected
    }

    private func loadManager() async throws -> NETunnelProviderManager {
        if let manager { return manager }
        let existing = try await NETunnelProviderManager.loadAllFromPreferences()
            .first { ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == providerBundleIdentifier }
        let resolved = existing ?? NETunnelProviderManager()
        manager = resolved
        return resolved
    }
}

enum TunnelError: LocalizedError {
    case notConnected
    case timedOut

    var errorDescription: String? {
        switch self {
        case .notConnected: "Il tunnel locale non è stato autorizzato. Accetta la richiesta VPN di iOS e riprova."
        case .timedOut: "Il tunnel locale non ha risposto in tempo. Riprova mantenendo SkinBridge aperta."
        }
    }
}
