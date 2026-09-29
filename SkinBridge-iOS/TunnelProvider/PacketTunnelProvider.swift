import Darwin
import NetworkExtension

/// Local-only packet tunnel used by SkinBridge to reach the iPhone's own
/// Remote Service Discovery endpoint. The address translation follows the
/// StosVPN/LocalDevVPN loopback design; traffic never leaves the device.
final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let deviceAddress = "10.7.0.0"
    private let exposedAddress = "10.7.0.1"
    private let subnetMask = "255.255.255.0"
    private lazy var deviceValue = ipValue(deviceAddress)
    private lazy var exposedValue = ipValue(exposedAddress)

    override func startTunnel(
        options: [String: NSObject]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: deviceAddress)
        let ipv4 = NEIPv4Settings(addresses: [deviceAddress], subnetMasks: [subnetMask])
        ipv4.includedRoutes = [NEIPv4Route(destinationAddress: deviceAddress, subnetMask: subnetMask)]
        ipv4.excludedRoutes = [.default()]
        settings.ipv4Settings = ipv4

        setTunnelNetworkSettings(settings) { [weak self] error in
            guard error == nil, let self else {
                completionHandler(error)
                return
            }
            self.forwardPackets()
            completionHandler(nil)
        }
    }

    override func stopTunnel(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }

    private func forwardPackets() {
        packetFlow.readPackets { [weak self] packets, protocols in
            guard let self else { return }
            var translated = packets
            for index in translated.indices
            where protocols[index].int32Value == AF_INET && translated[index].count >= 20 {
                translated[index].withUnsafeMutableBytes { bytes in
                    guard let words = bytes.baseAddress?.assumingMemoryBound(to: UInt32.self) else { return }
                    let source = UInt32(bigEndian: words[3])
                    let destination = UInt32(bigEndian: words[4])
                    if source == self.deviceValue { words[3] = self.exposedValue.bigEndian }
                    if destination == self.exposedValue { words[4] = self.deviceValue.bigEndian }
                }
            }
            self.packetFlow.writePackets(translated, withProtocols: protocols)
            self.forwardPackets()
        }
    }

    private func ipValue(_ address: String) -> UInt32 {
        let octets = address.split(separator: ".").compactMap(UInt32.init)
        guard octets.count == 4 else { return 0 }
        return (octets[0] << 24) | (octets[1] << 16) | (octets[2] << 8) | octets[3]
    }
}
