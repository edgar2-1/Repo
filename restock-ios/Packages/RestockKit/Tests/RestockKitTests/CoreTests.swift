import XCTest
@testable import RestockKit

let today = Day("2026-10-13")!
func d(_ s: String) -> Day { Day(s)! }
func item(_ name: String, every: Int, purchases n: Int, lastDaysAgo: Int, price: Double? = nil, store: String = "") -> Item {
    var ps: [Purchase] = []
    var day = today.adding(days: -lastDaysAgo)
    for _ in 0..<n { ps.insert(Purchase(date: day, price: price, store: store), at: 0); day = day.adding(days: -every) }
    return Item(name: name, category: Categories.guess(name), purchases: ps)
}

final class DayTests: XCTestCase {
    func testParsingAndArithmetic() {
        XCTAssertEqual(d("2026-10-13").description, "2026-10-13")
        XCTAssertNil(Day("2026-02-30")); XCTAssertNil(Day("2026-13-01")); XCTAssertNil(Day("nonsense"))
        XCTAssertEqual(d("2026-10-13").adding(days: 20), d("2026-11-02"))
        XCTAssertEqual(d("2026-03-07").adding(days: 2), d("2026-03-09"), "daylight saving must not shift days")
        XCTAssertEqual(d("2026-10-01").days(until: d("2026-10-13")), 12)
        XCTAssertEqual(d("2026-10-17").weekday, 6, "Oct 17 2026 is a Saturday")
        XCTAssertTrue(d("2026-01-31") < d("2026-02-01"))
    }
    func testCodable() throws {
        let data = try JSONEncoder().encode([d("2026-10-13")])
        XCTAssertEqual(String(data: data, encoding: .utf8), "[\"2026-10-13\"]")
        XCTAssertEqual(try JSONDecoder().decode([Day].self, from: data), [d("2026-10-13")])
    }
}

final class ReceiptParserTests: XCTestCase {
    // What OCR returned for the sample receipt in the web app.
    let sample = """
    TRADER JOE'S

    1234 MARKET ST

    SAN FRANCISCO CA

    (415) 555-0100
    ORGANIC BANANAS          1.49
    WHOLE MILK 1 GAL         3.99
    LARGE EGGS DOZEN         4.49
    SOURDOUGH BREAD          4.99
    2 @ 3.49
    BABY SPINACH             6.98
    GREEK YOGURT             5.49
    COFFEE BEANS 1202       12.99
    SUBTOTAL                40.42
    TAX                      0.00
    TOTAL                   40.42
    VISA                    40.42
    10/09/2026 14:32
    THANK YOU FOR SHOPPING
    """

    func testSampleReceipt() {
        let r = ReceiptParser.parse(sample, today: today)
        XCTAssertEqual(r.store, "Trader Joe's")
        XCTAssertEqual(r.date, d("2026-10-09"))
        XCTAssertEqual(r.total, 40.42)
        XCTAssertEqual(r.items.map(\.name), ["Organic Bananas", "Whole Milk 1 Gal", "Large Eggs Dozen", "Sourdough Bread", "Baby Spinach", "Greek Yogurt", "Coffee Beans"])
        XCTAssertEqual(r.items.first { $0.name == "Baby Spinach" }?.qty, 2, "the '2 @ 3.49' line belongs to spinach")
        XCTAssertEqual(r.items.map(\.price).reduce(0, +), 40.42, accuracy: 0.001)
    }

    func testWeightsCouponsAndOCRMistakes() {
        let text = "SAFEWAY\nSTORE 1234\n04/02/26 5:11 PM\n1 CHICKEN THIGHS 2.31 lb @ 3.79/lb 8.76 F\nCHEDDAR CHEESE 6.49 T\nDISH SOAP 3.79\n2 @ 1.29\nLEMONS 2.58\nCOUPON -1.00\nSUBTOTAL 20.62\nTAX 0.42\nTOTAL 21.O4\nDEBIT 21.04\nCHANGE 0.00"
        let r = ReceiptParser.parse(text, today: today)
        XCTAssertEqual(r.store, "Safeway")
        XCTAssertEqual(r.date, d("2026-04-02"))
        XCTAssertEqual(r.total, 21.04, "the O in 21.O4 is read as a zero")
        XCTAssertEqual(r.items.map(\.name), ["Chicken Thighs", "Cheddar Cheese", "Dish Soap", "Lemons"])
        XCTAssertEqual(r.items.map(\.price), [8.76, 6.49, 3.79, 2.58])
        XCTAssertEqual(r.items.last?.qty, 2)
    }

