import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol HTTPTransport: Sendable {
    func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int)
}

public struct URLSessionTransport: HTTPTransport {
    public init() {}
    public func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int) {
        var req = URLRequest(url: url, timeoutInterval: 15)
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        return try await withCheckedThrowingContinuation { cont in
            URLSession.shared.dataTask(with: req) { data, resp, err in
                if let err { cont.resume(throwing: err) } else { cont.resume(returning: (data ?? Data(), (resp as? HTTPURLResponse)?.statusCode ?? 0)) }
            }.resume()
        }
    }
}

/// Spaces requests out. A slot is reserved before sleeping, so concurrent callers queue up in order.
public actor RateLimiter {
    private var next = Date.distantPast
    private let gap: TimeInterval
    public init(gap: TimeInterval) { self.gap = gap }
    public func wait() async {
        let now = Date()
        let slot = max(now, next)
        next = slot.addingTimeInterval(gap)
        let delay = slot.timeIntervalSince(now)
        if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
    }
}

public enum ProductLookupError: Error, Equatable { case offline, busy }

public struct RankedProduct: Sendable { public var product: Product; public var score: Double }

/// Finds products and nutrition facts in Open Food Facts (https://world.openfoodfacts.org),
/// a free database under the Open Database License. The app credits it wherever its data is shown.
public final class OpenFoodFacts: Sendable {
    public static let shared = OpenFoodFacts()

    let transport: HTTPTransport
    /// Open Food Facts asks apps to keep full-text searches to about 10 a minute.
    let searchLimiter: RateLimiter
    let retryDelay: TimeInterval
    static let fields = "code,product_name,brands,quantity,image_front_small_url,nutriscore_grade,serving_size,nutriments"
    static let headers = ["User-Agent": "Restock/1.0 (iOS; https://github.com/edgar2-1/Repo)"]

    public init(transport: HTTPTransport = URLSessionTransport(), searchGap: TimeInterval = 6.5, retryDelay: TimeInterval = 4) {
        self.transport = transport; self.searchLimiter = RateLimiter(gap: searchGap); self.retryDelay = retryDelay
    }

    // MARK: query building

    static let storeBrands: [(String, String)] = [("trader joe", "Trader Joe's"), ("costco", "Kirkland Signature"), ("walmart", "Great Value"), ("target", "Good & Gather"), ("whole foods", "365"), ("safeway", "Signature Select"), ("kroger", "Kroger"), ("aldi", "Simply Nature"), ("publix", "Publix"), ("wegmans", "Wegmans"), ("heb", "H-E-B"), ("h e b", "H-E-B"), ("albertsons", "Signature Select"), ("sprouts", "Sprouts")]
    static let abbreviations: [String: String] = ["org": "organic", "orgnc": "organic", "whl": "whole", "bnls": "boneless", "sknls": "skinless", "chkn": "chicken", "brd": "bread", "grk": "greek", "ygrt": "yogurt", "yog": "yogurt", "crm": "cream", "chs": "cheese", "bnna": "banana", "bnns": "bananas", "veg": "vegetable", "ff": "fat free", "lf": "low fat", "choc": "chocolate", "pb": "peanut butter", "oj": "orange juice", "sprkl": "sparkling", "wtr": "water", "tj": "", "tjs": "", "ks": "", "gv": ""]

    /// The house brand of a store, used to search its own products first.
    public static func storeBrand(_ store: String?) -> String? {
        let n = Words.norm(store)
        guard !n.isEmpty else { return nil }
        return storeBrands.first { n.contains(Words.norm($0.0)) }?.1
    }

    /// "ORG WHOLE MILK 1 GAL" -> "organic whole milk"
    public static func cleanQuery(_ name: String) -> String {
        var q = Words.norm(name).split(separator: " ").map { abbreviations[String($0)] ?? String($0) }.joined(separator: " ")
        q = RX("\\b\\d+(\\.\\d+)?\\s*(oz|fl oz|lb|lbs|g|kg|ml|l|gal|gallon|ct|pk|pack|dozen|dz|ea|each|count)\\b").replace(q, with: " ")
        q = RX("\\b(gal|gallon|dozen|dz|ct|pk|oz|lb|lbs|ea|each|large|small|medium|lrg|sml|med|pack)\\b").replace(q, with: " ")
        q = RX("\\b\\d+\\b").replace(q, with: " ")
        return q.split(separator: " ").prefix(5).joined(separator: " ")
    }

    // MARK: parsing

    static func number(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String { return Double(s) }
        return nil
    }

