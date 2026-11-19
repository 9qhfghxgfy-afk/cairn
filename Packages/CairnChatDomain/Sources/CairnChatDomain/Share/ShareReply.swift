import Foundation

/// A whole answer to write down one socket: a status, a content type, and the body pieces in
/// order. Value-typed so every frame this server emits can be asserted in a test without a socket
/// in the room.
public struct ShareReply: Sendable, Equatable {
    public var status: Int
    public var contentType: String?
    /// Body pieces in the order they go out. For a stream these are the frames, written one at a
    /// time; for a complete answer there is exactly one.
    public var frames: [String]
    public var streaming: Bool
    public var extraHeaders: [String: String]

    public init(
        status: Int,
        contentType: String?,
        frames: [String] = [],
        streaming: Bool = false,
        extraHeaders: [String: String] = [:]
    ) {
        self.status = status
        self.contentType = contentType
        self.frames = frames
        self.streaming = streaming
        self.extraHeaders = extraHeaders
    }

    public var bodyData: Data { Data(frames.joined().utf8) }
    public var headData: Data { Data(headText.utf8) }
    public var allBytes: Data { headData + bodyData }

    public var headText: String {
        ShareHTTPResponse.head(
            status: status,
            contentType: contentType,
            streaming: streaming,
            bodyBytes: streaming ? nil : bodyData.count,
            extraHeaders: extraHeaders
        )
    }
}

/// Frame framing, spelled once.
public enum ShareFrame {
    /// Ollama: one JSON object per line.
    public static func ndjson(_ object: String) -> String { object + "\n" }
    /// OpenAI-compatible: one SSE event per chunk, terminated by a blank line.
    public static func sse(_ payload: String) -> String { "data: \(payload)\n\n" }
    public static let sseDone = "data: [DONE]\n\n"
}

public enum ShareHTTPResponse {
    public static let serverName = "\(ShareDialect.serverToken)/\(ShareSettings.servedVersion)"

    public static func json(status: Int, body: String, contentType: String = "application/json") -> ShareReply {
        ShareReply(status: status, contentType: contentType, frames: [body])
    }

    /// A stream gets **no Content-Length** and `Connection: close`: the end of the answer is the
    /// end of the socket, which is what lets a frame go out the moment it is produced instead of
    /// after a chunked-encoding state machine has been written and trusted.
    public static func streaming(dialect: ShareDialect, frames: [String] = []) -> ShareReply {
        ShareReply(status: 200, contentType: dialect.streamContentType, frames: frames, streaming: true)
    }

    /// An error in the dialect the client asked in. An Ollama client reads `error`; an
    /// OpenAI-compatible one reads `error.message`, and a bare string in the wrong shape reads to
    /// that client as a server that answered nothing.
    public static func error(status: Int, dialect: ShareDialect, message: String) -> ShareReply {
        switch dialect {
        case .ollama:
            return json(status: status, body: ShareErrorBody.ollama(message))
        case .openAI:
            return json(status: status, body: ShareErrorBody.openAI(message, kind: ShareHTTPResponse.kind(for: status)))
        }
    }

    /// A browser preflight is answered and stops there: it carries no turn and no key, so the
    /// answer is the permission, not a generation.
    public static func preflight(origin: String?) -> ShareReply {
        var headers = ["Access-Control-Allow-Methods": "GET, POST, OPTIONS", "Access-Control-Allow-Headers": "Authorization, X-API-Key, Content-Type"]
        if let origin, !origin.isEmpty { headers["Access-Control-Allow-Origin"] = origin }
        return ShareReply(status: 204, contentType: nil, extraHeaders: headers)
    }

    public static func head(
        status: Int,
        contentType: String?,
        streaming: Bool,
        bodyBytes: Int?,
        extraHeaders: [String: String] = [:]
    ) -> String {
        var lines = ["HTTP/1.1 \(status) \(reason(for: status))", "Server: \(serverName)", "Cache-Control: no-store", "Connection: close"]
        if let contentType { lines.append("Content-Type: \(contentType)") }
        if let bodyBytes { lines.append("Content-Length: \(bodyBytes)") }
        if streaming { lines.append("X-Accel-Buffering: no") }
        for name in extraHeaders.keys.sorted() { lines.append("\(name): \(extraHeaders[name] ?? "")") }
        return lines.joined(separator: "\r\n") + "\r\n\r\n"
    }

    public static func reason(for status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 413: return "Content Too Large"
        case 500: return "Internal Server Error"
        case 503: return "Service Unavailable"
        default: return "Status \(status)"
        }
    }

    /// The `type` an OpenAI-compatible client reads back, from the status alone.
    public static func kind(for status: Int) -> String {
        switch status {
        case 401, 403: return "authentication_error"
        case 404: return "not_found_error"
        case 400, 413: return "invalid_request_error"
        default: return "server_error"
        }
    }
}