    func testFutureAndAncientDatesIgnored() {
        XCTAssertNil(ReceiptParser.parseDate("12/31/2027", today: today))
        XCTAssertNil(ReceiptParser.parseDate("01/01/2019", today: today))
        XCTAssertEqual(ReceiptParser.parseDate("2026-09-30", today: today), d("2026-09-30"))
    }
}

final class TextAndMatchingTests: XCTestCase {
    func testNormAndTitleCase() {
        XCTAssertEqual(Words.norm("  Trader Joe's  ORG. Milk!! "), "trader joe s org milk")
        XCTAssertEqual(Words.titleCase("BREAD AND BUTTER (LARGE)"), "Bread and Butter (Large)")
        XCTAssertEqual(Categories.guess("Whole Milk 1 Gal"), "Dairy & eggs")
        XCTAssertEqual(Categories.guess("Paper towels"), "Household")
        XCTAssertEqual(Categories.guess("Widgets"), "Other")
        XCTAssertEqual(Categories.guess("Coffee beans"), "Pantry")
        XCTAssertEqual(Categories.guess("Frozen peas"), "Frozen")
    }
    func testMatching() {
        let items = [Item(name: "Bananas", category: "Produce"), Item(name: "Whole milk", category: "Dairy & eggs", aliases: ["WHL MLK"])]
        XCTAssertEqual(Matching.best("Organic Bananas", in: items).first?.item.name, "Bananas")
        XCTAssertEqual(Matching.best("whl mlk", in: items).first?.score, 1)
        XCTAssertTrue(Matching.best("Dish Soap", in: items).isEmpty)
    }
    func testQuickAdd() {
        XCTAssertEqual(QuickAdd.parse("2 oat milk, eggs; limes x3"), [QuickAddEntry(name: "oat milk", qty: 2), QuickAddEntry(name: "eggs", qty: 1), QuickAddEntry(name: "limes", qty: 3)])
        let items = [Item(name: "Eggs, dozen", category: "Dairy & eggs"), Item(name: "Whole milk", category: "Dairy & eggs"), Item(name: "Oat milk", category: "Dairy & eggs")]
        XCTAssertEqual(QuickAdd.existing("eggs", in: items)?.name, "Eggs, dozen")
        XCTAssertNil(QuickAdd.existing("milk", in: items), "two milks match, so it is ambiguous")
        XCTAssertEqual(QuickAdd.existing("oat milk", in: items)?.name, "Oat milk")
    }
}

