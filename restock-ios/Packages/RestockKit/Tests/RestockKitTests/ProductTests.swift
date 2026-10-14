import XCTest
@testable import RestockKit

struct MockTransport: HTTPTransport {
    let handler: @Sendable (URL) throws -> (Data, Int)
    func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int) { try handler(url) }
}
func json(_ obj: Any) -> Data { try! JSONSerialization.data(withJSONObject: obj) }
let yogurtHit: [String: Any] = ["code": "0894700010137", "product_name": "Greek Nonfat Yogurt Plain", "brands": ["Trader Joe's"], "quantity": "32 oz", "nutriscore_grade": "a", "nutriments": ["energy-kcal_100g": 65, "proteins_100g": "10.3", "fat_100g": 0]]
let syrupHit: [String: Any] = ["code": "1", "product_name": "Pancake Syrup 1 gal", "brands": "Generic", "nutriscore_grade": "e", "nutriments": ["energy_100g": 1088]]

final class ProductTests: XCTestCase {
    func testQueryCleaningAndStoreBrands() {
        XCTAssertEqual(OpenFoodFacts.cleanQuery("ORG WHOLE MILK 1 GAL"), "organic whole milk")
        XCTAssertEqual(OpenFoodFacts.cleanQuery("Coffee Beans 12oz"), "coffee beans")
        XCTAssertEqual(OpenFoodFacts.cleanQuery("KS BNLS SKNLS CHKN"), "boneless skinless chicken")
        XCTAssertEqual(OpenFoodFacts.storeBrand("Trader Joe's"), "Trader Joe's")
        XCTAssertEqual(OpenFoodFacts.storeBrand("COSTCO WHOLESALE"), "Kirkland Signature")
        XCTAssertNil(OpenFoodFacts.storeBrand("Corner shop"))
    }

    func testParsesProductsWithMixedTypes() throws {
        let p = try XCTUnwrap(OpenFoodFacts.product(from: yogurtHit))
        XCTAssertEqual(p.brand, "Trader Joe's"); XCTAssertEqual(p.grade, "a"); XCTAssertEqual(p.nutrition.protein, 10.3); XCTAssertEqual(p.nutrition.kcal, 65)
        let s = try XCTUnwrap(OpenFoodFacts.product(from: syrupHit))
        XCTAssertEqual(s.nutrition.kcal ?? 0, 260, accuracy: 0.1, "kJ is converted to kcal")
        XCTAssertNil(OpenFoodFacts.product(from: ["code": "2"]), "products without a name are skipped")
    }

    func testRankingPrefersNameAndStoreBrand() {
        let products = [OpenFoodFacts.product(from: syrupHit)!, OpenFoodFacts.product(from: yogurtHit)!]
        let ranked = OpenFoodFacts.rank("GREEK YOGURT", brand: "Trader Joe's", products: products)
        XCTAssertEqual(ranked.first?.product.name, "Greek Nonfat Yogurt Plain")
        XCTAssertGreaterThan(ranked.first!.score, 0.75)
    }

    func testSearchesBrandFirstThenSuggests() async throws {
        let seen = Seen()
        let off = OpenFoodFacts(transport: MockTransport { url in
            seen.add(URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "search_terms" }!.value!)
            return (json(["products": [yogurtHit, syrupHit]]), 200)
        }, searchGap: 0, retryDelay: 0)
        let p = try await off.suggestion(for: "GREEK YOGURT", store: "Trader Joe's")
        XCTAssertEqual(p?.code, "0894700010137")
        XCTAssertEqual(seen.values, ["greek yogurt Trader Joe's"], "a confident brand match needs no second search")
        let none = try await off.suggestion(for: "Birthday candles", store: nil)
        XCTAssertNil(none, "weak matches are not suggested")
    }

    func testErrorsAndBarcode() async {
        let offline = OpenFoodFacts(transport: MockTransport { _ in throw URLError(.notConnectedToInternet) }, searchGap: 0, retryDelay: 0)
        do { _ = try await offline.candidates(for: "milk", store: nil); XCTFail() } catch { XCTAssertEqual(error as? ProductLookupError, .offline) }
        let busy = OpenFoodFacts(transport: MockTransport { _ in (Data("<html>503</html>".utf8), 503) }, searchGap: 0, retryDelay: 0)
        do { _ = try await busy.candidates(for: "milk", store: nil); XCTFail() } catch { XCTAssertEqual(error as? ProductLookupError, .busy) }
        let barcode = OpenFoodFacts(transport: MockTransport { url in
            XCTAssertTrue(url.path.hasSuffix("/api/v2/product/0894700010137.json"))
            return (json(["product": yogurtHit.filter { $0.key != "code" }]), 200)
        }, searchGap: 0, retryDelay: 0)
        let p = try? await barcode.product(barcode: "0 89470 00101 37")
        XCTAssertEqual(p?.code, "0894700010137"); XCTAssertEqual(p?.name, "Greek Nonfat Yogurt Plain")
    }

    func testRateLimiterSpacesCalls() async {
        let limiter = RateLimiter(gap: 0.2)
        let start = Date()
        for _ in 0..<3 { await limiter.wait() }
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(start), 0.38)
    }
}

final class Seen: @unchecked Sendable {
    private let lock = NSLock(); private var v: [String] = []
    func add(_ s: String) { lock.lock(); v.append(s); lock.unlock() }
    var values: [String] { lock.lock(); defer { lock.unlock() }; return v }
}
