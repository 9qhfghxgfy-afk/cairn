import Foundation
import XCTest
import CairnChatDomain
import CairnAppUI

/// A position source that counts how often it is reached, and can be made to fail on purpose.
///
/// The count is the point of every refusal test here: `get_location` must decline **before** it touches a
/// position source, so a tool that read a fix and then decided to withhold it would fail these rather than
/// look correct. The real `LocationProvider` is deliberately never started by a test — nothing here wakes a
/// radio or raises iOS's prompt, which is what makes them runnable in a CI simulator with no consent state.
@MainActor
final class CountingLocationSource: LocationFixProviding {
    private(set) var calls = 0
    var fix: LocationFix?
    var failure: LocationFailureReason?

    init(fix: LocationFix? = nil, failure: LocationFailureReason? = nil) {
        self.fix = fix
        self.failure = failure
    }

    /// Nonisolated because the protocol requirement is, and a main-actor method cannot satisfy one in
    /// Swift 6 — the same hop the real `LocationProvider` makes, so the double matches the source it stands
    /// in for instead of quietly differing from it in the one place the compiler checks.
    nonisolated func currentFix() async throws -> LocationFix {
        try await takeReading()
    }

    private func takeReading() async throws -> LocationFix {
        calls += 1
        if let failure { throw failure }
        guard let fix else { throw LocationFailureReason.unavailable }
        return fix
    }
}


/// The app-layer location join, run end to end on the simulator.
///
/// The consent decision is split across three modules by design — the domain holds the record
/// (`LocationConsentGate`), the UI holds the sheet (`LocationConsentModel`), the app layer holds the radio —
/// and a unit test inside any one of them passes with the join missing. That is exactly the bug worth
/// catching here: a tool that runs without ever asking, or asks a sheet nothing is wired to answer, or asks
/// again after being refused. So each test drives the seam the tool actually calls, answers it through the
/// model the root view draws the sheet from, and checks both the answer and the record it left behind.
@MainActor
final class LocationWiringTests: XCTestCase {

    private let reading = LocationFix(
        latitude: 52.486243,
        longitude: -1.890421,
        horizontalAccuracyMeters: 42,
        timestamp: Date(timeIntervalSince1970: 1_763_542_800)
    )

    private var turnOn: ToolExecutionContext {
        ToolExecutionContext(toolsEnabled: true, outboundWebAllowed: true)
    }

    private func call() -> ToolCall { ToolCall(id: "call-1", name: BuiltInTool.getLocation) }

    private func registry(_ wiring: LocationWiring) -> ToolRegistry {
        ToolRegistry(tools: [wiring.tool])
    }

    /// Waits until the question is genuinely on the sheet instead of assuming a slice of main-actor time.
    ///
    /// `async let` starts a child task, and the asking side only reaches the model once this task gives the
    /// main actor up. A fixed sleep is a guess about how long that takes: a loaded CI runner can stall past
    /// any constant, and a test that then answered a question nobody had asked would sit waiting forever for
    /// a reply nobody gave. Polling a condition with a short sleep turns the wait into a condition, and the
    /// deadline makes a broken join report itself instead of running to the job timeout.
    private func waitUntil(
        _ condition: () -> Bool,
        timeout: Duration = .seconds(2)
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            if clock.now >= deadline { return false }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return true
    }

    // MARK: - The order: sheet first, radio only afterwards

    /// The whole privacy claim of this tool in one test: the tool stops in front of the sheet with the radio
    /// still asleep, and only reads once a person has said yes.
    func testTheToolStopsAtTheSheetWithTheRadioStillAsleep() async {
        let source = CountingLocationSource(fix: reading)
        let wiring = LocationWiring.install(source: source)
        // Everything the child task needs is bound here first. `async let` may run its body in a context that
        // cannot be handed `self`, and a `XCTestCase` is non-Sendable — so naming an instance method or a
        // computed property inside it means sending the test object across an isolation boundary, which CI
        // rejected at 44629653191. The registry, the call and the context are all values; the test object is not.
        let request = call()
        let toolRegistry = registry(wiring)
        let context = turnOn
        async let outcome = toolRegistry.execute(request, context: context)

        let appeared = await waitUntil { wiring.consent.isAsking }
        XCTAssertTrue(appeared, "the tool must raise the sheet before it reads anything")
        let callsWhileAsked = source.calls
        XCTAssertEqual(callsWhileAsked, 0, "and it must not reach the radio while the answer is still out")

        wiring.consent.resolve(allow: true)
        let result = await outcome
        XCTAssertNil(result.error, "a yes is an answer, not a fresh failure: \(result.output)")
        XCTAssertEqual(result.output, reading.modelText, "the reading reaches the model unchanged")
        XCTAssertTrue(result.output.contains("52.486"), "as coordinates the device reported: \(result.output)")
        XCTAssertTrue(result.output.contains("-1.8904"))
        XCTAssertFalse(result.output.contains("locality:"), "and nothing is geocoded into the answer")
        let callsAfter = source.calls
        XCTAssertEqual(callsAfter, 1, "the radio is reached exactly once, after the yes")
        let state = await wiring.gate.state
        XCTAssertEqual(state, .granted)

        let again = await registry(wiring).execute(call(), context: turnOn)
        XCTAssertNil(again.error, "an allowed record answers without interrupting anyone twice")
        let laterCalls = source.calls
        XCTAssertEqual(laterCalls, 2, "but the position is read again, because it is a new question")
        XCTAssertFalse(wiring.consent.isAsking, "and the sheet stays down")
    }

