import Foundation

// The data model matches the web app's backup JSON, so a backup copied from the
// web version can be pasted into AppSettings > Restore and loads unchanged.

public enum StockLevel: String, Codable, Sendable, CaseIterable {
    case stocked, used, out
}

public struct Purchase: Codable, Hashable, Sendable {
    public var date: Day
    public var qty: Int
    /// Price for one unit.
    public var price: Double?
    public var store: String

    public init(date: Day, qty: Int = 1, price: Double? = nil, store: String = "") {
        self.date = date; self.qty = max(1, qty); self.price = price; self.store = store
    }

    enum CodingKeys: String, CodingKey { case date, qty, price, store }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        date = try c.decode(Day.self, forKey: .date)
        qty = max(1, (try? c.decodeIfPresent(Int.self, forKey: .qty)) ?? 1)
        price = try? c.decodeIfPresent(Double.self, forKey: .price)
        store = ((try? c.decodeIfPresent(String.self, forKey: .store)) ?? nil) ?? ""
    }
}

public struct Nutrition: Codable, Hashable, Sendable {
    public var kcal, fat, sat, carbs, sugars, fiber, protein, salt: Double?
    public init(kcal: Double? = nil, fat: Double? = nil, sat: Double? = nil, carbs: Double? = nil, sugars: Double? = nil, fiber: Double? = nil, protein: Double? = nil, salt: Double? = nil) {
        self.kcal = kcal; self.fat = fat; self.sat = sat; self.carbs = carbs; self.sugars = sugars; self.fiber = fiber; self.protein = protein; self.salt = salt
    }
    public var isEmpty: Bool { [kcal, fat, sat, carbs, sugars, fiber, protein, salt].allSatisfy { $0 == nil } }
}

/// A product from Open Food Facts linked to an item.
public struct Product: Codable, Hashable, Sendable {
    public var code: String
    public var name: String
    public var brand: String
    public var qty: String
    public var image: String
    /// Nutri-Score grade "a"…"e", or "" when unknown.
    public var grade: String
    public var serving: String
    public var nutrition: Nutrition
    /// False while the match is only a suggestion.
    public var confirmed: Bool

    public init(code: String, name: String, brand: String = "", qty: String = "", image: String = "", grade: String = "", serving: String = "", nutrition: Nutrition = Nutrition(), confirmed: Bool = false) {
        self.code = code; self.name = name; self.brand = brand; self.qty = qty; self.image = image; self.grade = grade; self.serving = serving; self.nutrition = nutrition; self.confirmed = confirmed
    }

    public var imageURL: URL? { image.isEmpty ? nil : URL(string: image) }
    public var pageURL: URL? { code.isEmpty ? nil : URL(string: "https://world.openfoodfacts.org/product/\(code)") }

    enum CodingKeys: String, CodingKey { case code, name, brand, qty, image, grade, serving, nutrition = "n", confirmed }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        func s(_ k: CodingKeys) -> String { ((try? c.decodeIfPresent(String.self, forKey: k)) ?? nil) ?? "" }
        code = s(.code); name = s(.name); brand = s(.brand); qty = s(.qty); image = s(.image); grade = s(.grade); serving = s(.serving)
        nutrition = ((try? c.decodeIfPresent(Nutrition.self, forKey: .nutrition)) ?? nil) ?? Nutrition()
        confirmed = ((try? c.decodeIfPresent(Bool.self, forKey: .confirmed)) ?? nil) ?? false
    }
}

