import Foundation

/// Runs `body`, failing with `TVControllerError.timeout` after `seconds`.
/// `onTimeout` runs first so callers can unblock whatever `body` is waiting on.
public func withTimeout<T: Sendable>(
    seconds: Double,
    onTimeout: (@Sendable () -> Void)? = nil,
    _ body: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await body() }
        group.addTask {
            try await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
            onTimeout?()
            throw TVControllerError.timeout
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