final class PredictorTests: XCTestCase {
    func testLearnsIntervalAndFlagsOverdue() {
        let milk = item("Whole milk", every: 7, purchases: 6, lastDaysAgo: 9)
        let p = Predictor.predict(milk, today: today, soonDays: 3)
        XCTAssertEqual(p.interval, 7); XCTAssertEqual(p.source, .learned); XCTAssertEqual(p.count, 6)
        XCTAssertEqual(p.due, today.adding(days: -2)); XCTAssertEqual(p.daysLeft, -2); XCTAssertEqual(p.status, .overdue)
        XCTAssertEqual(Predictor.statusLabel(milk, p, soonDays: 3), "2d overdue")
        XCTAssertEqual(Predictor.displayLevel(milk, p), .out)
    }
    func testSoonOkAndUnknown() {
        XCTAssertEqual(Predictor.predict(item("Eggs", every: 10, purchases: 3, lastDaysAgo: 8), today: today, soonDays: 3).status, .soon)
        XCTAssertEqual(Predictor.predict(item("Oil", every: 60, purchases: 3, lastDaysAgo: 5), today: today, soonDays: 3).status, .ok)
        let once = Predictor.predict(item("Candles", every: 1, purchases: 1, lastDaysAgo: 3), today: today, soonDays: 3)
        XCTAssertEqual(once.status, .unknown); XCTAssertNil(once.interval); XCTAssertEqual(once.count, 1)
    }
    func testUserIntervalRestockAndSnooze() {
        var milk = item("Whole milk", every: 7, purchases: 6, lastDaysAgo: 9)
        milk.intervalDays = 14
        XCTAssertEqual(Predictor.predict(milk, today: today, soonDays: 3).status, .ok)
        milk.intervalDays = nil; milk.stockedOn = today
        let p = Predictor.predict(milk, today: today, soonDays: 3)
        XCTAssertEqual(p.due, today.adding(days: 7), "Restocked restarts the cycle from today")
        var late = item("Bread", every: 7, purchases: 4, lastDaysAgo: 10)
        late.snoozeUntil = today.adding(days: 2)
        XCTAssertEqual(Predictor.predict(late, today: today, soonDays: 3).status, .ok)
        late.snoozeUntil = nil; late.level = .out
        XCTAssertEqual(Predictor.predict(item("x", every: 30, purchases: 3, lastDaysAgo: 1), today: today, soonDays: 3).status, .ok)
        var marked = item("Oil", every: 60, purchases: 3, lastDaysAgo: 5); marked.level = .out
        XCTAssertEqual(Predictor.predict(marked, today: today, soonDays: 3).status, .soon, "Buy soon puts it in Coming up")
    }
    func testEveryText() {
        XCTAssertEqual(Predictor.everyText(7), "weekly"); XCTAssertEqual(Predictor.everyText(14), "every 2 weeks"); XCTAssertEqual(Predictor.everyText(9.5), "every 10 days")
    }
}

final class PantryTests: XCTestCase {
    func sample() -> AppData {
        AppData(items: [
            item("Whole milk", every: 7, purchases: 4, lastDaysAgo: 9, price: 3.99, store: "Trader Joe's"),
            item("Coffee beans", every: 21, purchases: 3, lastDaysAgo: 20, price: 12.99, store: "Costco"),
            item("Olive oil", every: 60, purchases: 2, lastDaysAgo: 5, price: 11.99, store: "Costco"),
        ])
    }

    func testSectionsCartAndTrip() {
        var data = sample()
        var s = data.listSections(today: today)
        XCTAssertEqual(s.now.map(\.name), ["Whole milk"]); XCTAssertEqual(s.soon.map(\.name), ["Coffee beans"])
        let added = data.addToList(QuickAdd.parse("2 oat milk, whole milk"))
        XCTAssertEqual(added, ["Oat milk", "Whole milk"])
        XCTAssertEqual(data.items.first { $0.name == "Oat milk" }?.listQty, 2)
        let milk = data.items.first { $0.name == "Whole milk" }!.id, oat = data.items.first { $0.name == "Oat milk" }!.id
        data.toggleCart(milk); data.toggleCart(oat)
        s = data.listSections(today: today)
        XCTAssertEqual(Set(s.cart.map(\.name)), ["Whole milk", "Oat milk"]); XCTAssertFalse(s.now.contains { $0.inCart })
        XCTAssertEqual(AppData.estimatedLine(data.item(milk)!), 3.99)
        let trip = data.finishTrip(store: "Trader Joe's", date: today, lineTotals: [milk: 4.19, oat: 7.00])
        XCTAssertEqual(trip.total ?? 0, 11.19, accuracy: 0.001); XCTAssertEqual(trip.items.count, 2)
        XCTAssertEqual(data.item(oat)?.purchases.last?.price, 3.5, "line total is split into a unit price")
        XCTAssertEqual(data.item(oat)?.purchases.last?.qty, 2)
        XCTAssertFalse(data.items.contains { $0.inCart || $0.onList })
        XCTAssertEqual(data.item(milk)?.level, .stocked)
        XCTAssertEqual(data.prediction(data.item(milk)!, today: today).due, today.adding(days: 7))
        XCTAssertEqual(data.trips.count, 1)
    }

