import Foundation

/// The TV this watch is paired with. The pairing itself lives on the TV side
/// (it remembers our client certificate); we only need to remember where it is.
struct PairedTV: Codable, Equatable {
    var name: String
    var host: String
}
