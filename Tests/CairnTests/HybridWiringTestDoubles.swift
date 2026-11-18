import Foundation
import CairnChatDomain

/// Typed event log for the residency tests. Records ids and verbs only — no model content, no prompt
/// text — which is the same rule the production code follows.
final class ResidencyRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []

    func record(_ entry: String) {
        lock.lock(); entries.append(entry); lock.unlock()
    }

    var recorded: [String] {
        lock.lock(); defer { lock.unlock() }; return entries
    }
}

/// A gate whose verdict is chosen by the test and whose releases are counted.
///
/// `@unchecked Sendable` because every access goes through the lock: the verdict is read from a turn's
/// task while the release count is read from the test. It exists to prove *injection* — that the gate a
/// workspace is handed is the gate a session answers with — which no verdict-only stub can show.
final class SpyResidencyGate: HybridResidencyGating, @unchecked Sendable {
    private let lock = NSLock()
    private var releases = 0
    private let verdict: Bool

    init(allowsTwoOnDeviceModelsResident verdict: Bool = false) {
        self.verdict = verdict
    }

    func allowsTwoOnDeviceModelsResident() -> Bool { verdict }

    @MainActor
    func evictResidentModel() async {
        lock.lock(); releases += 1; lock.unlock()
    }

    var releaseCount: Int {
        lock.lock(); defer { lock.unlock() }; return releases
    }
}