    func testSaveReceiptLearnsAliasesAndCreatesItems() {
        var data = sample()
        let milk = data.items[0].id
        let trip = data.saveReceipt(store: "Safeway", date: d("2026-10-12"), total: 9.48, lines: [
            .init(name: "WHL MILK GAL", qty: 1, lineTotal: 4.29, category: "Dairy & eggs", itemId: milk),
            .init(name: "Lemons", qty: 2, lineTotal: 2.58, category: "Produce", itemId: nil),
            .init(name: "  ", qty: 1, lineTotal: 1, category: "Other", itemId: nil),
        ])
        XCTAssertEqual(trip.items.count, 2); XCTAssertEqual(trip.source, .receipt)
        XCTAssertEqual(data.item(milk)?.aliases, ["WHL MILK GAL"])
        XCTAssertEqual(data.items.first { $0.name == "Lemons" }?.purchases.first?.price, 1.29)
        XCTAssertEqual(AppData.lastPrice(data.item(milk)!, store: "Trader Joe's"), 3.99)
        XCTAssertEqual(AppData.lastPrice(data.item(milk)!, store: nil), 4.29)
        XCTAssertEqual(AppData.pricesByStore(data.item(milk)!).map(\.store), ["Trader Joe's", "Safeway"])
        XCTAssertEqual(AppData.usualStore(data.item(milk)!), "Trader Joe's")
        XCTAssertEqual(data.knownStores().first, "Costco", "Costco has the most purchases in this data")
    }

    func testLevelSnoozeDeleteAndShareText() {
        var data = sample()
        let coffee = data.items[1].id
        data.setLevel(coffee, .stocked, today: today)
        XCTAssertEqual(data.item(coffee)?.stockedOn, today)
        XCTAssertEqual(data.snooze(data.items[0].id, today: today), 2)
        XCTAssertEqual(data.prediction(data.items[0], today: today).status, .ok)
        _ = data.toggleList(data.items[2].id)
        XCTAssertTrue(data.listText(today: today).contains("Costco\n☐ Olive oil"))
        data.delete(coffee); XCTAssertNil(data.item(coffee))
    }

    func testSpendingAndReminders() {
        var data = sample()
        data.settings.shopDay = 6; data.settings.shopTime = "09:30"
        XCTAssertGreaterThan(data.spent(inMonthOf: today), 0)
        XCTAssertEqual(data.spendByCategory(lastDays: 90, today: today).first?.category, "Pantry")
        let plan = ReminderPlanner.plan(data, today: today)
        XCTAssertTrue(plan.contains { $0.id == "shopping-day" && $0.day == d("2026-10-17") && $0.hour == 9 && $0.minute == 30 && $0.repeatsWeekly })
        XCTAssertTrue(plan.contains { $0.body.contains("Olive oil") }, "olive oil enters the due-soon window later")
        XCTAssertFalse(plan.contains { $0.body.contains("Whole milk") }, "already overdue items are on the list, not reminded")
    }
}

final class BackupCompatibilityTests: XCTestCase {
    func testReadsWebAppBackup() throws {
        let url = Bundle.module.url(forResource: "web-backup", withExtension: "json", subdirectory: "Fixtures")!
        let data = try AppData.decode(Data(contentsOf: url))
        XCTAssertEqual(data.items.count, 18)
        XCTAssertEqual(data.trips.count, 3)
        XCTAssertTrue(data.trips.contains { $0.source == .trip && !$0.items.isEmpty })
        let yogurt = try XCTUnwrap(data.items.first { $0.product != nil })
        XCTAssertEqual(yogurt.product?.brand, "Chobani"); XCTAssertEqual(yogurt.product?.nutrition.kcal, 53)
        XCTAssertTrue(data.items.contains { $0.notes == "1 gal" })
        let again = try AppData.decode(data.encoded())
        XCTAssertEqual(again, data, "encoding and decoding round-trips")
        XCTAssertTrue(String(data: try data.encoded(), encoding: .utf8)!.contains("\"receipts\""), "keeps the web app's key so backups go both ways")
    }
}

final class SampleTests: XCTestCase {
    func testSampleLooksLikeARealPantry() {
        let data = AppData.sample(today: today)
        let s = data.listSections(today: today)
        XCTAssertEqual(data.items.count, 17)
        XCTAssertEqual(Set(s.now.map(\.name)), ["Whole milk", "Cheddar", "Birthday candles"])
        XCTAssertFalse(s.soon.isEmpty)
        XCTAssertEqual(data.trips.count, 1)
        XCTAssertTrue(AppData.pricesByStore(data.items[0]).count >= 2, "some items have prices at two stores")
    }
}
