import Foundation

/// A parsed SSDP `HTTP/1.1 200 OK` search reply.
public struct SSDPResponse: Equatable, Sendable {
    public var headers: [String: String]

    public init(headers: [String: String]) {
        self.headers = headers
    }

    /// Parses the raw datagram. Header names are lower-cased.
    public init?(datagram: Data) {
        guard let text = String(data: datagram, encoding: .utf8) ?? String(data: datagram, encoding: .isoLatin1) else { return nil }
        let lines = text.split(whereSeparator: { $0 == "\r\n" || $0 == "\n" }).map(String.init)
        guard let status = lines.first, status.uppercased().contains("200 OK") else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }
        self.headers = headers
    }

    public var location: URL? { headers["location"].flatMap(URL.init(string:)) }
    public var searchTarget: String { headers["st"] ?? "" }
    public var usn: String { headers["usn"] ?? "" }
    public var server: String { headers["server"] ?? "" }

    /// Host (IP) taken from the LOCATION header.
    public var host: String? { location?.host }

    /// Best-effort brand detection from the ST / SERVER headers.
    public var brand: TVBrand? {
        let st = searchTarget.lowercased()
        let server = server.lowercased()
        if st.contains("roku:ecp") || server.contains("roku") { return .roku }
        if st.contains("lge-com") || st.contains("webos") || server.contains("webos") { return .lg }
        if st.contains("samsung") || server.contains("samsung") || server.contains("tizen") { return .samsung }
        return nil
    }

    /// The M-SEARCH datagram used to find every brand we support.
    public static func searchRequest(target: String = "ssdp:all", maxWait: Int = 2) -> Data {
        let text = [
            "M-SEARCH * HTTP/1.1",
            "HOST: 239.255.255.250:1900",
            "MAN: \"ssdp:discover\"",
            "MX: \(maxWait)",
            "ST: \(target)",
            "", "",
        ].joined(separator: "\r\n")
        return Data(text.utf8)
    }
}
