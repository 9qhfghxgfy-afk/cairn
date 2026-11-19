import Foundation
import XCTest
@testable import CairnChatDomain

/// The consent state machine, with no sheet and no hardware behind it.
///
/// These are the rules the location tool stands on, and none of them need a device: an undecided chat
/// asks once and only once, a denied chat never asks again, a granted chat never asks at all, and an
/// undecided chat **with nobody to ask is a refusal** — silence is not permission, and a build with no
/// sheet wired to it must fail closed rather than open.
@MainActor
final class LocationConsentTests: XCTestCase {

    // MARK: - The policy, as a value

    func testThePolicyNamesWhatEachStateDoes() {
        XCTAssertEqual(LocationConsentPolicy.action(state: .granted, canAsk: true), .proceed,
                       "an answered yes does not interrupt anybody again")
        XCTAssertEqual(LocationConsentPolicy.action(state: .granted, canAsk: false), .proceed)
        XCTAssertEqual(
            LocationConsentPolicy.action(state: .denied, canAsk: true),
            .refuse(.permissionDenied),
            "\"no\" is an answer, not a prompt to ask again"
        )
        XCTAssertEqual(LocationConsentPolicy.action(state: .denied, canAsk: false),
                       .refuse(.permissionDenied))
        XCTAssertEqual(LocationConsentPolicy.action(state: .undecided, canAsk: true), .askOnce)
        XCTAssertEqual(
            LocationConsentPolicy.action(state: .undecided, canAsk: false),
            .refuse(.permissionDenied),
            "nobody to ask is a refusal, never a free pass"
        )
    }

    func testAnAnswerFilesTheStateItMeans() {
        XCTAssertEqual(LocationConsentPolicy.state(after: true), .granted)
        XCTAssertEqual(LocationConsentPolicy.state(after: false), .denied)
        XCTAssertTrue(LocationConsentState.granted.allowsLocation)
        XCTAssertFalse(LocationConsentState.denied.allowsLocation)
        XCTAssertFalse(LocationConsentState.undecided.isSettled, "undecided still owes a question")
        XCTAssertTrue(LocationConsentState.denied.isSettled, "a no is settled")
        XCTAssertEqual(LocationConsentState.allCases.count, 3)
    }

    // MARK: - The record the tool consults

    func testUndecidedWithNobodyToAskRefusesAndLeavesTheRecordUndecided() async {
        let gate = LocationConsentGate()
        let decision = await gate.authorize(asking: nil)
        XCTAssertEqual(decision, .refused(.permissionDenied))
        let state = await gate.state
        XCTAssertEqual(state, .undecided, "a question nobody could answer leaves the record honest")
    }

    func testTheFirstYesIsAskedOnceAndHeld() async {
        let counter = AskCounter(answer: true)
        let gate = LocationConsentGate()
        let first = await gate.authorize(asking: askedSheet(counter))
        XCTAssertEqual(first, .allowed)
        let second = await gate.authorize(asking: askedSheet(counter))
        XCTAssertEqual(second, .allowed)
        let asked = await counter.count
        XCTAssertEqual(asked, 1, "one question per person, not one per turn")
        let state = await gate.state
        XCTAssertEqual(state, .granted)
    }

    func testANoIsHeldTheSameWayAndStopsTheAsking() async {
        let counter = AskCounter(answer: false)
        let gate = LocationConsentGate()
        let first = await gate.authorize(asking: askedSheet(counter))
        XCTAssertEqual(first, .refused(.permissionDenied))
        let second = await gate.authorize(asking: askedSheet(counter))
        XCTAssertEqual(second, .refused(.permissionDenied))
        let asked = await counter.count
        XCTAssertEqual(asked, 1, "a refusal is not worn down by asking twice")
        let state = await gate.state
        XCTAssertEqual(state, .denied)
    }

    func testAGrantedRecordNeverPutsUpASheet() async {
        let counter = AskCounter(answer: true)
        let decision = await LocationConsentGate(state: .granted).authorize(
            asking: askedSheet(counter)
        )
        XCTAssertEqual(decision, .allowed)
        let asked = await counter.count
        XCTAssertEqual(asked, 0, "an answer already on the record does not interrupt the user")
    }

    func testADeniedRecordNeverPutsUpASheet() async {
        let counter = AskCounter(answer: true)
        let decision = await LocationConsentGate(state: .denied).authorize(
            asking: askedSheet(counter)
        )
        XCTAssertEqual(decision, .refused(.permissionDenied))
        let asked = await counter.count
        XCTAssertEqual(asked, 0, "the sheet must not reappear for a decision already made")
    }


    func testResetTakesTheRecordBackToUndecided() async {
        let counter = AskCounter(answer: true)
        let gate = LocationConsentGate()
        _ = await gate.authorize(asking: askedSheet(counter))
        let granted = await gate.state
        XCTAssertEqual(granted, .granted)
        await gate.reset()
        let cleared = await gate.state
        XCTAssertEqual(cleared, .undecided, "a cleared record owes the question again")
        _ = await gate.authorize(asking: askedSheet(counter))
        let asked = await counter.count
        XCTAssertEqual(asked, 2, "one question per record, so a cleared record asks once more")
    }

    /// Two turns reaching for the position at once must put up one sheet, not two, and both must be
    /// answered from the single answer.
    func testConcurrentCallsAskTheSheetOnceNotOnceEach() async {
        let counter = AskCounter(answer: true, pause: .milliseconds(40))
        let gate = LocationConsentGate()
        async let first = gate.authorize(asking: askedSheet(counter))
        async let second = gate.authorize(asking: askedSheet(counter))
        let decisions = [await first, await second]
        let asked = await counter.count
        XCTAssertEqual(asked, 1, "one sheet for one moment, whoever arrives at it")
        for decision in decisions {
            XCTAssertEqual(decision, .allowed)
        }
    }
}
