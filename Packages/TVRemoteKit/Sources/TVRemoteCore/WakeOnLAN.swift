import Foundation
#if canImport(Network) && !os(Linux)
import Network
#endif

/// Sends a Wake-on-LAN magic packet. Samsung and LG TVs power on this way
/// when "Mobile TV On" / "Turn on via Wi-Fi" is enabled on the TV.
///
/// Best effort: broadcast may need the multicast entitlement on watchOS, so
/// the packet is also sent directly to the TV's last known address.
public enum WakeOnLAN {
    public static func magicPacket(macAddress: String) -> Data? {
        guard let mac = parse(macAddress) else { return nil }
        var packet = Data(repeating: 0xFF, count: 6)
        for _ in 0 ..< 16 { packet.append(contentsOf: mac) }
        return packet
    }

    static func parse(_ text: String) -> [UInt8]? {
        let parts = text.split(whereSeparator: { $0 == ":" || $0 == "-" }).map(String.init)
        guard parts.count == 6 else { return nil }
        let bytes = parts.compactMap { UInt8($0, radix: 16) }
        return bytes.count == 6 ? bytes : nil
    }
}

#if canImport(Network) && !os(Linux)
extension WakeOnLAN {
    public static func wake(macAddress: String, host: String?) async {
        guard let packet = magicPacket(macAddress: macAddress) else { return }

        var targets: [String] = ["255.255.255.255"]
        if let host { targets.append(host) }
        for target in targets {
            await send(packet, to: target)
        }
    }

    private static func send(_ packet: Data, to host: String) async {
        let connection = NWConnection(host: NWEndpoint.Host(host), port: 9, using: .udp)
        let once = OnceFlag()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: packet, completion: .contentProcessed { _ in
                        connection.cancel()
                        once.run { continuation.resume() }
                    })
                case .failed, .waiting, .cancelled:
                    connection.cancel()
                    once.run { continuation.resume() }
                default:
                    break
                }
            }
            connection.start(queue: DispatchQueue.global(qos: .utility))
        }
    }
}
#endif