public struct Item: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var category: String
    /// Fixed "runs out every N days" set by the user; nil means learn it from purchases.
    public var intervalDays: Int?
    /// Other names this item has appeared under on receipts.
    public var aliases: [String]
    public var purchases: [Purchase]
    public var onList: Bool
    public var inCart: Bool
    /// How many to buy on the current list.
    public var listQty: Int?
    public var level: StockLevel?
    /// The day the user marked it Restocked; restarts the cycle without a purchase.
    public var stockedOn: Day?
    public var snoozeUntil: Day?
    /// Usual store chosen by the user; nil means learn it from purchases.
    public var store: String?
    public var notes: String?
    public var product: Product?

    public init(id: String = UUID().uuidString, name: String, category: String, intervalDays: Int? = nil, aliases: [String] = [], purchases: [Purchase] = [], onList: Bool = false, inCart: Bool = false, listQty: Int? = nil, level: StockLevel? = nil, stockedOn: Day? = nil, snoozeUntil: Day? = nil, store: String? = nil, notes: String? = nil, product: Product? = nil) {
        self.id = id; self.name = name; self.category = category; self.intervalDays = intervalDays; self.aliases = aliases; self.purchases = purchases
        self.onList = onList; self.inCart = inCart; self.listQty = listQty; self.level = level; self.stockedOn = stockedOn; self.snoozeUntil = snoozeUntil
        self.store = store; self.notes = notes; self.product = product
    }

    enum CodingKeys: String, CodingKey { case id, name, category, intervalDays, aliases, purchases, onList, inCart, listQty, level, stockedOn, snoozeUntil, store, notes, product }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = ((try? c.decodeIfPresent(String.self, forKey: .id)) ?? nil) ?? UUID().uuidString
        name = try c.decode(String.self, forKey: .name)
        category = ((try? c.decodeIfPresent(String.self, forKey: .category)) ?? nil) ?? "Other"
        intervalDays = (try? c.decodeIfPresent(Int.self, forKey: .intervalDays)) ?? nil
        aliases = ((try? c.decodeIfPresent([String].self, forKey: .aliases)) ?? nil) ?? []
        purchases = ((try? c.decodeIfPresent([Purchase].self, forKey: .purchases)) ?? nil) ?? []
        onList = ((try? c.decodeIfPresent(Bool.self, forKey: .onList)) ?? nil) ?? false
        inCart = ((try? c.decodeIfPresent(Bool.self, forKey: .inCart)) ?? nil) ?? false
        listQty = (try? c.decodeIfPresent(Int.self, forKey: .listQty)) ?? nil
        level = (try? c.decodeIfPresent(StockLevel.self, forKey: .level)) ?? nil
        stockedOn = (try? c.decodeIfPresent(Day.self, forKey: .stockedOn)) ?? nil
        snoozeUntil = (try? c.decodeIfPresent(Day.self, forKey: .snoozeUntil)) ?? nil
        store = (try? c.decodeIfPresent(String.self, forKey: .store)) ?? nil
        notes = (try? c.decodeIfPresent(String.self, forKey: .notes)) ?? nil
        product = (try? c.decodeIfPresent(Product.self, forKey: .product)) ?? nil
    }

    public var quantityOnList: Int { max(1, listQty ?? 1) }
}

public struct TripLine: Codable, Hashable, Sendable {
    public var itemId: String?
    public var name: String
    public var qty: Int
    /// Line total (all units).
    public var price: Double?
    public init(itemId: String?, name: String, qty: Int = 1, price: Double? = nil) { self.itemId = itemId; self.name = name; self.qty = max(1, qty); self.price = price }

    enum CodingKeys: String, CodingKey { case itemId, name, qty, price }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        itemId = (try? c.decodeIfPresent(String.self, forKey: .itemId)) ?? nil
        name = ((try? c.decodeIfPresent(String.self, forKey: .name)) ?? nil) ?? ""
        qty = max(1, ((try? c.decodeIfPresent(Int.self, forKey: .qty)) ?? nil) ?? 1)
        price = (try? c.decodeIfPresent(Double.self, forKey: .price)) ?? nil
    }
}

public enum TripSource: String, Codable, Sendable { case trip, receipt }

