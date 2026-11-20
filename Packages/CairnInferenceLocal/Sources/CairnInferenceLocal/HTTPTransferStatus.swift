import Foundation

/// Which HTTP answer means "the bytes behind this response are the file", and which means "this is an error page".
///
/// The rule exists because a download task does not fail on a refusal. URLSession hands back
/// `error == nil` for a 401, 403, 404 or 429 and writes the server's error body to the temporary file exactly as
/// it would write a weight file, so a 404 from the Hub arrives looking like a successful download of a
/// fifteen-byte JSON document. Measured against the real endpoint on 2026-11-20: a missing path answered
/// `status=404 error=nil` with a 15-byte body, and the delegate that was written to accept anything moved it
/// into place. Saved as `model.safetensors` that body is a model that loads as nothing, which is why the status
/// is checked before a single byte is stored rather than after.
///
/// 206 is accepted on purpose. A resumed transfer asks for a range and is answered with partial content — that
/// is the resumed file continuing, not an error — and the Hub's own redirect to the storage host keeps the
/// `Range` header intact, so a pause taken mid-file comes back as 206 rather than 200.
enum HTTPTransferStatus {
    /// Partial content: the continuation of a file this phone already started fetching.
    static let partialContent = 206
    /// Range not satisfiable: the offset a resume block asked for is no longer in this file.
    static let staleRange = 416

    static func carriesFile(_ status: Int) -> Bool {
        status == partialContent || (200 ..< 300).contains(status)
    }

    /// Whether the answer to refuse is worth starting the file over rather than reporting.
    ///
    /// A resume block points into a temporary file the system owns, and its offset can go stale — the publisher
    /// repushed the file, or the storage host no longer holds that range. The server says so with 416, and that
    /// is one file that has to be taken again from its beginning, not a download that failed.
    static func asksForARestart(_ status: Int) -> Bool { status == staleRange }

    /// The refusal in a sentence a person can act on.
    ///
    /// The status number is included because it is the only part of a refusal that is worth showing: it is typed
    /// metadata, it says which of the four refusals this is, and nothing of the server's body — which can contain
    /// a token-bearing URL or an account name — ever travels with it.
    static func refusal(_ status: Int) -> String {
        switch status {
        case 401:
            return "The Hub asked to be signed in before handing over this file (status 401). A saved token may "
                + "be missing, expired, or not allowed for this repository."
        case 403:
            return "The Hub will not give this file to this phone (status 403). The repository may be private, "
                + "or its terms may have to be accepted on the Hub's website first."
        case 404:
            return "The Hub has no file at that address (status 404). The repository may have renamed or "
                + "removed it since this list was read."
        case staleRange:
            return "The part of the file this phone asked to resume from is no longer there (status 416). "
                + "The file is being taken again from its beginning."
        case 429:
            return "The Hub is turning this phone away for asking too often (status 429). Wait a minute and "
                + "start the download again."
        case 500...599:
            return "The Hub could not serve this file (status \(status)). Its side is failing, not this phone's. "
                + "Try again in a little while."
        default:
            return "The server answered with status \(status) instead of the file, so nothing was stored."
        }
    }

    /// The refusal for a real response, or nil when the response is one this downloader may store.
    ///
    /// A response that is not HTTP at all is not refused here: this downloader only builds `https` URLs, and a
    /// check invented for a scheme it never asks for would be a rule nobody can test.
    static func refusal(for response: URLResponse?) -> String? {
        guard let http = response as? HTTPURLResponse else { return nil }
        let status = http.statusCode
        return carriesFile(status) ? nil : refusal(status)
    }
}
