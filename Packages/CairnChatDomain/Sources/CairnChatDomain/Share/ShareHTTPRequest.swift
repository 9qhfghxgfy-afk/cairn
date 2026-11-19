import Foundation

/// One parsed HTTP/1.1 request, as a value.
///
/// Header names are lowercased on the way in, because HTTP/1.1 says they are
/// case-insensitive and a server that compares them as written is a server that rejects
/// `Authorization:` written by a different client library tomorrow.
public struct ShareHTTPRequest: Sendable, Equatable {
    public var method: String
    /// Path without the query string.
    public var path: String
    public var query: String?
    public var headers: [String: String]
    public var body: Data

    public init(
        method: String,
        path: String,
        query: String? = nil,
        headers: [String: String] = [:],
        body: Data = Data()
    ) {
        self.method = method
        self.path = path
        self.query = query
        self.headers = headers
        self.body = body
    }

    public func header(_ name: String) -> String? { headers[name.lowercased()] }

    /// The path's dialect-shaped route, so a caller never has to remember to lowercase the verb.
    public var endpoint: ShareEndpoint { ShareRouting.endpoint(method: method, path: path) }

    public var contentLength: Int? {
        guard let raw = header("content-length") else { return nil }
        return Int(raw)
    }
}
