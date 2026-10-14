import Foundation

public struct ParsedReceiptItem: Hashable, Sendable {
    public var name: String
    public var qty: Int
    /// Line total.
    public var price: Double
    /// Indexes of the source lines in the text (name line, price line), for highlighting.
    public var sourceLines: [Int]
}

public struct ParsedReceipt: Hashable, Sendable {
    public var store: String?
    public var date: Day?
    public var total: Double?
    public var items: [ParsedReceiptItem]
}

/// Turns OCR text from a grocery receipt into items, store, date and total.
/// Port of the web app's parser; both are covered by the same test receipts.
public enum ReceiptParser {
    static let skip = RX("\\b(sub\\s?total|total|tax|change|cash|visa|master\\s?card|mastercard|m/c|amex|discover|debit|credit|balance|tender|amount|approved|approval|auth|thank|cashier|register|reg\\b|trans|terminal|card|account|acct|savings|you saved|saved|coupon|discount|loyalty|points|member|rewards|www\\.|http|\\.com|invoice|order|receipt|date|time|phone|tel\\b|items?\\s+sold|item count|count|qty|price|description|store|ref|chip|contactless|signature|customer copy|merchant|entry|aid|tvr|tsi|arqc|return policy|survey|welcome|open|hours)\\b", ignoreCase: true)
    static let price = RX("(?:^|\\s)(-?)\\$?\\s?(\\d{1,4})[.,](\\d{2})\\s*(?:[A-Z]{1,2}|\\*|-)?\\s*$")
    static let qtyLine = RX("^(\\d{1,3})\\s*(?:@|x)\\s*\\$?(\\d+[.,]\\d{2})(?:\\s*(?:/|ea|each)\\s*\\w*)?$", ignoreCase: true)
    static let lastToken = RX("(\\S+)\\s*([A-Z]{0,2})$")
    static let totalWord = RX("\\btotal\\b", ignoreCase: true)
    static let sub = RX("sub", ignoreCase: true)
    static let leadQty = RX("^(\\d{1,2})\\s*(?:x|@|ea)?\\s+(?=[A-Za-z])", ignoreCase: true)
    static let atQty = RX("(\\d{1,2})\\s*(?:@|x)\\s*\\$?\\d+[.,]\\d{2}", ignoreCase: true)
    static let weight = RX("(\\d+(?:\\.\\d+)?)\\s*(lb|kg|oz|g)\\b\\s*(@\\s*\\$?\\d+[.,]\\d{2}\\s*(?:/\\s*\\w+)?)?", ignoreCase: true)
    static let storeChars = RX("[^A-Za-z0-9&' .-]")
    static let isoDate = RX("\\b(20\\d{2})[-/.](\\d{1,2})[-/.](\\d{1,2})\\b")
    static let usDate = RX("\\b(\\d{1,2})[/\\-.](\\d{1,2})[/\\-.](\\d{2,4})\\b")

    /// OCR confuses O/0, l/1, S/5 and B/8 inside the trailing price token only.
    static func fixPriceToken(_ line: String) -> String {
        guard let m = lastToken.first(in: line), let tok = m[1] else { return line }
        let code = m[2] ?? ""
        guard tok.contains(where: \.isNumber), tok.contains(where: { $0 == "." || $0 == "," }) else { return line }
        var fixed = ""
        for ch in tok {
            switch ch {
            case "O", "o": fixed.append("0")
            case "I", "l", "|": fixed.append("1")
            case "S": fixed.append("5")
            case "B": fixed.append("8")
            default: fixed.append(ch)
            }
        }
        var out = line
        out.replaceSubrange(m.range, with: fixed + (code.isEmpty ? "" : " " + code))
        return out
    }

