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
/// `@unchecked Sendable` because its only mutable state is the release counter, and that counter is
/// main-actor work in both directions: `evictResidentModel` is `@MainActor`, and every test reads the
/// count from the main actor too. `NSLock.lock()` is unavailable inside an async function, so the
/// count is kept without a lock rather than pretending a lock is what makes it safe.
final class SpyResidencyGate: HybridResidencyGating, @unchecked Sendable {
    private let verdict: Bool
    private var releases = 0

    init(allowsTwoOnDeviceModelsResident verdict: Bool = false) {
        self.verdict = verdict
    }

    func allowsTwoOnDeviceModelsResident() -> Bool { verdict }

    @MainActor
    func evictResidentModel() async {
        releases += 1
    }

    @MainActor var releaseCount: Int { releases }
}
