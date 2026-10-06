import Foundation

/// A TV found on the network but not yet saved.
public struct DiscoveredDevice: Identifiable, Hashable, Sendable {
    public var id: String { "\(brand.rawValue)|\(host)" }
    public let brand: TVBrand
    public let name: String
    public let host: String
    /// Extra identification, e.g. model name.
    public let detail: String?

    public init(brand: TVBrand, name: String, host: String, detail: String? = nil) {
        self.brand = brand
        self.name = name
        self.host = host
        self.detail = detail
    }

    public static func == (lhs: DiscoveredDevice, rhs: DiscoveredDevice) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
