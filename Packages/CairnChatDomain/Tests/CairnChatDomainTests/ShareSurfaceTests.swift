import XCTest
@testable import CairnChatDomain

/// What the surface is allowed to list, and what it says about itself.
final class ShareSurfaceTests: XCTestCase {

    /// An engine double with nothing behind it: these tests are about which engines the surface is
    /// allowed to name, not about what a model answers.
    private struct StubEngine: InferenceProvider {
        let id: String
        let displayName: String
        var networkClass: NetworkClass { .onDevice }
        var capabilities: ProviderCapabilities { ProviderCapabilities() }
        var serverProfileID: UUID? { nil }
        func models() async throws -> [ModelInfo] { [] }
        func stream(_ request: GenerationRequest) -> AsyncThrowingStream<StreamChunk, any Error> {
            AsyncThrowingStream { $0.finish() }
        }
    }

    func testTheTableKeepsSelectionOrderAndDropsAnIDWithNoEngine() {
        let table = ShareEngineTable.build(
            from: [StubEngine(id: "ondevice-apple", displayName: "Apple model"),
                   StubEngine(id: "ollama-box", displayName: "LAN box")],
            selected: ["ollama-box", "ondevice-apple", "gone-engine"]
        )
        XCTAssertEqual(table.servedIDs, ["ollama-box", "ondevice-apple"], "the order the user ticked is the order advertised")
        XCTAssertNil(table.entry(forModelID: "gone-engine"), "an id with no live engine is dropped rather than served as a ghost")
        XCTAssertNotNil(table.provider(forModelID: "ollama-box"))
        XCTAssertNil(table.provider(forModelID: "gone-engine"))
    }

    func testADuplicateTickServesOneEngineNotTwo() {
        let table = ShareEngineTable.build(
            from: [StubEngine(id: "m", displayName: "Model")],
            selected: ["m", "m"]
        )
        XCTAssertEqual(table.servedIDs, ["m"])
    }

    func testAnEmptySelectionIsSaidToBeEmpty() {
        XCTAssertTrue(ShareEngineTable.build(from: [StubEngine(id: "m", displayName: "Model")], selected: []).isEmpty)
        XCTAssertTrue(ShareEngineTable().isEmpty)
        XCTAssertTrue(ShareSettings().sharedEngineIDs.isEmpty, "off by default is structural")
        XCTAssertFalse(ShareSettings().hasSelection)
        XCTAssertTrue(ShareSettings(sharedEngineIDs: ["m"]).hasSelection)
    }

    func testTheServedNameIsTheEngineIDSoNothingHasToStayInSync() {
        let entry = ShareModelEntry(id: "cairn-foundation", displayName: "Foundation", engineID: "cairn-foundation")
        XCTAssertEqual(entry.id, entry.engineID)
        XCTAssertNil(entry.parameterSize, "nothing is invented about an engine that says nothing")
    }

    func testTheBadgeIsUpForTheWholeTimeAPortIsOpen() {
        XCTAssertEqual(ShareStatusText.badge(.off), nil)
        XCTAssertEqual(ShareStatusText.badge(ShareServerStatus(state: .starting)), "Opening")
        XCTAssertEqual(ShareStatusText.badge(ShareServerStatus(state: .running)), "Sharing")
        XCTAssertNil(ShareStatusText.badge(ShareServerStatus(state: .stopping)))
        XCTAssertNil(ShareStatusText.badge(ShareServerStatus(state: .failed)))
    }

    func testTheRunningLineSaysWhatIsUpWithoutNamingAnAddress() {
        let status = ShareServerStatus(state: .running, port: 11434, servedModelIDs: ["a", "b"], clientCount: 1, boundAddress: "192.168.1.20")
        let line = ShareStatusText.statusLine(status)
        XCTAssertTrue(line.contains("11434"))
        XCTAssertTrue(line.contains("1 client connected"))
        XCTAssertTrue(line.contains("2 models shared"))
        XCTAssertFalse(line.contains("192.168"), "the address has its own line, and only appears on this screen")
        XCTAssertTrue(ShareStatusText.addressLine(status)?.contains("192.168.1.20") == true)
        XCTAssertNil(ShareStatusText.addressLine(.off), "nothing is bound, so there is nothing to type")
    }

    func testTheStoppedAndFailedLinesSayWhichRuleStoppedIt() {
        XCTAssertTrue(ShareStatusText.statusLine(.off).contains("Off"))
        XCTAssertTrue(ShareStatusText.statusLine(ShareServerStatus(state: .failed, failure: .noAddress)).contains("Wi-Fi"))
        XCTAssertTrue(ShareStatusText.statusLine(ShareServerStatus(state: .failed)).contains("port"))
        XCTAssertTrue(ShareStatusText.failureText(.tokenTooWeak).contains("16"))
        XCTAssertTrue(ShareStatusText.failureText(.needsModel).contains("tick"))
        XCTAssertTrue(ShareStatusText.failureText(.notLocalAddress).contains("public"))
    }

    /// A refusal is a code, and the line shown for it must not carry an address or a key.
    func testNoSaidLineCarriesAnAddressOrAKey() {
        let key = "0123456789abcdef0123456789abcdef"
        for refusal in ShareRefusal.allCases {
            XCTAssertFalse(ShareStatusText.failureText(refusal).contains(key))
            XCTAssertFalse(ShareStatusText.failureText(refusal).contains("192"))
        }
        XCTAssertFalse(ShareStatusText.failureText(nil).isEmpty)
    }

    /// Asking for one address is not the same as getting one, and the difference has to be said out loud.
    /// A port the system bound device-wide must never be described as pinned to the address printed on the
    /// line above it; a port that really is pinned needs no caveat at all.
    func testTheStatusSaysHowFirmlyThePortIsBound() {
        let pinned = ShareServerStatus(state: .running, port: 11434, servedModelIDs: ["a"], boundAddress: "192.168.1.20", bindScope: .chosenAddress)
        let wide = ShareServerStatus(state: .running, port: 11434, servedModelIDs: ["a"], boundAddress: "192.168.1.20", bindScope: .deviceWide)

        XCTAssertFalse(ShareStatusText.statusLine(pinned).contains("every interface"), "a pinned port says nothing extra")
        XCTAssertTrue(ShareStatusText.statusLine(wide).contains("every interface"))
        XCTAssertTrue(ShareStatusText.bindNote(pinned)?.contains("only") == true)
        XCTAssertTrue(ShareStatusText.bindNote(wide)?.contains("whole") == true)
        XCTAssertNil(ShareStatusText.bindNote(.off), "nothing is bound, so there is nothing to qualify")
        XCTAssertFalse((ShareStatusText.bindNote(wide) ?? "").contains("192"), "even the caveat names no address")
    }

    /// The two limits this milestone owes are stated, not hidden: a phone is not a server, and the
    /// Local Network permission really breaks the connection when it is denied.
    func testTheDocumentedLimitsAreSaidOutLoud() {
        XCTAssertTrue(ShareStatusText.suspensionNote.lowercased().contains("suspend"))
        XCTAssertTrue(ShareStatusText.suspensionNote.contains("foreground"))
        XCTAssertTrue(ShareStatusText.permissionNote.contains("Local Network"))
        XCTAssertTrue(ShareStatusText.tokenNote.contains("key"))
        XCTAssertTrue(ShareStatusText.servingNote(.off).contains("Off"))
        XCTAssertTrue(ShareStatusText.pathsNote.contains("/api/chat"))
        XCTAssertTrue(ShareStatusText.pathsNote.contains("/v1/chat/completions"))
    }
}
