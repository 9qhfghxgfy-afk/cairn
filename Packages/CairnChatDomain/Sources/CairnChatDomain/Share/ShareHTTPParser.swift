import Foundation

/// Why a request was refused before it was ever routed. Typed, and never carries the bytes.
public enum ShareParseFailure: String, Sendable, Equatable, Error {
    case malformedRequest
    case unsupportedVersion
    case unsupportedBodyEncoding
    case headersTooLarge
    case bodyTooLarge
}

public enum ShareParseOutcome: Sendable, Equatable {
    case complete(ShareHTTPRequest)
    /// The socket has not delivered a whole request yet. This is the normal state mid-read, not an
    /// error — an HTTP request arrives in as many pieces as the network feels like.
    case needMoreBytes
    case rejected(ShareParseFailure)
}

/// A small, strict HTTP/1.1 request reader.
///
/// Strict on purpose. This listener answers clients on the same wire an Ollama or OpenAI client
/// expects, and the least useful failure is a silently mis-parsed request: a request with a
/// truncated body would otherwise be answered as if it had arrived whole, which looks like the
/// model misbehaving. Byte budgets exist because a socket is not a promise — a phone must not be
/// made to hold an attacker-sized buffer in order to answer one line. They bound **what a request
/// may be**, never what a user may do.
public enum ShareHTTPParser {
    public static let headerByteBudget = 16_384
    /// A shared vision turn carries a base64 image inside its JSON body, so the body ceiling has
    /// to clear a photo, not just a prompt.
    public static let bodyByteBudget = 8_388_608

    public static func parse(_ data: Data) -> ShareParseOutcome {
        let bytes = [UInt8](data)
        guard let boundary = terminator(in: bytes) else {
            return bytes.count > headerByteBudget ? .rejected(.headersTooLarge) : .needMoreBytes
        }
        let headBytes = Array(bytes[0..<boundary.headEnd])
        if headBytes.count > headerByteBudget { return .rejected(.headersTooLarge) }
        return assemble(head: headBytes, body: Array(bytes[boundary.bodyStart...]))
    }

    private struct Boundary { var headEnd: Int; var bodyStart: Int }

    /// Finds `\r\n\r\n`, or the lenient `\n\n` a hand-written client may send.
    private static func terminator(in bytes: [UInt8]) -> Boundary? {
        var index = 0
        while index + 1 < bytes.count {
            if bytes[index] == 13, bytes[index + 1] == 10 {
                if index + 3 < bytes.count, bytes[index + 2] == 13, bytes[index + 3] == 10 {
                    return Boundary(headEnd: index, bodyStart: index + 4)
                }
            } else if bytes[index] == 10 {
                if index + 1 < bytes.count, bytes[index + 1] == 10 {
                    return Boundary(headEnd: index, bodyStart: index + 2)
                }
            }
            index += 1
        }
        return nil
    }

    /// One head line per LF **byte**, with a trailing CR byte dropped.
    ///
    /// This is done on bytes on purpose. In Swift a `Character` is an extended grapheme cluster and
    /// CR+LF collapses into **one** character, so splitting a request head on the character `"\n"`
    /// does not split a request at all: `components(separatedBy: "\n")` hands back the whole head as
    /// a single line, the request line then splits into four space-separated fields instead of
    /// three, and every real client — which sends CRLF, because RFC 9112 says to — is refused as
    /// malformed. A wire format is bytes; only the decoded line becomes a `String`.
    private static func lines(from head: [UInt8]) -> [String] {
        var lines: [String] = []
        var start = 0
        while start <= head.count {
            var end = start
            while end < head.count, head[end] != 10 { end += 1 }
            var slice = Array(head[start..<end])
            if slice.last == 13 { slice.removeLast() }
            lines.append(String(bytes: slice, encoding: .utf8) ?? "")
            start = end + 1
        }
        return lines
    }

    private static func assemble(head headBytes: [UInt8], body: [UInt8]) -> ShareParseOutcome {
        let headLines = lines(from: headBytes)
        guard let requestLine = headLines.first, requestLine.isEmpty == false else {
            return .rejected(.malformedRequest)
        }
        let fields = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard fields.count == 3 else { return .rejected(.malformedRequest) }
        guard fields[2].uppercased().hasPrefix("HTTP/1.") else { return .rejected(.unsupportedVersion) }

        var path = String(fields[1])
        var query: String?
        if let mark = path.firstIndex(of: "?") {
            query = String(path[path.index(after: mark)...])
            path = String(path[..<mark])
        }
        guard path.hasPrefix("/") else { return .rejected(.malformedRequest) }

        var headers: [String: String] = [:]
        for line in headLines.dropFirst() {
            if line.isEmpty { continue }
            guard let colon = line.firstIndex(of: ":") else { return .rejected(.malformedRequest) }
            let name = String(line[..<colon]).lowercased()
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }
        if headers["transfer-encoding"]?.lowercased().contains("chunked") == true {
            return .rejected(.unsupportedBodyEncoding)
        }

        let request = ShareHTTPRequest(
            method: String(fields[0]).uppercased(),
            path: path,
            query: query,
            headers: headers,
            body: Data(body)
        )
        guard let declared = request.contentLength else { return .complete(request) }
        if declared > bodyByteBudget { return .rejected(.bodyTooLarge) }
        guard body.count >= declared else { return .needMoreBytes }
        var trimmed = request
        trimmed.body = Data(body[0..<declared])
        return .complete(trimmed)
    }
}
