import Foundation

/// Small wrapper over NSRegularExpression (works the same on iOS and Linux).
struct RX {
    let re: NSRegularExpression
    init(_ pattern: String, ignoreCase: Bool = false) {
        re = try! NSRegularExpression(pattern: pattern, options: ignoreCase ? [.caseInsensitive] : [])
    }
    struct Match {
        let range: Range<String.Index>
        let groups: [String?]
        subscript(i: Int) -> String? { i < groups.count ? groups[i] : nil }
    }
    func first(in s: String) -> Match? {
        guard let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return Self.convert(m, s)
    }
    func all(in s: String) -> [Match] {
        re.matches(in: s, range: NSRange(s.startIndex..., in: s)).map { Self.convert($0, s) }
    }
    func test(_ s: String) -> Bool { first(in: s) != nil }
    func replace(_ s: String, with template: String) -> String {
        re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
    }
    private static func convert(_ m: NSTextCheckingResult, _ s: String) -> Match {
        var groups: [String?] = []
        for i in 0..<m.numberOfRanges {
            let r = m.range(at: i)
            if r.location == NSNotFound { groups.append(nil) } else { groups.append(Range(r, in: s).map { String(s[$0]) }) }
        }
        return Match(range: Range(m.range, in: s)!, groups: groups)
    }
}

public enum Words {
    private static let nonAlnum = RX("[^a-z0-9 ]+")
    private static let spaces = RX("\\s+")

    /// Lowercase, letters and digits only, single spaces.
    public static func norm(_ s: String?) -> String {
        guard let s else { return "" }
        let lowered = nonAlnum.replace(s.lowercased(), with: " ")
        return spaces.replace(lowered, with: " ").trimmingCharacters(in: .whitespaces)
    }

    /// "ORGANIC BANANAS" -> "Organic Bananas", keeping small joining words lowercase.
    public static func titleCase(_ s: String) -> String {
        var out = ""
        var prev: Character? = nil
        for ch in s.lowercased() {
            if ch.isLetter, ch.isASCII, prev == nil || prev!.isWhitespace || "(/-".contains(prev!) { out.append(contentsOf: ch.uppercased()) } else { out.append(ch) }
            prev = ch
        }
        return RX("\\b(And|Of|With|In)\\b").all(in: out).reversed().reduce(out) { acc, m in
            var a = acc; a.replaceSubrange(m.range, with: a[m.range].lowercased()); return a
        }
    }

    /// Same word, or one is a prefix of the other when both have 3+ letters ("org" ~ "organic").
    public static func tokenMatch(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        if a.count >= 3 && b.count >= 3 { return a.hasPrefix(b) || b.hasPrefix(a) }
        return false
    }
}

public enum Categories {
    public static let all = ["Produce", "Dairy & eggs", "Meat & fish", "Bakery", "Pantry", "Frozen", "Drinks", "Snacks", "Household", "Personal care", "Pets & baby", "Other"]

    static let words: [(String, [String])] = [
        ("Produce", ["banana","apple","orange","lemon","lime","avocado","tomato","onion","garlic","potato","carrot","lettuce","spinach","kale","pepper","cucumber","berry","berries","strawberr","grape","melon","broccoli","celery","mushroom","salad","herb","cilantro","parsley","ginger","pear","peach","plum","mango","squash","zucchini","corn","beans","cabbage"]),
        ("Dairy & eggs", ["milk","egg","cheese","yogurt","yoghurt","butter","cream","cheddar","mozzarella","parmesan","kefir","cottage"]),
        ("Meat & fish", ["chicken","beef","pork","turkey","salmon","tuna","shrimp","fish","steak","bacon","sausage","ham","ground","lamb","deli"]),
        ("Bakery", ["bread","bagel","tortilla","bun","roll","muffin","croissant","pita","naan","loaf","baguette"]),
        ("Pantry", ["rice","pasta","flour","sugar","oil","olive","vinegar","salt","spice","cereal","oat","granola","honey","peanut","jam","sauce","soup","broth","stock","can ","canned","lentil","chickpea","quinoa","noodle","ketchup","mustard","mayo","syrup","coffee","tea ","cocoa","baking","vanilla","nut","almond","walnut"]),
        ("Frozen", ["frozen","ice cream","pizza","frz","fzn","popsicle"]),
        ("Drinks", ["water","juice","soda","cola","beer","wine","kombucha","sparkling","seltzer","drink","lemonade"]),
        ("Snacks", ["chip","cracker","cookie","chocolate","candy","pretzel","popcorn","bar ","bars","snack","trail mix"]),
        ("Household", ["paper towel","toilet","tissue","detergent","soap","sponge","trash","bag","foil","wrap","cleaner","bleach","dish","laundry","battery","bulb","napkin"]),
        ("Personal care", ["shampoo","conditioner","toothpaste","toothbrush","deodorant","razor","lotion","floss","sunscreen","vitamin","tampon","pad"]),
        ("Pets & baby", ["dog","cat ","litter","diaper","wipes","formula","kibble","pet"]),
    ]

    /// Phrases checked before the keyword lists, so "coffee beans" isn't produce and "frozen peas" isn't fresh.
    static let overrides: [(String, String)] = [("frozen", "Frozen"), ("ice cream", "Frozen"), ("coffee", "Pantry"), ("peanut butter", "Pantry"), ("olive oil", "Pantry"), ("dog food", "Pets & baby"), ("cat food", "Pets & baby"), ("baby food", "Pets & baby")]

    public static func guess(_ name: String) -> String {
        let n = " " + Words.norm(name) + " "
        if let o = overrides.first(where: { n.contains($0.0) }) { return o.1 }
        for (cat, ws) in words where ws.contains(where: { n.contains($0) }) { return cat }
        return "Other"
    }
}
