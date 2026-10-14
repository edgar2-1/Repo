import Foundation

public extension AppData {
    /// An example pantry with realistic history, so a new user (or App Review) sees the app working.
    static func sample(today: Day, settings: AppSettings = AppSettings()) -> AppData {
        struct Row { let name: String; let aisle: String; let every: Int; let since: Int; let count: Int; let price: Double; let store: String }
        let rows: [Row] = [
            Row(name: "Whole milk", aisle: "Dairy & eggs", every: 7, since: 9, count: 6, price: 3.99, store: "Trader Joe's"),
            Row(name: "Eggs, dozen", aisle: "Dairy & eggs", every: 10, since: 9, count: 5, price: 4.49, store: "Trader Joe's"),
            Row(name: "Bananas", aisle: "Produce", every: 6, since: 4, count: 8, price: 1.29, store: "Trader Joe's"),
            Row(name: "Greek yogurt", aisle: "Dairy & eggs", every: 8, since: 2, count: 4, price: 5.49, store: "Costco"),
            Row(name: "Sourdough bread", aisle: "Bakery", every: 7, since: 7, count: 5, price: 4.99, store: "Trader Joe's"),
            Row(name: "Coffee beans", aisle: "Pantry", every: 21, since: 16, count: 4, price: 12.99, store: "Costco"),
            Row(name: "Olive oil", aisle: "Pantry", every: 60, since: 44, count: 3, price: 11.99, store: "Costco"),
            Row(name: "Chicken thighs", aisle: "Meat & fish", every: 10, since: 3, count: 5, price: 8.72, store: "Safeway"),
            Row(name: "Baby spinach", aisle: "Produce", every: 7, since: 6, count: 6, price: 3.49, store: "Trader Joe's"),
            Row(name: "Toilet paper", aisle: "Household", every: 30, since: 31, count: 3, price: 18.99, store: "Costco"),
            Row(name: "Dish soap", aisle: "Household", every: 45, since: 20, count: 2, price: 3.79, store: "Safeway"),
            Row(name: "Sparkling water", aisle: "Drinks", every: 14, since: 12, count: 4, price: 5.99, store: "Costco"),
            Row(name: "Oats", aisle: "Pantry", every: 28, since: 10, count: 3, price: 4.29, store: "Trader Joe's"),
            Row(name: "Cheddar", aisle: "Dairy & eggs", every: 14, since: 15, count: 4, price: 6.49, store: "Safeway"),
            Row(name: "Toothpaste", aisle: "Personal care", every: 50, since: 23, count: 2, price: 4.19, store: "Safeway"),
            Row(name: "Tortilla chips", aisle: "Snacks", every: 12, since: 1, count: 3, price: 3.29, store: "Trader Joe's"),
        ]
        var items: [Item] = []
        for (k, row) in rows.enumerated() {
            var purchases: [Purchase] = []
            var day: Day = today.adding(days: -row.since)
            for i in 0..<row.count {
                let jitter: Int = ((k * 7 + i * 3) % 5) - 2
                let otherStore: Bool = i == 1 && k % 3 == 0
                let store: String = otherStore ? (row.store == "Costco" ? "Trader Joe's" : "Safeway") : row.store
                let wobble: Double = 1 + (Double((k + i) % 4) - 1.5) * 0.03
                let markup: Double = otherStore ? 1.12 : 1
                let price: Double = (row.price * wobble * markup * 100).rounded() / 100
                purchases.insert(Purchase(date: day, price: price, store: store), at: 0)
                let gap: Int = row.every + (i == row.count - 2 ? 0 : jitter)
                day = day.adding(days: -gap)
            }
            items.append(Item(name: row.name, category: row.aisle, purchases: purchases))
        }
        items[0].notes = "1 gal"
        items[5].notes = "Kirkland medium roast"
        items.append(Item(name: "Birthday candles", category: "Household", onList: true, level: .out))
        let tripDay = today.adding(days: -9)
        let tripItems = items.filter { $0.purchases.last?.date == tripDay }
        let lines = tripItems.map { TripLine(itemId: $0.id, name: $0.name, qty: 1, price: $0.purchases.last?.price) }
        let total = lines.compactMap(\.price).reduce(0, +)
        return AppData(items: items, trips: lines.isEmpty ? [] : [Trip(date: tripDay, store: "Trader Joe's", total: (total * 100).rounded() / 100, items: lines, source: .trip)], settings: settings)
    }
}
