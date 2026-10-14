import Foundation

public enum Matching {
    /// How well a receipt line name matches a pantry item, 0…1.
    public static func score(_ receiptName: String, _ item: Item) -> Double {
        let r = Words.norm(receiptName), n = Words.norm(item.name)
        if r.isEmpty || n.isEmpty { return 0 }
        if r == n { return 1 }
        if item.aliases.contains(where: { Words.norm($0) == r }) { return 1 }
        let rt = r.split(separator: " ").map(String.init), nt = n.split(separator: " ").map(String.init)
        let hits = nt.filter { t in rt.contains { Words.tokenMatch($0, t) } }.count
        let hits2 = rt.filter { t in nt.contains { Words.tokenMatch($0, t) } }.count
        let s = max(Double(hits) / Double(nt.count), Double(hits2) / Double(rt.count)) * 0.9
        return (r.contains(n) || n.contains(r)) ? max(s, 0.8) : s
    }

    public static func best(_ name: String, in items: [Item]) -> [(item: Item, score: Double)] {
        items.map { ($0, score(name, $0)) }.filter { $0.1 >= 0.5 }.sorted { $0.1 > $1.1 }
    }
}

public struct QuickAddEntry: Hashable, Sendable { public var name: String; public var qty: Int }

public enum QuickAdd {
    static let leading = RX("^(\\d{1,2})\\s*(?:x|×)?\\s+(.+)$", ignoreCase: true)
    static let trailing = RX("^(.+?)\\s+(?:x|×)\\s*(\\d{1,2})$", ignoreCase: true)

    /// "2 oat milk, eggs, limes x3" -> oat milk ×2, eggs ×1, limes ×3
    public static func parse(_ text: String) -> [QuickAddEntry] {
        text.components(separatedBy: CharacterSet(charactersIn: ",;\n")).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.compactMap { s in
            if let m = leading.first(in: s) { return QuickAddEntry(name: m[2]!.trimmingCharacters(in: .whitespaces), qty: Int(m[1]!)!) }
            if let m = trailing.first(in: s) { return QuickAddEntry(name: m[1]!.trimmingCharacters(in: .whitespaces), qty: Int(m[2]!)!) }
            return QuickAddEntry(name: s, qty: 1)
        }.filter { !$0.name.isEmpty }
    }

    /// The existing item a typed name refers to: exact name or alias, or the only item that
    /// contains every typed word with at most one extra ("eggs" -> "Eggs, dozen").
    public static func existing(_ name: String, in items: [Item]) -> Item? {
        let n = Words.norm(name)
        if let exact = items.first(where: { Words.norm($0.name) == n || $0.aliases.contains { Words.norm($0) == n } }) { return exact }
        let words = n.split(separator: " ").map(String.init)
        let close = items.filter { it in
            let iw = Words.norm(it.name).split(separator: " ").map(String.init)
            return words.allSatisfy { w in iw.contains { Words.tokenMatch($0, w) } } && iw.count - words.count <= 1
        }
        return close.count == 1 ? close[0] : nil
    }
}
