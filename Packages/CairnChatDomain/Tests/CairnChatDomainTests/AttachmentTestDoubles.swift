import Foundation
@testable import CairnChatDomain

/// Collects the requests a session actually builds, so a test can read what would have gone out to a
/// server rather than trusting that it did.
final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [GenerationRequest] = []

    var all: [GenerationRequest] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    var last: GenerationRequest? { all.last }

    func record(_ request: GenerationRequest) {
        lock.lock()
        stored.append(request)
        lock.unlock()
    }
}

/// An engine that answers with one word and keeps every request it was handed.
///
/// The module's own mock cannot see images and records nothing, and both of those are the point of these
/// tests: whether an image is put on the wire, and whether a document's text ever is. The vision flag is a
/// constructor argument because the capability a provider declares is the only thing the gate is allowed to
/// read — there is no "usually supports images" in this app.
struct RecordingEngine: InferenceProvider {
    let id: String
    let seesImages: Bool
    let recorder: RequestRecorder

    init(
        id: String = "recording",
        seesImages: Bool = false,
        recorder: RequestRecorder = RequestRecorder()
    ) {
        self.id = id
        self.seesImages = seesImages
        self.recorder = recorder
    }

    var displayName: String { "Recording Engine" }
    var networkClass: NetworkClass { .onDevice }
    var samplingSupport: SamplingSupport { .none }

    var capabilities: ProviderCapabilities {
        ProviderCapabilities(
            streaming: true,
            thinking: false,
            toolCalling: false,
            vision: seesImages,
            modelListing: true,
            contextLengthAdjustable: true
        )
    }

    func models() async throws -> [ModelInfo] {
        [ModelInfo(id: "recorded-model", displayName: "Recorded Model", providerID: id)]
    }

    func stream(_ request: GenerationRequest) -> AsyncThrowingStream<StreamChunk, any Error> {
        recorder.record(request)
        return AsyncThrowingStream { continuation in
            continuation.yield(.content("Noted."))
            continuation.finish()
        }
    }
}
