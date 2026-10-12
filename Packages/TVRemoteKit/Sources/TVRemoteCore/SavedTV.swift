import Foundation

/// A TV the user added. Secrets (Samsung token, LG client key) are *not*
/// stored here; see `SecretStore`.
public struct SavedTV: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var brand: TVBrand
    public var name: String
    public var host: String
    /// Optional hint for reconnecting, e.g. a Samsung MAC for Wake-on-LAN.
    public var macAddress: String?
    /// User-chosen accent for the TV picker ("red", "blue", …); nil for default.
    public var colorName: String?

    public init(id: UUID = UUID(), brand: TVBrand, name: String, host: String, macAddress: String? = nil, colorName: String? = nil) {
        self.id = id
        self.brand = brand
        self.name = name
        self.host = host
        self.macAddress = macAddress
        self.colorName = colorName
    }
}

/// Persists the list of saved TVs and which one is selected.
public final class SavedTVStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let listKey = "tvremote.savedTVs"
    private let selectedKey = "tvremote.selectedTV"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var tvs: [SavedTV] {
        get {
            guard let data = defaults.data(forKey: listKey),
                  let list = try? JSONDecoder().decode([SavedTV].self, from: data) else { return [] }
            return list
        }
        set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: listKey)
        }
    }

    public var selectedID: UUID? {
        get { defaults.string(forKey: selectedKey).flatMap(UUID.init(uuidString:)) }
        set { defaults.set(newValue?.uuidString, forKey: selectedKey) }
    }

    public func upsert(_ tv: SavedTV) {
        var list = tvs
        if let index = list.firstIndex(where: { $0.id == tv.id }) {
            list[index] = tv
        } else {
            list.append(tv)
        }
        tvs = list
    }

    public func remove(id: UUID) {
        tvs = tvs.filter { $0.id != id }
        if selectedID == id { selectedID = tvs.first?.id }
    }
}
