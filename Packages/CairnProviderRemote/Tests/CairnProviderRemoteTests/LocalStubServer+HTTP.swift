import Foundation

/// The wire half of the stub: what a request line looks like, and what a response head looks
/// like. Kept apart from the socket plumbing so each piece stays readable.
extension LocalStubServer {
    static func requestPath(_ data: Data) -> String {
        guard let text = String(data: data, encoding: .utf8) else { return "" }
        let line = text.components(separatedBy: "\r\n").first ?? ""
        let fields = line.components(separatedBy: " ")
        return fields.count >= 2 ? fields[1] : ""
    }

    static func responseHead(status: Int, contentType: String, byteCount: Int) -> Data {
        let reason = status == 200 ? "OK" : "Status \(status)"
        let head = "HTTP/1.1 \(status) \(reason)\r\n"
            + "Content-Type: \(contentType)\r\n"
            + "Content-Length: \(byteCount)\r\n"
            + "Connection: close\r\n"
            + "\r\n"
        return Data(head.utf8)
    }
}