/// A shopping trip, finished in the app or saved from a scanned receipt.
public struct Trip: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var date: Day
    public var store: String
    public var total: Double?
    public var items: [TripLine]
    public var source: TripSource
    /// Item count for old web-app receipts that didn't keep line detail.
    public var itemCount: Int?

    public init(id: String = UUID().uuidString, date: Day, store: String, total: Double?, items: [TripLine], source: TripSource) {
        self.id = id; self.date = date; self.store = store; self.total = total; self.items = items; self.source = source
    }

    enum CodingKeys: String, CodingKey { case id, date, store, total, items, source, itemCount }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = ((try? c.decodeIfPresent(String.self, forKey: .id)) ?? nil) ?? UUID().uuidString
        date = try c.decode(Day.self, forKey: .date)
        store = ((try? c.decodeIfPresent(String.self, forKey: .store)) ?? nil) ?? ""
        total = (try? c.decodeIfPresent(Double.self, forKey: .total)) ?? nil
        items = ((try? c.decodeIfPresent([TripLine].self, forKey: .items)) ?? nil) ?? []
        source = ((try? c.decodeIfPresent(TripSource.self, forKey: .source)) ?? nil) ?? .receipt
        itemCount = ((try? c.decodeIfPresent(Int.self, forKey: .itemCount)) ?? nil) ?? ((try? c.decodeIfPresent(Int.self, forKey: CodingKeys(stringValue: "items")!)) ?? nil)
    }

    public var displayTotal: Double? { total ?? (items.isEmpty ? nil : items.compactMap(\.price).reduce(0, +)) }
}

public struct AppSettings: Codable, Hashable, Sendable {
    /// Show "due soon" this many days ahead.
    public var soonDays: Int = 3
    public var budget: Double?
    public var groupByStore: Bool = false
    public var badge: Bool = false
    /// Weekly shopping day, 0 = Sunday … 6 = Saturday.
    public var shopDay: Int?
    /// "HH:mm"
    public var shopTime: String?
    /// Hour of day for "running low" notifications.
    public var reminderHour: Int = 9
    public var notifications: Bool = false
    public var autoProducts: Bool = true

    public init() {}

    enum CodingKeys: String, CodingKey { case soonDays, budget, groupByStore, badge, shopDay, shopTime, reminderHour, notifications, autoProducts }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        soonDays = ((try? c.decodeIfPresent(Int.self, forKey: .soonDays)) ?? nil) ?? 3
        budget = (try? c.decodeIfPresent(Double.self, forKey: .budget)) ?? nil
        groupByStore = ((try? c.decodeIfPresent(Bool.self, forKey: .groupByStore)) ?? nil) ?? false
        badge = ((try? c.decodeIfPresent(Bool.self, forKey: .badge)) ?? nil) ?? false
        shopDay = (try? c.decodeIfPresent(Int.self, forKey: .shopDay)) ?? nil
        shopTime = (try? c.decodeIfPresent(String.self, forKey: .shopTime)) ?? nil
        reminderHour = ((try? c.decodeIfPresent(Int.self, forKey: .reminderHour)) ?? nil) ?? 9
        notifications = ((try? c.decodeIfPresent(Bool.self, forKey: .notifications)) ?? nil) ?? false
        autoProducts = ((try? c.decodeIfPresent(Bool.self, forKey: .autoProducts)) ?? nil) ?? true
    }
}

public struct AppData: Codable, Hashable, Sendable {
    public var items: [Item]
    public var trips: [Trip]
    public var settings: AppSettings

    public init(items: [Item] = [], trips: [Trip] = [], settings: AppSettings = AppSettings()) {
        self.items = items; self.trips = trips; self.settings = settings
    }

    // The web app calls trips "receipts".
    enum CodingKeys: String, CodingKey { case items, trips = "receipts", settings }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        items = try c.decode([Item].self, forKey: .items)
        trips = ((try? c.decodeIfPresent([Trip].self, forKey: .trips)) ?? nil) ?? []
        settings = ((try? c.decodeIfPresent(AppSettings.self, forKey: .settings)) ?? nil) ?? AppSettings()
    }

    public static func decode(_ data: Data) throws -> AppData { try JSONDecoder().decode(AppData.self, from: data) }
    public func encoded(pretty: Bool = false) throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try e.encode(self)
    }

    public func index(of id: String) -> Int? { items.firstIndex { $0.id == id } }
    public func item(_ id: String) -> Item? { items.first { $0.id == id } }
}
