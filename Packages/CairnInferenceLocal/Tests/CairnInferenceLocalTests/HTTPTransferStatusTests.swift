import Foundation
import Testing
@testable import CairnInferenceLocal

/// Which HTTP answers are files and which are error pages, and what a refusal says out loud.
///
/// The rule is the one thing standing between a 404 and an installed model, so it is tested as a rule rather
/// than trusted: a download task reports a refusal as a finished transfer with no error, and the status is the
/// only fact that separates the file from the page describing why the file is not there.
struct HTTPTransferStatusTests {
    @Test func acceptsAWholeFileAndAPartialOne() {
        #expect(HTTPTransferStatus.carriesFile(200))
        // 206 is a resumed file continuing, not a broken transfer.
        #expect(HTTPTransferStatus.carriesFile(HTTPTransferStatus.partialContent))
        #expect(HTTPTransferStatus.carriesFile(201))
    }

    @Test func refusesEveryRefusalTheHubActuallySends() {
        for status in [301, 401, 403, 404, HTTPTransferStatus.staleRange, 429, 500, 503] {
            #expect(!HTTPTransferStatus.carriesFile(status), "status \(status) must never be stored as a file")
        }
    }

    /// The one refusal that is a restart rather than an end, and the ones that are not.
    @Test func treatsOnlyStaleRangeAsARestart() {
        #expect(HTTPTransferStatus.asksForARestart(HTTPTransferStatus.staleRange))
        #expect(!HTTPTransferStatus.asksForARestart(404))
        #expect(!HTTPTransferStatus.asksForARestart(429))
    }

    /// A refusal has to name the number, because the number is what the person can act on: a 401 wants a
    /// token, a 403 wants repository terms, a 404 wants a different file.
    @Test func namesTheStatusInEveryRefusalItShows() {
        for status in [401, 403, 404, 416, 429, 500] {
            #expect(HTTPTransferStatus.refusal(status).contains("\(status)"))
        }
        #expect(HTTPTransferStatus.refusal(401) != HTTPTransferStatus.refusal(404))
        #expect(HTTPTransferStatus.refusal(429) != HTTPTransferStatus.refusal(500))
        // An unmapped status still says something true rather than nothing.
        #expect(HTTPTransferStatus.refusal(418).contains("418"))
    }

    /// Nothing of the server's body travels with a refusal — only the number does.
    @Test func keepsARefusalFreeOfAnythingButTheNumber() {
        for status in [401, 403, 404, 429, 500, 418] {
            let line = HTTPTransferStatus.refusal(status).lowercased()
            #expect(!line.contains("http"))
            #expect(!line.contains("authorization"))
            #expect(!line.contains("bearer"))
        }
    }

    @Test func separatesAFileFromARefusal() {
        #expect(HTTPTransferStatus.refusal(for: response(200)) == nil)
        #expect(HTTPTransferStatus.refusal(for: response(206)) == nil)
        #expect(HTTPTransferStatus.refusal(for: response(404)) != nil)
        // A response that is not HTTP at all is not a refusal this downloader invented a rule for.
        #expect(HTTPTransferStatus.refusal(for: nil) == nil)
        #expect(HTTPTransferStatus.refusal(for: URLResponse(url: URL(string: "file:///x")!, mimeType: nil,
                                                            expectedContentLength: 0, textEncodingName: nil)) == nil)
    }

    /// The failure the manager reports is this rule's words, not a flattened sentence of its own.
    @Test func statesTheRefusalThroughTheStatusRule() {
        #expect(ModelDownloadFailure.refusedByServer(status: 403).message
                == HTTPTransferStatus.refusal(403))
        #expect(ModelDownloadFailure.refusedByServer(status: 404).message.contains("404"))
    }

    private func response(_ status: Int) -> URLResponse? {
        HTTPURLResponse(url: URL(string: "https://huggingface.co/org/model/resolve/main/model.safetensors")!,
                        statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)
    }
}
