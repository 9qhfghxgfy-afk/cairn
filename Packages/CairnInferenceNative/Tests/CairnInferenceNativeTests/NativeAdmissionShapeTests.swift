import CairnChatDomain
import Foundation
import Testing
@testable import CairnInferenceNative

/// The gate shape, tested where it can be tested. The runtime is absent on this machine, so what is
/// worth proving is that the verdict carries a pool size, that a refusal really stops the turn before
/// the runtime is reached, and that a turn which fails still closes its ledger turn.
struct NativeAdmissionShapeTests {
    private func request() -> GenerationRequest {
        GenerationRequest(
            modelID: MLXNativeProvider.modelID,
            messages: [ChatMessagePayload(role: .user, text: "Hello")],
            config: ChatConfig()
        )
    }

    private var directory: URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("gate-shape")
    }

    @Test func theUnwiredGateAdmitsAndAsksForNoPoolAtAll() async {
        // No measurement, no pool. mlx-swift documents a cache limit of 0 as disabling buffer reuse:
        // smaller and slower, and the honest posture when nobody has measured what the phone can spare.
        let verdict = await NativeAdmissionUnwired().admitLoading(modelDirectory: directory)
        #expect(verdict == .admit(cacheLimitBytes: 0))
        #expect(verdict.cacheLimitBytes == 0)
        #expect(verdict.isAdmitted)
    }

    @Test func aRefusalCarriesItsSentenceAndNoCacheLimit() {
        let verdict = NativeAdmission.refuse(reason: "This model needs about 1.5 GiB")
        #expect(verdict.isAdmitted == false)
        #expect(verdict.cacheLimitBytes == nil)
    }

    @Test func aRefusingGateStopsTheTurnBeforeTheRuntimeIsAskedForAnything() async {
        let gate = RefusingAdmission()
        let here = directory
        let provider = MLXNativeProvider(directoryResolver: { here }, admission: gate)
        var thrown: NativeGenerationError?
        do {
            for try await _ in provider.stream(request()) {}
        } catch let issue as NativeGenerationError {
            thrown = issue
        } catch {
            Issue.record("unexpected error type: \(type(of: error))")
        }
        #expect(thrown == .insufficientMemory(reason: RefusingAdmission.reason))
        // Asked once, and nothing else. A refused turn never began, so there is no turn to close and no
        // residency to release — the ledger count stays where it was, which is what keeps every later
        // release from being deferred to a turn that will never end.
        #expect(await gate.log == ["admit"])
        #expect(await provider.residentModelId() == nil)
    }

    @Test func backgroundingAnIdleProviderIsSafeAndClaimsNothingResident() async {
        let provider = MLXNativeProvider()
        await provider.unloadIfIdle()
        await provider.flushCachesIfIdle()
        #expect(await provider.residentModelId() == nil)
    }
}

/// A gate that says no, and records that the provider closed the turn anyway.
///
/// `@unchecked Sendable` because its only state is the recorded list and the lock that guards it; the
/// protocol it conforms to requires `Sendable`, and a test double that has to count calls across the
/// provider's actor boundary needs mutable state.
final class RefusingAdmission: NativeMemoryAdmitting, @unchecked Sendable {
    static let reason = "This model needs about 1.5 GiB of memory and this app has 600 MiB."

    private let lock = NSLock()
    private var entries: [String] = []

    func admitLoading(modelDirectory: URL) async -> NativeAdmission {
        lock.lock(); entries.append("admit"); lock.unlock()
        return .refuse(reason: Self.reason)
    }

    func turnFinished(modelDirectory: URL) async {
        lock.lock(); entries.append("finished"); lock.unlock()
    }

    var log: [String] {
        lock.lock(); defer { lock.unlock() }; return entries
    }
}