    static func product(from h: [String: Any]) -> Product? {
        guard let rawName = h["product_name"] as? String, !rawName.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let n = h["nutriments"] as? [String: Any] ?? [:]
        var kcal = number(n["energy-kcal_100g"])
        if kcal == nil, let kj = number(n["energy_100g"]) { kcal = kj / 4.184 }
        let brands: String = (h["brands"] as? String) ?? ((h["brands"] as? [String])?.joined(separator: ", ") ?? "")
        let grade = (h["nutriscore_grade"] as? String) ?? ""
        let code: String = (h["code"] as? String) ?? (number(h["code"]).map { String(Int($0)) } ?? "")
        return Product(code: code, name: rawName.trimmingCharacters(in: .whitespaces),
                       brand: brands.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? "",
                       qty: h["quantity"] as? String ?? "", image: h["image_front_small_url"] as? String ?? "",
                       grade: ["a", "b", "c", "d", "e"].contains(grade) ? grade : "", serving: h["serving_size"] as? String ?? "",
                       nutrition: Nutrition(kcal: kcal, fat: number(n["fat_100g"]), sat: number(n["saturated-fat_100g"]), carbs: number(n["carbohydrates_100g"]),
                                            sugars: number(n["sugars_100g"]), fiber: number(n["fiber_100g"]), protein: number(n["proteins_100g"]), salt: number(n["salt_100g"])))
    }

    /// Scores candidates by word overlap with the item name, store brand and whether nutrition is present.
    public static func rank(_ name: String, brand: String?, products: [Product]) -> [RankedProduct] {
        let qt = cleanQuery(name).split(separator: " ").map(String.init).filter { $0.count > 2 }
        let brandWord = brand.flatMap { Words.norm($0).split(separator: " ").first.map(String.init) }
        return products.map { p in
            let pt = Words.norm(p.name).split(separator: " ").map(String.init)
            let overlap = qt.isEmpty ? 0 : Double(qt.filter { w in pt.contains { Words.tokenMatch($0, w) } }.count) / Double(qt.count)
            let brandHit = (brandWord.map { Words.norm(p.brand).contains($0) } ?? false) ? 0.25 : 0
            let hasNutrition = p.nutrition.kcal != nil ? 0.15 : 0
            let extra = Double(max(0, pt.count - qt.count - 2)) * 0.03
            return RankedProduct(product: p, score: overlap * 0.7 + brandHit + hasNutrition + (p.grade.isEmpty ? 0 : 0.05) - extra)
        }.sorted { $0.score > $1.score }
    }

    // MARK: network

    func fetchJSON(_ url: URL, tries: Int = 3) async throws -> [String: Any] {
        var sawNetworkError = false
        for attempt in 0..<tries {
            do {
                let (data, status) = try await transport.get(url, headers: Self.headers)
                if status == 200, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { return obj }
            } catch { sawNetworkError = true }
            if attempt < tries - 1 { try? await Task.sleep(nanoseconds: UInt64(retryDelay * Double(attempt + 1) * 1_000_000_000)) }
        }
        throw sawNetworkError ? ProductLookupError.offline : ProductLookupError.busy
    }

    func searchURL(_ q: String) -> URL {
        var c = URLComponents(string: "https://world.openfoodfacts.org/cgi/search.pl")!
        c.queryItems = [.init(name: "search_terms", value: q), .init(name: "search_simple", value: "1"), .init(name: "action", value: "process"), .init(name: "json", value: "1"), .init(name: "page_size", value: "12"), .init(name: "fields", value: Self.fields)]
        return c.url!
    }

    func search(_ q: String) async throws -> [Product] {
        await searchLimiter.wait()
        let obj = try await fetchJSON(searchURL(q))
        return (obj["products"] as? [[String: Any]] ?? []).compactMap(Self.product(from:))
    }

    /// Best matches for an item, searching the store's own brand first.
    public func candidates(for name: String, store: String?) async throws -> [RankedProduct] {
        let base = Self.cleanQuery(name)
        guard !base.isEmpty else { return [] }
        let brand = Self.storeBrand(store)
        var ranked: [RankedProduct] = []
        if let brand { ranked = Self.rank(name, brand: brand, products: try await search(base + " " + brand)) }
        if ranked.first.map({ $0.score < 0.75 }) ?? true {
            let seen = Set(ranked.map(\.product.code))
            ranked += Self.rank(name, brand: brand, products: try await search(base)).filter { !seen.contains($0.product.code) }
            ranked.sort { $0.score > $1.score }
        }
        return ranked
    }

    /// The single best match when it is confident enough to suggest.
    public func suggestion(for name: String, store: String?) async throws -> Product? {
        guard let best = try await candidates(for: name, store: store).first, best.score >= 0.6 else { return nil }
        return best.product
    }

    /// Exact product by barcode (EAN/UPC).
    public func product(barcode: String) async throws -> Product? {
        let digits = barcode.filter(\.isNumber)
        guard !digits.isEmpty, let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(digits).json?fields=\(Self.fields)") else { return nil }
        let obj = try await fetchJSON(url, tries: 2)
        guard var p = obj["product"] as? [String: Any] else { return nil }
        if p["code"] == nil { p["code"] = digits }
        return Self.product(from: p)
    }
}
