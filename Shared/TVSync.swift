import Foundation
import TVRemoteCore
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// Everything one device needs to control the same TVs as the other:
/// the TV list, per-TV credentials, and the Google TV client identity
/// (certificate + key) so a Google TV paired on the phone also accepts the watch.
struct SyncPayload: Codable, Equatable {
    var tvs: [SavedTV]
    var credentials: [String: String]
    var identityCertificate: Data?
    var identityKey: Data?
    var updatedAt: Date
}

/// Mirrors saved TVs between iPhone and Apple Watch over WatchConnectivity.
///
/// Both sides publish their full state as the application context; the
/// receiver applies it when it is newer than what it last applied. The
/// transport is end-to-end encrypted between the paired devices.
final class TVSync: NSObject, @unchecked Sendable {
    static let shared = TVSync()

    /// Called on the main actor with a payload newer than our own state.
    var onReceive: (@MainActor (SyncPayload) -> Void)?

    private let lock = NSLock()
    private var pendingPayload: SyncPayload?

    var isAvailable: Bool {
        #if canImport(WatchConnectivity)
        return WCSession.isSupported()
        #else
        return false
        #endif
    }

    func activate() {
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        #endif
    }

    /// Publishes the current state. Safe to call often; only the latest wins.
    func push(_ payload: SyncPayload) {
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return }
        lock.lock(); pendingPayload = payload; lock.unlock()
        flush()
        #endif
    }

    #if canImport(WatchConnectivity)
    private func flush() {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        #if os(iOS)
        guard session.isPaired, session.isWatchAppInstalled else { return }
        #endif
        lock.lock()
        let payload = pendingPayload
        pendingPayload = nil
        lock.unlock()
        guard let payload, let data = try? JSONEncoder().encode(payload) else { return }
        try? session.updateApplicationContext(["payload": data])
    }

    private func apply(_ context: [String: Any]) {
        guard let data = context["payload"] as? Data,
              let payload = try? JSONDecoder().decode(SyncPayload.self, from: data) else { return }
        Task { @MainActor [onReceive] in onReceive?(payload) }
    }
    #endif
}

#if canImport(WatchConnectivity)
extension TVSync: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        // Pick up anything the other side sent while we were away.
        if !session.receivedApplicationContext.isEmpty {
            apply(session.receivedApplicationContext)
        }
        flush()
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        apply(applicationContext)
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        flush()
    }
    #endif
}
#endif
