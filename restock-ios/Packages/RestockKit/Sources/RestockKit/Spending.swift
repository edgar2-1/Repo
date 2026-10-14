import Foundation

public struct PriceChange: Hashable, Sendable { public var name: String; public var previous: Double; public var latest: Double; public var change: Double }

public extension AppData {
    private var pricedPurchases: [(Purchase, Item)] { items.flatMap { it in it.purchases.filter { ($0.price ?? 0) > 0 }.map { ($0, it) } } }

    func spent(inMonthOf day: Day) -> Double {
        pricedPurchases.filter { $0.0.date.monthKey == day.monthKey }.reduce(0) { $0 + $1.0.price! * Double($1.0.qty) }
    }

    func spendByCategory(lastDays: Int, today: Day) -> [(category: String, amount: Double)] {
        var m: [String: Double] = [:]
        for (p, it) in pricedPurchases where p.date.days(until: today) < lastDays { m[it.category, default: 0] += p.price! * Double(p.qty) }
        return m.map { ($0.key, $0.value) }.sorted { $0.amount > $1.amount }
    }

    /// Items whose latest price differs from the median of earlier prices by 10% or more.
    func priceChanges() -> [PriceChange] {
        items.compactMap { it in
            let pr = it.purchases.filter { ($0.price ?? 0) > 0 }.sorted { $0.date < $1.date }
            guard pr.count >= 2 else { return nil }
            let latest = pr.last!.price!, previous = Predictor.median(pr.dropLast().map { $0.price! })
            let d = (latest - previous) / previous
            return abs(d) >= 0.1 ? PriceChange(name: it.name, previous: previous, latest: latest, change: d) : nil
        }.sorted { $0.change > $1.change }
    }
}

public struct Reminder: Hashable, Sendable {
    public var id: String
    public var day: Day
    public var hour: Int
    public var minute: Int
    public var title: String
    public var body: String
    public var repeatsWeekly: Bool
}

public enum ReminderPlanner {
    /// One "running low" notification per day, on the day items enter the due-soon window,
    /// plus the weekly shopping-day reminder. iOS keeps at most 64 pending, so this caps at 40.
    public static func plan(_ data: AppData, today: Day) -> [Reminder] {
        var byDay: [Day: [String]] = [:]
        for it in data.items where !it.onList && !it.inCart {
            let p = data.prediction(it, today: today)
            guard let due = p.due else { continue }
            let warn = due.adding(days: -data.settings.soonDays)
            if warn > today { byDay[warn, default: []].append(it.name) }
        }
        var out: [Reminder] = byDay.keys.sorted().prefix(40).map { day in
            let names = byDay[day]!.sorted()
            let body: String
            switch names.count {
            case 1: body = "\(names[0]) is running low."
            case 2: body = "\(names[0]) and \(names[1]) are running low."
            default: body = "\(names[0]), \(names[1]) and \(names.count - 2) more are running low."
            }
            return Reminder(id: "low-\(day)", day: day, hour: data.settings.reminderHour, minute: 0, title: "Time to restock", body: body, repeatsWeekly: false)
        }
        if let wd = data.settings.shopDay {
            let parts = (data.settings.shopTime ?? "10:00").split(separator: ":").compactMap { Int($0) }
            var d = today; while d.weekday != wd { d = d.adding(days: 1) }
            out.append(Reminder(id: "shopping-day", day: d, hour: parts.first ?? 10, minute: parts.count > 1 ? parts[1] : 0, title: "Grocery run", body: "Open Restock to see what to buy.", repeatsWeekly: true))
        }
        return out
    }
}
