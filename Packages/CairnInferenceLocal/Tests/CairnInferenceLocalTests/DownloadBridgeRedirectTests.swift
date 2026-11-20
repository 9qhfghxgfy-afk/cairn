import Foundation
import Testing
@testable import CairnInferenceLocal

/// The redirect rule: a credential stops at the host it was written for.
///
/// The Hub answers a weight-file request by pointing at a storage host nobody named, and the signed address it
/// hands out carries its own authorisation. A bearer token is proof of who asked, not a ticket for wherever the
/// answer points, so the hop has to go out without it — while the headers that make a resumed file resume have
/// to survive the hop untouched.
struct DownloadBridgeRedirectTests {
    private let hub = URL(string: "https://huggingface.co/org/model/resolve/main/model.safetensors")!
    private let storage = URL(
        string: "https://cas-bridge.xethub.hf.co/xet-bridge-us/abc/model.safetensors?X-Amz-Signature=deadbeef"
    )!

    private func request(to url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer hf_secretvalue", forHTTPHeaderField: "Authorization")
        request.setValue("hf_secretvalue", forHTTPHeaderField: "X-API-Key")
        request.setValue("session=abc", forHTTPHeaderField: "Cookie")
        request.setValue("bytes=1048576-", forHTTPHeaderField: "Range")
        request.setValue(HuggingFaceEndpoints.userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    @Test func stripsTheCredentialOnACrossHostHop() {
        let onward = DownloadBridge.redirectRequest(request(to: storage), redirectedFrom: hub)
        #expect(onward.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(onward.value(forHTTPHeaderField: "X-API-Key") == nil)
        #expect(onward.value(forHTTPHeaderField: "Api-Key") == nil)
        #expect(onward.value(forHTTPHeaderField: "Cookie") == nil)
    }

    /// A same-host hop is an authenticated retry of the host the token was written for, and dropping the token
    /// there is what breaks a private repository's download.
    @Test func keepsTheCredentialOnASameHostHop() {
        let retry = URL(string: "https://huggingface.co/org/model/resolve/main/config.json")!
        let onward = DownloadBridge.redirectRequest(request(to: retry), redirectedFrom: hub)
        #expect(onward.value(forHTTPHeaderField: "Authorization") == "Bearer hf_secretvalue")
        #expect(onward.value(forHTTPHeaderField: "Cookie") == "session=abc")
    }

    /// An unknown source is treated as a stranger: the token has no host it is known to belong to, so it does
    /// not travel.
    @Test func stripsTheCredentialWhenTheSourceIsUnknown() {
        let onward = DownloadBridge.redirectRequest(request(to: hub), redirectedFrom: nil)
        #expect(onward.value(forHTTPHeaderField: "Authorization") == nil)
    }

    /// Everything that is not a credential rides along, because a resumed download that loses its `Range`
    /// header starts a four-gigabyte file over again and never says so.
    @Test func carriesEveryHeaderThatIsNotACredential() {
        let onward = DownloadBridge.redirectRequest(request(to: storage), redirectedFrom: hub)
        #expect(onward.value(forHTTPHeaderField: "Range") == "bytes=1048576-")
        #expect(onward.value(forHTTPHeaderField: "User-Agent") == HuggingFaceEndpoints.userAgent)
        #expect(onward.url == storage)
    }

    /// A request with no credential at all — the ordinary case for a public model — is unchanged by the rule.
    @Test func leavesARequestWithoutACredentialAlone() {
        var plain = URLRequest(url: storage)
        plain.setValue("bytes=0-", forHTTPHeaderField: "Range")
        let onward = DownloadBridge.redirectRequest(plain, redirectedFrom: hub)
        #expect(onward.value(forHTTPHeaderField: "Range") == "bytes=0-")
        #expect(onward.value(forHTTPHeaderField: "Authorization") == nil)
    }

    /// The delegate finds its waiter by the token carried on the task, which is what lets several files be in
    /// flight at once without their callbacks landing on each other.
    @Test func readsTheTokenBackOffTheTaskThatCarriesIt() {
        let session = URLSession(configuration: .ephemeral)
        let task = session.downloadTask(with: URLRequest(url: hub))
        task.taskDescription = "42"
        #expect(DownloadBridge().token(for: task) == 42)
        task.cancel()
        session.invalidateAndCancel()
    }
}
