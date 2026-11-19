import CairnChatDomain
import Foundation

/// Test doubles for the share surface, so the switch, the status line, the key and the foreground rule can
/// be proven in the simulator suite without a listener and without a secure enclave.
///
/// Both halves sit behind domain protocols — `ShareServing`, `ShareEngineListing`, `ShareTokenStoring` —
/// which is the seam `CairnAppUI` is allowed to hold. Nothing here opens a socket, and nothing here could:
/// these are the only shapes the screen is given.
@MainActor
final class FakeShareSurface: ShareServing, ShareEngineListing {
    struct Start {
        var port: Int
        var token: String
        var engineIDs: [String]
    }

    var decision: ShareStartDecision = .allowed
    /// The code a refused start leaves behind, so the screen's sentence can be checked against it.
    var refusal: ShareRefusal = .needsToken
    var starts: [Start] = []
    var stopCount = 0
    var catalog: [ShareModelEntry] = []
    var status = ShareServerStatus.off

    func start(port: Int, token: String, engineIDs: [String]) async -> ShareStartDecision {
        starts.append(Start(port: port, token: token, engineIDs: engineIDs))
        if decision.isAllowed {
            status = ShareServerStatus(
                state: .running,
                port: port,
                servedModelIDs: engineIDs,
                boundAddress: "127.0.0.1"
            )
        } else {
            status = ShareServerStatus(state: .failed, port: port, failure: refusal)
        }
        return decision
    }

    func stop() async {
        stopCount += 1
        status = .off
    }

    func availableEngines() -> [ShareModelEntry] { catalog }
}

/// A key vault with no Keychain in it. It records every write, which is how the tests prove the screen
/// never invents a key of its own and never shows a key the vault refused to keep.
@MainActor
final class FakeTokenVault: ShareTokenStoring {
    private(set) var stored: String?
    private(set) var writes: [String] = []
    private(set) var rotations = 0
    var draws = ["first-key-long-enough-to-pass", "second-key-long-enough-to-rotate"]
    var refusesToWrite = false

    func token() -> String? { stored }

    @discardableResult
    func save(_ token: String) -> Bool {
        if refusesToWrite { return false }
        writes.append(token)
        stored = token.isEmpty ? nil : token
        return true
    }

    func clear() {
        stored = nil
    }

    func rotate() -> String {
        let key = draws[min(rotations, draws.count - 1)]
        rotations += 1
        _ = save(key)
        return key
    }
}
