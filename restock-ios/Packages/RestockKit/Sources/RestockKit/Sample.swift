import Foundation

public extension AppData {
    /// An example pantry with realistic history, so a new user (or App Review) sees the app working.
    static func sample(today: Day, settings: AppSettings = AppSettings()) -> AppData {
        // name, aisle, days between buys, days since last buy, purchases, price, store
        let rows: [(String, String, Int, Int, Int, Double, String)] = [
            ("Whole milk", "Dairy & eggs", 7, 9, 6, 3.99, "Trader Joe's"), ("Eggs, dozen", "Dairy & eggs", 10, 9, 5, 4.49, "Trader Joe's"), ("Bananas", "Produce", 6, 4, 8, 1.29, "Trader Joe's"),
            ("Greek yogurt", "Dairy & eggs", 8, 2, 4, 5.49, "Costco"), ("Sourdough bread", "Bakery", 7, 7, 5, 4.99, "Trader Joe's"), ("Coffee beans", "Pantry", 21, 16, 4, 12.99, "Costco"),
            ("Olive oil", "Pantry", 60, 44, 3, 11.99, "Costco"), ("Chicken thighs", "Meat & fish", 10, 3, 5, 8.72, "Safeway"), ("Baby spinach", "Produce", 7, 6, 6, 3.49, "Trader Joe's"),
            ("Toilet paper", "Household", 30, 31, 3, 18.99, "Costco"), ("Dish soap", "Household", 45, 20, 2, 3.79, "Safeway"), ("Sparkling water", "Drinks", 14, 12, 4, 5.99, "Costco"),
            ("Oats", "Pantry", 28, 10, 3, 4.29, "Trader Joe's"), ("Cheddar", "Dairy & eggs", 14, 15, 4, 6.49, "Safeway"), ("Toothpaste", "Personal care", 50, 23, 2, 4.19, "Safeway"), ("Tortilla chips", "Snacks", 12, 1, 3, 3.29, "Trader Joe's"),
        ]
        var items: [Item] = rows.enumerated().map { k, r in
            let (name, aisle, every, since, n, price, store) = r
            var purchases: [Purchase] = []
            var day = today.adding(days: -since)
            for i in 0..<n {
                let jitter = ((k * 7 + i * 3) % 5) - 2
                let otherStore = i == 1 && k % 3 == 0
                let st = otherStore ? (store == "Costco" ? "Trader Joe's" : "Safeway") : store
                let p = (price * (1 + (Double((k + i) % 4) - 1.5) * 0.03) * (otherStore ? 1.12 : 1) * 100).rounded() / 100
                purchases.insert(Purchase(date: day, price: p, store: st), at: 0)
                day = day.adding(days: -(every + (i == n - 2 ? 0 : jitter)))
            }
            return Item(name: name, category: aisle, purchases: purchases)
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
