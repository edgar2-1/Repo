import Foundation
import RestockKit

func money(_ value: Double?) -> String {
    guard let value else { return "" }
    return value.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
}

func parseAmount(_ text: String) -> Double? {
    Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
}

extension Day {
    var asDate: Date { date(hour: 12) ?? Date() }
    var short: String { asDate.formatted(.dateTime.month(.abbreviated).day()) }
    var long: String { asDate.formatted(.dateTime.weekday(.wide).month(.wide).day()) }
}
