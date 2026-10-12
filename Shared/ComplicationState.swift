import Foundation
import TVRemoteCore
#if canImport(WidgetKit)
import WidgetKit
#endif

/// What the watch face complication shows. Written by the watch app, read by
/// the widget extension through a shared App Group container.
struct ComplicationState: Codable, Equatable {
    var tvName: String?
    var brand: TVBrand?
    var isOn: Bool?
    var updatedAt: Date

    static let key = "complicationState"

    /// App Group id, injected from the `APP_GROUP_ID` build setting via Info.plist.
    static var appGroupID: String? {
        Bundle.main.object(forInfoDictionaryKey: "TVRemoteAppGroup") as? String
    }

    static var sharedDefaults: UserDefaults? {
        guard let id = appGroupID, !id.isEmpty, !id.hasPrefix("$(") else { return nil }
        return UserDefaults(suiteName: id)
    }

    static func load() -> ComplicationState? {
        guard let data = sharedDefaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ComplicationState.self, from: data)
    }

    func save() {
        guard let defaults = Self.sharedDefaults, let data = try? JSONEncoder().encode(self) else { return }
        if let existing = Self.load(), existing.tvName == tvName, existing.brand == brand, existing.isOn == isOn {
            return // nothing visible changed; don't burn the widget's refresh budget
        }
        defaults.set(data, forKey: Self.key)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
