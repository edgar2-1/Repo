import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum HTTPError: Error, Sendable, Equatable {
    case status(Int)
    case noResponse
}

/// Small URLSession wrapper. TVs use self-signed certificates on their HTTPS
/// ports, so `insecure` accepts any server trust (local network only).
public final class HTTPClient: NSObject, URLSessionDelegate, @unchecked Sendable {
    public static let insecure = HTTPClient(trustAnyCertificate: true)
    public static let standard = HTTPClient(trustAnyCertificate: false)

    private var session: URLSession!
    private let trustAnyCertificate: Bool

    public init(trustAnyCertificate: Bool, timeout: TimeInterval = 5) {
        self.trustAnyCertificate = trustAnyCertificate
        super.init()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout * 2
        #if !os(Linux)
        configuration.waitsForConnectivity = false
        #endif
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    @discardableResult
    public func get(_ url: URL) async throws -> (Data, HTTPURLResponse) {
        try await request("GET", url)
    }

    @discardableResult
    public func post(_ url: URL, body: Data? = nil, contentType: String? = nil) async throws -> (Data, HTTPURLResponse) {
        try await request("POST", url, body: body, contentType: contentType)
    }

    public func request(_ method: String, _ url: URL, body: Data? = nil, contentType: String? = nil) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        if body != nil, contentType == nil { request.setValue("text/plain", forHTTPHeaderField: "Content-Type") }

        return try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let http = response as? HTTPURLResponse else {
                    continuation.resume(throwing: HTTPError.noResponse)
                    return
                }
                guard (200 ..< 300).contains(http.statusCode) else {
                    continuation.resume(throwing: HTTPError.status(http.statusCode))
                    return
                }
                continuation.resume(returning: (data ?? Data(), http))
            }
            task.resume()
        }
    }

    // MARK: URLSessionDelegate

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