    public static func parseDate(_ text: String, today: Day) -> Day? {
        func valid(_ d: Day?) -> Day? { guard let d, d <= today, d.days(until: today) < 1100 else { return nil }; return d }
        for m in isoDate.all(in: text) {
            if let d = valid(Day(year: Int(m[1]!)!, month: Int(m[2]!)!, day: Int(m[3]!)!)) { return d }
        }
        for m in usDate.all(in: text) {
            let a = Int(m[1]!)!, b = Int(m[2]!)!
            var y = Int(m[3]!)!; if y < 100 { y += 2000 }
            var mo = a, da = b
            if a > 12 && b <= 12 { mo = b; da = a }
            if let d = valid(Day(year: y, month: mo, day: da)) { return d }
        }
        return nil
    }

    public static func parse(_ text: String, today: Day = .today()) -> ParsedReceipt {
        let lines: [(t: String, i: Int)] = text.components(separatedBy: .newlines).enumerated().compactMap { i, raw in
            let t = raw.replacingOccurrences(of: "|", with: " ").replacingOccurrences(of: "¦", with: " ")
                .components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
            return t.count > 1 ? (t, i) : nil
        }
        var items: [ParsedReceiptItem] = []
        var store: String? = nil
        var total: Double? = nil
        var pendingName: (name: String, src: Int)? = nil
        var pendingQty: (q: Int, unit: Double)? = nil
        func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) <= 0.02 }
        func letters(_ s: String) -> Int { s.filter { $0.isASCII && $0.isLetter }.count }

        for (raw, src) in lines {
            let line = fixPriceToken(raw)
            // "2 @ 3.49" belongs to the neighbouring item whose line total matches
            if let ql = qtyLine.first(in: line) {
                let q = Int(ql[1]!)!, unit = Double(ql[2]!.replacingOccurrences(of: ",", with: "."))!
                if let last = items.indices.last, items[last].qty == 1, near(items[last].price, Double(q) * unit) { items[last].qty = q }
                else { pendingQty = (q, unit) }
                pendingName = nil
                continue
            }
            guard let m = price.first(in: line) else {
                if skip.test(line) { pendingName = nil; continue }
                let l = letters(line)
                if store == nil, items.isEmpty, l >= 3, Double(l) >= Double(line.count) * 0.5, line.count <= 40 {
                    store = Words.titleCase(storeChars.replace(line, with: "").trimmingCharacters(in: .whitespaces))
                    continue
                }
                pendingName = l >= 3 ? (line, src) : nil
                continue
            }
            let negative = m[1] == "-"
            let amount = Double("\(m[2]!).\(m[3]!)")!
            var name = String(line[..<m.range.lowerBound]).trimmingCharacters(in: .whitespaces)
            var nameSrc = src
            if totalWord.test(name) && !sub.test(name) { total = amount; pendingName = nil; continue }
            if name.isEmpty {
                guard let p = pendingName else { continue }
                name = p.name; nameSrc = p.src
            }
            pendingName = nil
            if negative || amount <= 0 || skip.test(name) { continue }
            var qty = 1
            if let q1 = leadQty.first(in: name) { qty = Int(q1[1]!)!; name = String(name[q1.range.upperBound...]) }
            if let q2 = atQty.first(in: name) { qty = Int(q2[1]!)!; name.replaceSubrange(q2.range, with: "") }
            if let w = weight.first(in: name), w[3] != nil { name.replaceSubrange(w.range, with: "") }
            name = RX("^\\d{4,}\\s*").replace(name, with: "")
            name = RX("\\s\\d{4,}$").replace(name, with: "")
            name = RX("[*#~_=]+").replace(name, with: " ")
            name = name.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
            if letters(name) < 2 { continue }
            if let pq = pendingQty { if qty == 1 && near(amount, Double(pq.q) * pq.unit) { qty = pq.q }; pendingQty = nil }
            items.append(ParsedReceiptItem(name: Words.titleCase(name), qty: qty, price: amount, sourceLines: [nameSrc, src]))
        }
        return ParsedReceipt(store: store, date: parseDate(text, today: today), total: total, items: items)
    }
}
