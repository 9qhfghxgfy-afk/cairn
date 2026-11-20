import Foundation
import Testing
@testable import CairnInferenceLocal

/// How often a bar is allowed to move, and what it is allowed to say while it stands still.
///
/// A four-gigabyte weight file reports a write every few hundred kilobytes, which is thousands of updates per
/// transfer. Each one crosses into the view model and redraws a bar nobody can read that fast, and the flood
/// costs socket time — a progress stream that outruns the screen is how a fast download looks a slow one.
struct DownloadBridgeProgressTests {
    /// Collects updates from whichever queue the delegate happens to run on.
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var seen: [DownloadProgressUpdate] = []
        var all: [DownloadProgressUpdate] {
            lock.lock()
            defer { lock.unlock() }
            return seen
        }
        var count: Int { all.count }
        var last: DownloadProgressUpdate? { all.last }
        func record(_ update: DownloadProgressUpdate) {
            lock.lock()
            seen.append(update)
            lock.unlock()
        }
    }

    private func bridge(_ recorder: Recorder) -> (DownloadBridge, Int) {
        let bridge = DownloadBridge()
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("cairn-progress-\(UUID().uuidString)/model.safetensors")
        return (bridge, bridge.register(destination: destination) { recorder.record($0) })
    }

    @Test func sendsTheFirstNumberAndHoldsTheSmallOnes() {
        let recorder = Recorder()
        let (bridge, token) = bridge(recorder)
        let total: Int64 = 4_000_000_000
        bridge.emitProgress(token: token, received: 0, expectedFromServer: total)
        // Thousands of these follow a real download; none of them may reach the screen.
        for bytes in stride(from: Int64(1_000), through: 50_000, by: 1_000) {
            bridge.emitProgress(token: token, received: bytes, expectedFromServer: total)
        }
        #expect(recorder.count == 1)
        #expect(recorder.last?.receivedBytes == 0)

        bridge.emitProgress(token: token, received: 1_000_000, expectedFromServer: total)
        #expect(recorder.count == 2)
        #expect(recorder.last?.receivedBytes == 1_000_000)
        #expect(recorder.last?.expectedBytes == total)
    }

    /// A hop that restarts — a redirect followed, a retry taken — counts from zero again. Measuring the window
    /// from the last number sent would read that as a negative stride and go quiet for the rest of the transfer.
    @Test func treatsARestartedCounterAsANewWindow() {
        let recorder = Recorder()
        let (bridge, token) = bridge(recorder)
        bridge.emitProgress(token: token, received: 5_000_000, expectedFromServer: 9_000_000)
        bridge.emitProgress(token: token, received: 300_000, expectedFromServer: 9_000_000)
        #expect(recorder.count == 2)
        #expect(recorder.last?.receivedBytes == 300_000)
    }

    /// A missing denominator stays missing. A guessed one is a lie about how close the download is.
    @Test func leavesAnUndeclaredFileSizeUndeclared() {
        let recorder = Recorder()
        let (bridge, token) = bridge(recorder)
        bridge.emitProgress(token: token, received: 128, expectedFromServer: -1)
        #expect(recorder.last?.expectedBytes == nil)
        #expect(recorder.last?.fraction == nil)
        #expect(recorder.last?.receivedBytes == 128)
    }

    /// A wait repeats the last honest numbers rather than inventing new ones: a bar parked at 2.1 GB is still a
    /// bar that says 2.1 GB, and the waiting flag is what tells the screen to explain why it is not moving.
    @Test func repeatsTheLastHonestNumbersWhileWaiting() {
        let recorder = Recorder()
        let (bridge, token) = bridge(recorder)
        bridge.emitProgress(token: token, received: 4_000, expectedFromServer: 9_000)
        bridge.emitWaiting(token: token, expectedFromServer: 9_000)
        #expect(recorder.count == 2)
        guard let waiting = recorder.last else { return }
        #expect(waiting.isWaiting)
        #expect(waiting.receivedBytes == 4_000)
        #expect(waiting.expectedBytes == 9_000)
        #expect(waiting.fraction ?? 0 > 0)
    }

    /// A transfer that has been answered stops reporting. A late write landing after the pause was reported must
    /// not move a bar the person has already been told stands still.
    @Test func reportsNothingAfterATransferIsAnswered() {
        let recorder = Recorder()
        let (bridge, token) = bridge(recorder)
        bridge.answer(token: token, failure: nil)
        bridge.emitProgress(token: token, received: 5_000_000, expectedFromServer: 9_000_000)
        bridge.emitWaiting(token: token, expectedFromServer: 9_000_000)
        #expect(recorder.count == 0)
    }
}