    // MARK: - Refusing, including by swiping the sheet away

    /// Closing the sheet is not postponing the question. It is a no, recorded as one — otherwise the next
    /// turn asks again and a person learns that warnings can be waved off until they stop appearing.
    func testWalkingAwayFromTheSheetIsARefusalThatNeverReachesTheRadio() async {
        let source = CountingLocationSource(fix: reading)
        let wiring = LocationWiring.install(source: source)
        let request = call()
        let toolRegistry = registry(wiring)
        let context = turnOn
        async let outcome = toolRegistry.execute(request, context: context)

        let appeared = await waitUntil { wiring.consent.isAsking }
        XCTAssertTrue(appeared, "walking away only means something if there was a sheet to walk away from")

        // No `resolve` call at all: this is the sheet being closed, which `CairnRootView` routes here.
        wiring.consent.declineUnanswered()
        let result = await outcome
        XCTAssertEqual(result.error, .locationDenied)
        let state = await wiring.gate.state
        XCTAssertEqual(state, .denied, "a dismissed warning is recorded as a refusal")
        let calls = source.calls
        XCTAssertEqual(calls, 0, "and a refusal never reaches the radio")

        let again = await registry(wiring).execute(call(), context: turnOn)
        XCTAssertEqual(again.error, .locationDenied, "a refusal is not worn down by asking again")
        let laterCalls = source.calls
        XCTAssertEqual(laterCalls, 0, "and the second call is answered from the record, not from the hardware")
        XCTAssertFalse(wiring.consent.isAsking, "the sheet does not come back for a decided question")
    }

    /// Two chats can want a position in the same instant. They get one sheet and one answer, because a second
    /// sheet stacked on the first cannot be answered by the buttons on it — and a silent refusal for whoever
    /// arrived second would be an answer nobody gave.
    func testTwoTurnsThatAskAtOnceShareOneSheet() async {
        let source = CountingLocationSource(fix: reading)
        let wiring = LocationWiring.install(source: source)
        let request = call()
        let toolRegistry = registry(wiring)
        let context = turnOn
        async let first = toolRegistry.execute(request, context: context)
        async let second = toolRegistry.execute(request, context: context)

        let appeared = await waitUntil { wiring.consent.isAsking }
        XCTAssertTrue(appeared)
        wiring.consent.resolve(allow: false)

        let a = await first
        let b = await second
        XCTAssertEqual(a.error, .locationDenied)
        XCTAssertEqual(b.error, .locationDenied, "the second turn is answered by the same sheet, not a new one")
        let calls = source.calls
        XCTAssertEqual(calls, 0, "neither turn reaches the radio")
        XCTAssertFalse(wiring.consent.isAsking, "one answer closed both waits")
    }

    // MARK: - iOS decides separately

    /// The app's own yes does not settle iOS's prompt. When the system refuses, the model is told it was
    /// declined — not that the device is broken — and the tool does not retry, because a model cannot talk
    /// a person into changing a permission.
    func testIOSRefusingTheSystemPromptEndsTheCallAsARefusal() async {
        let source = CountingLocationSource(failure: .permissionDenied)
        let wiring = LocationWiring.install(source: source)
        await wiring.gate.resolve(allow: true)

        let result = await registry(wiring).execute(call(), context: turnOn)
        XCTAssertEqual(result.error, .locationDenied)
        XCTAssertFalse(result.error?.modelCanRetry ?? true, "a person has to change this, not the model")
        let calls = source.calls
        XCTAssertEqual(calls, 1, "one attempt, no retry loop behind a refusal")
        XCTAssertFalse(wiring.consent.isAsking, "the record was already answered, so no sheet came up")
        let state = await wiring.gate.state
        XCTAssertEqual(state, .granted, "our record stands — the denial belongs to iOS")
    }

