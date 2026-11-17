import CryptoKit
import Foundation

/// Streaming SHA-256 over a file, in chunks.
///
/// A model file is gigabytes, so it is hashed as it is read rather than loaded into memory — the
/// whole reason this is not a one-line `Data` hash. An `InputStream` is used instead of a file
/// handle so the caller never holds the file open across an await.
///
/// The digest is what makes a resumed download trustworthy: a partial file reassembled from two
/// connections is only the file the user asked for if the bytes hash to the published value.
public enum SHA256Digest {
    public static let streamingChunkBytes = 1 << 20

    public static func hex(of data: Data) -> String {
        Self.encode(SHA256.hash(data: data))
    }

    /// Lowercase hex, or nil when the file cannot be read. nil is reported as a verification
    /// failure by the caller; it is never treated as a match.
    public static func hex(ofFileAt url: URL, chunkBytes: Int = streamingChunkBytes) -> String? {
        guard chunkBytes > 0, let stream = InputStream(url: url) else { return nil }
        stream.open()
        defer { stream.close() }

        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: chunkBytes)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read < 0 { return nil }
            if read == 0 { break }
            hasher.update(data: Data(bytes: buffer, count: read))
        }
        if let streamError = stream.streamError { _ = streamError; return nil }
        return Self.encode(hasher.finalize())
    }

    /// True only on an exact, case-insensitive hex match. An expected value of nil means the
    /// publisher offered no digest, which the caller must surface rather than silently accept.
    public static func matches(expected: String?, fileAt url: URL) -> Bool {
        guard let expected, !expected.isEmpty,
              let actual = hex(ofFileAt: url)
        else { return false }
        return actual.caseInsensitiveCompare(expected.trimmingCharacters(in: .whitespaces)) == .orderedSame
    }

    static func encode(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
