import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// IPv4 address and netmask of the active Wi-Fi interface.
public struct LocalInterface: Equatable, Sendable {
    public let name: String
    public let address: UInt32
    public let netmask: UInt32

    public var addressString: String { LocalNetwork.string(from: address) }

    /// Every other host address in the subnet, capped to the /24 that contains
    /// us so a scan stays short on large networks.
    public var scanTargets: [String] {
        var mask = netmask
        if (~mask) > 0xFF { mask = 0xFFFF_FF00 }
        let network = address & mask
        let hostBits = ~mask
        guard hostBits >= 2 else { return [] }
        return (1 ..< hostBits).compactMap { offset in
            let candidate = network | offset
            return candidate == address ? nil : LocalNetwork.string(from: candidate)
        }
    }
}

public enum LocalNetwork {
    /// The first non-loopback IPv4 interface, preferring Wi-Fi (`en0`).
    public static func primaryInterface() -> LocalInterface? {
        let all = interfaces()
        return all.first { $0.name == "en0" } ?? all.first
    }

    public static func interfaces() -> [LocalInterface] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }

        var result: [LocalInterface] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard let addr = entry.pointee.ifa_addr, addr.pointee.sa_family == sa_family_t(AF_INET),
                  let maskPtr = entry.pointee.ifa_netmask else { continue }
            let flags = Int32(truncatingIfNeeded: entry.pointee.ifa_flags)
            guard flags & Int32(IFF_UP) != 0, flags & Int32(IFF_LOOPBACK) == 0 else { continue }
            let name = String(cString: entry.pointee.ifa_name)
            let address = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            let mask = maskPtr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            guard address != 0 else { continue }
            result.append(LocalInterface(name: name, address: address, netmask: mask))
        }
        return result
    }

    static func string(from address: UInt32) -> String {
        "\(address >> 24 & 0xFF).\(address >> 16 & 0xFF).\(address >> 8 & 0xFF).\(address & 0xFF)"
    }

    public static func parse(_ dotted: String) -> UInt32? {
        let parts = dotted.split(separator: ".").compactMap { UInt32($0) }
        guard parts.count == 4, parts.allSatisfy({ $0 <= 255 }) else { return nil }
        return parts[0] << 24 | parts[1] << 16 | parts[2] << 8 | parts[3]
    }
}