    /// A switched-off Location Service is a different fact from a refused permission, and it needs different
    /// words: one is a setting to flip, the other is a decision a person made. Collapsing them teaches a
    /// person that the tool is broken when nothing is wrong with it.
    func testServicesOffIsAnsweredAsDisabledRatherThanAsADenial() async {
        let source = CountingLocationSource(failure: .servicesDisabled)
        let wiring = LocationWiring.install(source: source)
        await wiring.gate.resolve(allow: true)

        let result = await registry(wiring).execute(call(), context: turnOn)
        XCTAssertEqual(result.error, .locationDisabled)
        XCTAssertFalse(result.error?.modelCanRetry ?? true, "no query fixes a service that is off")
        XCTAssertTrue(
            (result.detail ?? result.output).contains("Location Services"),
            "and the reason names the thing to change: \(result.detail ?? result.output)"
        )
    }

    /// The registry is rebuilt whenever a switch moves, so the consent record must travel with the tool
    /// rather than be created inside it. A fresh gate per rebuild would put the sheet back up in front of
    /// someone who has already answered — which is how a permission prompt becomes noise.
    func testARebuiltRegistryCarriesTheSameAnswer() async {
        let source = CountingLocationSource(fix: reading)
        let wiring = LocationWiring.install(source: source)
        let gate = wiring.gate
        await gate.resolve(allow: false)

        // `ToolWiring` reinstalls every tool on each rebuild; passing the gate through is what keeps an
        // unrelated settings change from re-asking a settled question.
        let rebuilt = LocationWiring.install(gate: gate, source: source)
        let result = await registry(rebuilt).execute(call(), context: turnOn)
        XCTAssertEqual(result.error, .locationDenied)
        XCTAssertFalse(rebuilt.consent.isAsking, "a rebuild does not re-ask a question already answered")
        let calls = source.calls
        XCTAssertEqual(calls, 0, "and the record, not the hardware, is what answered")
    }

    /// Moving the `Tools` switch off has to stop the tool where it stands rather than merely hide the menu
    /// item: a turn that is already streaming can still be holding a call in flight.
    func testFlippingTheSwitchStopsTheToolWhereItStands() async {
        let source = CountingLocationSource(fix: reading)
        let wiring = LocationWiring.install(source: source)
        await wiring.gate.resolve(allow: true)
        let switchedOff = ToolExecutionContext(toolsEnabled: false, outboundWebAllowed: true)

        let result = await registry(wiring).execute(call(), context: switchedOff)
        XCTAssertEqual(result.error, .toolsOff)
        let calls = source.calls
        XCTAssertEqual(calls, 0, "the switch is checked before the radio is reached, not after")
        XCTAssertFalse(wiring.consent.isAsking, "and it does not ask permission to do something already off")
    }

    /// A position read asks nothing of anybody but the person holding the phone, so it must never be
    /// entangled with the outbound web opt-in — no badge, no acknowledgement, no network class. This is the
    /// fact that keeps `get_location` out of the badge's scope, and it is pinned here because this is the
    /// layer where a real CoreLocation source gets attached.
    func testTheAssembledToolStillDeclaresItselfOnDevice() {
        let tool = LocationWiring.install(source: CountingLocationSource(fix: reading)).tool
        XCTAssertEqual(tool.definition.name, BuiltInTool.getLocation)
        XCTAssertEqual(tool.definition.networkClass, .onDevice)
        XCTAssertFalse(tool.definition.requiresPublicInternet)
        XCTAssertFalse(tool.definition.requiresNetwork, "a radio is not a socket")
    }

    /// A chat that has never opted in to the outbound web still gets `get_location`. The badge, the web
    /// acknowledgement and this tool have nothing to do with each other, and a build that gated a position
    /// read on a web acknowledgement would be implying that reading a radio sends something somewhere.
    func testTheToolIsAdvertisedWithoutTheWebOptIn() {
        let tool = LocationWiring.install(source: CountingLocationSource(fix: reading)).tool
        let noWeb = ToolExecutionContext(toolsEnabled: true, outboundWebAllowed: false)
        let advertised = ToolRegistry(tools: [tool]).availableDefinitions(context: noWeb)
        XCTAssertEqual(advertised.map(\.name), [BuiltInTool.getLocation])
    }
}



