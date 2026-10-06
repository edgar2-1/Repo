import Foundation
import TVRemoteCore
import GoogleTVRemote
import RokuRemote
import SamsungRemote
import LGRemote

/// Builds the right `TVController` for a saved TV.
enum ControllerFactory {
    static let googleDeviceInfo = RemoteDeviceInfo(
        model: "Apple Watch",
        vendor: "Apple",
        packageName: "com.googletvwatchremote",
        appVersion: "1.0"
    )

    @MainActor
    static func make(for tv: SavedTV, credential: String?, identity: @MainActor () throws -> ClientIdentity) throws -> TVController {
        switch tv.brand {
        case .googleTV:
            return GoogleTVController(host: tv.host, identity: try identity(), deviceInfo: googleDeviceInfo)
        case .roku:
            return RokuController(host: tv.host)
        case .samsung:
            return SamsungController(host: tv.host, token: credential, clientName: "Apple Watch", macAddress: tv.macAddress)
        case .lg:
            return LGController(host: tv.host, clientKey: credential, macAddress: tv.macAddress)
        }
    }

    /// Looks up a friendly name / model / MAC for a host of a known brand.
    static func identify(brand: TVBrand, host: String) async -> DiscoveredDevice? {
        switch brand {
        case .googleTV: return nil
        case .roku: return await RokuController.identify(host: host)
        case .samsung: return await SamsungController.identify(host: host)
        case .lg: return await LGController.identify(host: host)
        }
    }

    /// MAC address for Wake-on-LAN where the platform exposes one.
    static func macAddress(brand: TVBrand, host: String) async -> String? {
        switch brand {
        case .samsung: return await SamsungController.fetchInfo(host: host)?.macAddress
        default: return nil
        }
    }
}
