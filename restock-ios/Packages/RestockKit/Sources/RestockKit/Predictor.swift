import Foundation

public enum StockStatus: String, Sendable { case overdue, soon, ok, unknown }
public enum IntervalSource: String, Sendable { case learned, set }

public struct Prediction: Hashable, Sendable {
    public var last: Day?
    public var lastPurchase: Purchase?
    /// Days between buys in use (set by the user, or learned).
    public var interval: Double?
    /// The learned interval, when there are 2+ purchase days.
    public var learned: Double?
    public var source: IntervalSource?
    public var due: Day?
    public var daysLeft: Int?
    public var status: StockStatus
    /// Distinct purchase days.
    public var count: Int
}

public enum Predictor {
    static func median(_ a: [Double]) -> Double {
        let s = a.sorted(); let m = s.count / 2
        return s.count % 2 == 1 ? s[m] : (s[m - 1] + s[m]) / 2
    }

    /// After two purchases, the median gap between purchase days becomes the interval.
    /// Next due = last purchase (or the day it was marked Restocked) + interval.
    public static func predict(_ item: Item, today: Day, soonDays: Int) -> Prediction {
        let days = Array(Set(item.purchases.map(\.date))).sorted()
        let last = days.last
        var gaps: [Double] = []
        if days.count > 1 { for i in 1..<days.count { gaps.append(Double(days[i - 1].days(until: days[i]))) } }
        let learned = gaps.isEmpty ? nil : median(gaps)
        let interval = item.intervalDays.map(Double.init) ?? learned
        let source: IntervalSource? = item.intervalDays != nil ? .set : (learned != nil ? .learned : nil)
        var anchor = last
        if let s = item.stockedOn, last == nil || s > last! { anchor = s }
        var due: Day? = nil
        if let anchor, let interval { due = anchor.adding(days: max(1, Int(interval.rounded()))) }
        var status: StockStatus = .unknown
        var daysLeft: Int? = nil
        if let due {
            let left = today.days(until: due)
            daysLeft = left
            let snoozed = item.snoozeUntil.map { $0 > today } ?? false
            status = snoozed ? .ok : left < 0 ? .overdue : left <= soonDays ? .soon : .ok
        }
        if item.level == .out && status != .overdue { status = .soon }
        if item.level == .stocked && status == .unknown { status = .ok }
        let lastPurchase = item.purchases.last { $0.date == last }
        return Prediction(last: last, lastPurchase: lastPurchase, interval: interval, learned: learned, source: source, due: due, daysLeft: daysLeft, status: status, count: days.count)
    }

    /// Where the Restocked / Used / Buy soon control sits: the user's choice, else the prediction.
    public static func displayLevel(_ item: Item, _ p: Prediction) -> StockLevel {
        if let l = item.level { return l }
        if item.onList || p.status == .overdue || p.status == .soon { return .out }
        if let i = p.interval, let left = p.daysLeft, Double(left) >= i * 0.75 { return .stocked }
        return .used
    }

    public static func statusLabel(_ item: Item, _ p: Prediction, soonDays: Int) -> String {
        if item.onList { return "on list" }
        switch p.status {
        case .overdue: return p.daysLeft == 0 ? "due today" : "\(-(p.daysLeft ?? 0))d overdue"
        case .soon:
            if p.daysLeft == nil || (item.level == .out && (p.daysLeft ?? 0) > soonDays) { return "buy soon" }
            return "due " + relative(p.daysLeft!)
        case .ok: return p.due != nil ? "due " + relative(p.daysLeft!) : "stocked"
        case .unknown: return p.count == 1 ? "learning" : "new"
        }
    }

    public static func relative(_ n: Int) -> String {
        switch n { case 0: return "today"; case 1: return "tomorrow"; case -1: return "yesterday"; default: return n > 0 ? "in \(n) days" : "\(-n) days ago" }
    }

    public static func everyText(_ n: Double?) -> String {
        guard let n else { return "" }
        let r = Int(n.rounded())
        if r % 7 == 0 && r >= 14 { return "every \(r / 7) weeks" }
        if r == 7 { return "weekly" }
        return "every \(r) days"
    }
}
