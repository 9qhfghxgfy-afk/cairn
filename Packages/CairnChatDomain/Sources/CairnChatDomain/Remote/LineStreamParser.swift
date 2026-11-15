import Foundation

/// Incremental newline-splitting for streamed HTTP bodies (SSE and NDJSON).
///
/// Network chunks split ANYWHERE — including mid-multibyte-UTF-8-sequence —
/// so this splits raw bytes on 0x0A and only then decodes each whole line.
/// Decoding per line is what keeps a split emoji from becoming garbage.
public struct LineStreamParser: Sendable {
    private var buffer = Data()

    public init() {}

    /// Bytes received so far that have not yet formed a complete line.
    public var pendingByteCount: Int { buffer.count }

    /// Feeds one network chunk and returns every line completed by it
    /// (newline stripped, one trailing 0x0D trimmed for CRLF streams).
    public mutating func feed(_ data: Data) -> [Data] {
        buffer.append(data)
        var lines: [Data] = []
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let lineEnd = newlineIndex
            var line = buffer[buffer.startIndex..<lineEnd]
            buffer.removeSubrange(buffer.startIndex...newlineIndex)
            if line.last == 0x0D { line = line.dropLast() }
            lines.append(Data(line))
        }
        return lines
    }

    /// A final unterminated tail, if the producer ended without a newline.
    public mutating func takeTrailingPartialLine() -> Data? {
        guard !buffer.isEmpty else { return nil }
        let tail = buffer
        buffer.removeAll(keepingCapacity: false)
        return tail
    }

    /// UTF-8 decode; nil for undecodable bytes (callers treat that as a
    /// malformed line rather than guessing at replacement text).
    public static func decode(_ line: Data) -> String? {
        String(data: line, encoding: .utf8)
    }
}