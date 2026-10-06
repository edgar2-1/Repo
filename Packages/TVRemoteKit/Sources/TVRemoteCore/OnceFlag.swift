import Foundation

/// Runs a closure at most once.
final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    @discardableResult
    func run(_ body: () -> Void) -> Bool {
        lock.lock()
        if done { lock.unlock(); return false }
        done = true
        lock.unlock()
        body()
        return true
    }
}
