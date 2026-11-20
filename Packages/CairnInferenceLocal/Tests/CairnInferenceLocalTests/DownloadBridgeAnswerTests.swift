import Foundation
import Testing
@testable import CairnInferenceLocal

/// What a transfer is answered with.
///
/// None of this needs a network: the rules are driven directly with a token, a synthetic response and a
/// temporary file, which is the only reason they can be tested at all. What they protect is expensive — a
/// refused error page stored as a weight file, and an answer lost between two callbacks.
struct DownloadBridgeAnswerTests {
    private func scratch() -> (root: URL, destination: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cairn-bridge-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (root, root.appendingPathComponent("model.safetensors"))
    }

    /// A body on disk, which is all the handoff callback ever hands over: an error page and a weight file look
    /// identical in this position.
    private func body(_ text: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cairn-body-\(UUID().uuidString)")
        try Data(text.utf8).write(to: url)
        return url
    }

    private func response(_ status: Int) -> URLResponse? {
        HTTPURLResponse(url: URL(string: "https://huggingface.co/org/model/resolve/main/model.safetensors")!,
                        statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)
    }

    /// The status is checked before anything moves, so a refusal leaves nothing behind.
    @Test func refusesAnErrorPageAndStoresNothing() async throws {
        let (root, destination) = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let bridge = DownloadBridge()
        let token = bridge.register(destination: destination) { _ in }
        bridge.storeFile(try body(#"{"error":"Not Found"}"#), for: token, response: response(404))
        let outcome = await bridge.wait(for: token)
        #expect(outcome == .refused(status: 404))
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    /// A refusal can arrive before the caller gets as far as asking for its result: the task starts first, and a
    /// bad path is answered in microseconds. An answer with nowhere to go used to be an answer that was lost,
    /// which is how a 404 reached the sheet wearing a cancellation message.
    @Test func refusesTheRealReasonWhenTheAnswerArrivesBeforeTheCallerWaits() async throws {
        let (root, destination) = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let bridge = DownloadBridge()
        let token = bridge.register(destination: destination) { _ in }
        bridge.storeFile(try body(#"{"error":"Not Found"}"#), for: token, response: response(403))
        // Nothing has asked for the outcome yet, and the answer still cannot be missed.
        #expect(await bridge.wait(for: token) == .refused(status: 403))
    }

    /// A completion with no file behind it is not success with zero bytes; it is a transfer that delivered
    /// nothing, and the two must not read the same way on a screen.
    @Test func doesNotReportSuccessWhenNoFileArrived() async {
        let (root, destination) = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let bridge = DownloadBridge()
        let token = bridge.register(destination: destination) { _ in }
        bridge.answer(token, failure: nil)
        #expect(await bridge.wait(for: token)
                == .failed(message: "The transfer finished without delivering a file."))
    }

    /// A real file is moved out of the system's temporary location and reported with the bytes that are actually
    /// on disk — which for a resumed file is not the number the socket counted.
    @Test func movesTheFileIntoPlaceAndReportsTheBytesOnDisk() async throws {
        let (root, destination) = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let bridge = DownloadBridge()
        let token = bridge.register(destination: destination) { _ in }
        // 206, not 200: a resumed file is answered with partial content and is still the file.
        bridge.storeFile(try body("payload payload"), for: token, response: response(206))
        bridge.answer(token, failure: nil)
        #expect(await bridge.wait(for: token) == .complete(bytes: 14))
        #expect(try Data(contentsOf: destination) == Data("payload payload".utf8))
    }

    /// Nowhere to put the file is a failure of its own, said in storage words rather than network words.
    @Test func reportsAStoreProblemWhenTheFileCannotBeStored() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cairn-bridge-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // The destination's own parent is a regular file, so there is no directory to move into.
        let blocker = root.appendingPathComponent("blocker")
        try Data("x".utf8).write(to: blocker)
        let bridge = DownloadBridge()
        let token = bridge.register(destination: blocker.appendingPathComponent("model.safetensors")) { _ in }
        bridge.storeFile(try body("payload"), for: token, response: response(200))
        #expect(await bridge.wait(for: token)
                == .failed(message: "The downloaded file could not be stored."))
    }

    /// One pause produces two callbacks and no order between them is documented, so the first to answer wins and
    /// the second is dropped. Resuming a continuation twice is a crash rather than a wrong number.
    @Test func keepsTheFirstAnswerWhenTwoArrive() async {
        let (root, destination) = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let bridge = DownloadBridge()
        let token = bridge.register(destination: destination) { _ in }
        bridge.answer(token, failure: URLError(.timedOut))
        bridge.answer(token, failure: nil)
        switch await bridge.wait(for: token) {
        case .failed(let text):
            #expect(text.contains("\(NSURLErrorTimedOut)"))
            #expect(text.contains("Resume"))
        default:
            Issue.record("a stalled socket must be reported as a failure")
        }
    }

    /// A stop aimed at one repository's directory leaves every other repository's file alone, and closes the
    /// connection of the one it is aimed at rather than waiting for the next gap between bytes.
    @Test func stopsOnlyTheFilesOfThatDirectory() {
        let (root, destination) = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = URLSession(configuration: .ephemeral)
        let task = session.downloadTask(
            with: URLRequest(url: URL(string: "https://huggingface.co/org/model/resolve/main/config.json")!)
        )
        let bridge = DownloadBridge()
        let token = bridge.register(destination: destination) { _ in }
        task.taskDescription = String(token)
        bridge.attach(token, task: task)

        #expect(bridge.stopTransfers(in: root.appendingPathComponent("other-repository"), pause: true) == 0)
        #expect(bridge.stopTransfers(in: root, pause: false) == 1)
        task.cancel()
        session.invalidateAndCancel()
    }
}
