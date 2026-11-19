import Foundation
import XCTest
@testable import CairnChatDomain

/// Consent before hardware, proved through the registry the way a turn calls it.
///
/// Each test here asserts a source call count as well as an outcome, because "we asked first" is only
/// worth what the count proves. A tool that reads a position and then declines to send it is a bug this
/// file exists to catch, and nothing else in the suite would see it.
@MainActor
final class GetLocationConsentEnforcementTests: XCTestCase {

    private let reading = LocationFix(
        latitude: 51.500729,
        longitude: -0.124625,
        horizontalAccuracyMeters: 9,
        timestamp: Date(timeIntervalSince1970: 1_763_542_800)
    )

    private var turnOn: ToolExecutionContext {
        ToolExecutionContext(toolsEnabled: true, outboundWebAllowed: false)
    }

    private func call() -> ToolCall { ToolCall(id: "call-1", name: BuiltInTool.getLocation) }

    private func run(
        _ source: RecordingLocationSource,
        consent: LocationConsentGate,
        asker: LocationConsentRequester? = nil
    ) async -> ToolOutcome {
        let tool = GetLocationTool(source: source, consent: consent, asker: asker)
        return await ToolRegistry(tools: [CalculatorTool(), tool]).execute(call(), context: turnOn)
    }

    func testUndecidedRefusesAndReachesNoSourceAtAll() async {
        let source = RecordingLocationSource(fix: reading)
        let outcome = await run(source, consent: LocationConsentGate())
        XCTAssertFalse(outcome.succeeded)
        XCTAssertEqual(outcome.error, .locationDenied)
        let calls = source.calls
        XCTAssertEqual(calls, 0, "nothing is read before anybody is asked")
        XCTAssertTrue(outcome.modelText.contains("get_location"))
        XCTAssertTrue(outcome.modelText.contains("locationDenied"), outcome.modelText)
    }

    func testUndecidedWithNobodyToAskRefusesWithoutAQuestion() async {
        let source = RecordingLocationSource(fix: reading)
        let counter = AskCounter(answer: true)
        let outcome = await run(source, consent: LocationConsentGate(), asker: nil)
        XCTAssertEqual(outcome.error, .locationDenied)
        let calls = source.calls
        let asked = await counter.count
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(asked, 0, "a sheet that does not exist cannot be asked")
    }

    func testAYesIsAskedOnceAndThenReturnsThePosition() async {
        let source = RecordingLocationSource(fix: reading)
        let counter = AskCounter(answer: true)
        let gate = LocationConsentGate()
        let outcome = await run(source, consent: gate, asker: { await counter.ask() })
        XCTAssertTrue(outcome.succeeded, outcome.modelText)
        XCTAssertTrue(outcome.output.contains("latitude: 51.50073"), outcome.output)
        XCTAssertTrue(outcome.output.contains("horizontal accuracy: 9 m"), outcome.output)
        let calls = source.calls
        let asked = await counter.count
        XCTAssertEqual(calls, 1, "the position is read once the answer is in")
        XCTAssertEqual(asked, 1)

        let second = await run(source, consent: gate, asker: { await counter.ask() })
        XCTAssertTrue(second.succeeded)
        let laterAsked = await counter.count
        let laterCalls = source.calls
        XCTAssertEqual(laterAsked, 1, "the next turn does not interrupt anybody again")
        XCTAssertEqual(laterCalls, 2, "and it does read the position again")
    }

    func testWalkingAwayFromTheSheetIsANoAndReadsNothing() async {
        let source = RecordingLocationSource(fix: reading)
        let gate = LocationConsentGate()
        // The sheet closed without an answer: the asker resolves the record to "no" and says no, which is
        // what `LocationConsentModel.declineUnanswered` does on a real device.
        let outcome = await run(
            source, consent: gate,
            asker: { await gate.resolve(allow: false); return false }
        )
        XCTAssertEqual(outcome.error, .locationDenied)
        let calls = source.calls
        let state = await gate.state
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(state, .denied, "a dismissed question is recorded as a refusal")
    }

    func testADeniedRecordNeverReachesTheSourceAndNeverReasks() async {
        let source = RecordingLocationSource(fix: reading)
        let counter = AskCounter(answer: true)
        let gate = LocationConsentGate(state: .denied)
        let outcome = await run(source, consent: gate, asker: { await counter.ask() })
        XCTAssertEqual(outcome.error, .locationDenied)
        let calls = source.calls
        let asked = await counter.count
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(asked, 0, "\"no\" is an answer, not a prompt to ask again")
    }

    func testAChatWithItsToolsOffIsRefusedBeforeAnythingElse() async {
        let source = RecordingLocationSource(fix: reading)
        let tool = GetLocationTool(source: source, consent: LocationConsentGate(state: .granted))
        let outcome = await ToolRegistry(tools: [tool]).execute(
            call(), context: ToolExecutionContext(toolsEnabled: false)
        )
        XCTAssertEqual(outcome.error, .toolsOff)
        let calls = source.calls
        XCTAssertEqual(calls, 0, "the chip is checked before the record, and both before the radio")
    }
}
