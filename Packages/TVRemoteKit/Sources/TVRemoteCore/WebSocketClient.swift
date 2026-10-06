import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum WebSocketError: Error, Sendable {
    case closed(code: Int, reason: String?)
    case notOpen
}

/// WebSocket connection built on `URLSessionWebSocketTask`.
///
/// Text messages (and binary frames that decode as UTF-8) are delivered on
/// `messages`. Self-signed TV certificates are accepted when
/// `trustAnyCertificate` is set.
public final class WebSocketClient: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    public let messages: AsyncThrowingStream<String, Error>

    private let url: URL
    private let trustAnyCertificate: Bool
    private let messageContinuation: AsyncThrowingStream<String, Error>.Continuation
    private var session: URLSession!
    private var task: URLSessionWebSocketTask?
    private let lock = NSLock()
    private var openContinuation: CheckedContinuation<Void, Error>?
    private var finished = false

    public init(url: URL, trustAnyCertificate: Bool = true, timeout: TimeInterval = 10) {
        var continuation: AsyncThrowingStream<String, Error>.Continuation!
        messages = AsyncThrowingStream { continuation = $0 }
        messageContinuation = continuation
        self.url = url
        self.trustAnyCertificate = trustAnyCertificate
        super.init()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        #if !os(Linux)
        configuration.waitsForConnectivity = false
        #endif
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    deinit {
        receiveTask?.cancel()
        task?.cancel(with: .goingAway, reason: nil)
        session.invalidateAndCancel()
    }

    /// Opens the socket and waits for the handshake to complete.
    public func connect() async throws {
        let task = session.webSocketTask(with: url)
        self.task = task
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.lock()
            openContinuation = continuation
            lock.unlock()
            task.resume()
        }
        receiveLoop()
    }

    public func send(text: String) async throws {
        guard let task else { throw WebSocketError.notOpen }
        try await task.send(.string(text))
    }

    public func send<T: Encodable>(json value: T) async throws {
        let data = try JSONEncoder().encode(value)
        try await send(text: String(decoding: data, as: UTF8.self))
    }

    public func close() {
        receiveTask?.cancel()
        task?.cancel(with: .normalClosure, reason: nil)
        finish(error: nil)
    }

    // MARK: Internals

    private var receiveTask: Task<Void, Never>?

    private func receiveLoop() {
        guard let task else { return }
        receiveTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let message = try await task.receive()
                    switch message {
                    case .string(let text):
                        self?.messageContinuation.yield(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            self?.messageContinuation.yield(text)
                        }
                    @unknown default:
                        break
                    }
                } catch {
                    self?.finish(error: error)
                    return
                }
            }
        }
    }

    private func finish(error: Error?) {
        lock.lock()
        let already = finished
        finished = true
        let pendingOpen = openContinuation
        openContinuation = nil
        lock.unlock()
        if let pendingOpen {
            pendingOpen.resume(throwing: error ?? WebSocketError.closed(code: 0, reason: "closed before open"))
        }
        guard !already else { return }
        if let error { messageContinuation.finish(throwing: error) } else { messageContinuation.finish() }
    }

    // MARK: URLSessionWebSocketDelegate

    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        lock.lock()
        let pending = openContinuation
        openContinuation = nil
        lock.unlock()
        pending?.resume()
    }

    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                           didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let text = reason.flatMap { String(data: $0, encoding: .utf8) }
        finish(error: WebSocketError.closed(code: closeCode.rawValue, reason: text))
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        finish(error: error)
    }

    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                           completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        #if canImport(Security) && !os(Linux)
        if trustAnyCertificate,
           challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }
        #endif
        completionHandler(.performDefaultHandling, nil)
    }
}
