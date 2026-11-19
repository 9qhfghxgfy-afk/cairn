import Foundation
import XCTest
@testable import CairnChatDomain

/// The names a refused position comes back under, and the shape of a fix that is allowed through.
///
/// A model given an empty result writes its own answer; a model given `.timedOut` with a sentence saying
/// the device did not answer writes a sentence saying the device did not answer. That difference is what
/// these tests hold, together with the rule that a reading too broken to be a place never reaches a
/// prompt at all.
@MainActor
final class GetLocationFailureTests: XCTestCase {

    private var granted: LocationConsentGate { LocationConsentGate(state: .granted) }

    private var turnOn: ToolExecutionContext {
        ToolExecutionContext(toolsEnabled: true, outboundWebAllowed: false)
    }

    private func call() -> ToolCall { ToolCall(id: "call-1", name: BuiltInTool.getLocation) }

    private func run(
        _ source: RecordingLocationSource, budget: Duration = .milliseconds(80)
    ) async -> ToolOutcome {
        let tool = GetLocationTool(source: source, consent: granted, budget: budget)
        return await ToolRegistry(tools: [tool]).execute(call(), context: turnOn)
    }

    func testEachLocationFailureCarriesItsOwnToolError() {
        XCTAssertEqual(LocationFailureReason.permissionDenied.toolError, .locationDenied)
        XCTAssertEqual(LocationFailureReason.servicesDisabled.toolError, .locationDisabled)
        XCTAssertEqual(LocationFailureReason.timedOut.toolError, .timedOut)
        XCTAssertEqual(LocationFailureReason.unavailable.toolError, .unavailable)
        XCTAssertTrue(LocationFailureReason.timedOut.modelCanRetry, "a fix that never arrived may arrive")
        XCTAssertFalse(LocationFailureReason.permissionDenied.modelCanRetry,
                       "a permission is not something a model can fix by trying again")
        XCTAssertFalse(LocationFailureReason.servicesDisabled.modelCanRetry)
        XCTAssertFalse(LocationFailureReason.unavailable.modelCanRetry)
        for reason in LocationFailureReason.allCases {
            XCTAssertFalse(reason.userText.isEmpty)
            // Nothing a location refusal says may name an endpoint: this tool has none.
            XCTAssertFalse(reason.userText.contains("http"))
        }
    }

    func testServicesDisabledComesBackAsItsOwnFailure() async {
        let outcome = await run(
            RecordingLocationSource(failure: LocationFailureReason.servicesDisabled)
        )
        XCTAssertEqual(outcome.error, .locationDisabled)
        XCTAssertTrue(outcome.modelText.contains("Location Services"), outcome.modelText)
    }

    func testAUnavailableDeviceSaysSoRatherThanGivingNoAnswer() async {
        let outcome = await run(RecordingLocationSource())
        XCTAssertEqual(outcome.error, .unavailable)
        XCTAssertFalse(outcome.modelText.isEmpty, "an empty result is a model filling the gap itself")
    }

    func testASourceThatNeverAnswersIsBounded() async {
        let slow = LocationFix(latitude: 1, longitude: 1, horizontalAccuracyMeters: 5)
        let outcome = await run(
            RecordingLocationSource(fix: slow, hold: .seconds(30)),
            budget: .milliseconds(50)
        )
        XCTAssertEqual(outcome.error, .timedOut)
        XCTAssertTrue(outcome.modelText.contains("did not produce a position"), outcome.modelText)
    }

    func testAnImplausibleReadingIsRefusedRatherThanSentToTheModel() async {
        let impossible = LocationFix(latitude: 137, longitude: 412, horizontalAccuracyMeters: -5)
        XCTAssertFalse(impossible.isPlausible, "a coordinate outside the ranges is a broken source")
        let outcome = await run(RecordingLocationSource(fix: impossible))
        XCTAssertEqual(outcome.error, .unavailable)
        XCTAssertFalse(outcome.output.contains("137"), "the broken numbers do not travel")
    }

    // MARK: - The shape of a fix that is allowed through

    func testAFixIsRoundedToThePrecisionTheHardwareClaims() {
        let fix = LocationFix(
            latitude: 47.6062091,
            longitude: -122.3320705,
            horizontalAccuracyMeters: 24.7,
            timestamp: Date(timeIntervalSince1970: 1_763_542_800)
        )
        XCTAssertEqual(fix.latitude, 47.60621, "five decimals, no more")
        XCTAssertEqual(fix.longitude, -122.33207)
        XCTAssertEqual(fix.accuracyMeters, 25)
        XCTAssertTrue(fix.isPlausible)
        XCTAssertTrue(fix.modelText.contains("2025-11-19T09:00:00Z"), fix.modelText)
        XCTAssertFalse(fix.modelText.contains("locality"), "a fix with no place on it does not invent one")
        XCTAssertTrue(fix.modelText.contains("not an address"), fix.modelText)
    }

    func testAPlaceTheSourceAlreadyHasTravelsAndIsLabelled() {
        let placed = LocationFix(
            latitude: 51.500729, longitude: -0.124625, horizontalAccuracyMeters: 8,
            locality: "  London  ", region: "   "
        )
        XCTAssertEqual(placed.locality, "London", "trimmed on the way in")
        XCTAssertNil(placed.region, "an empty region is the same fact as no region")
        XCTAssertTrue(placed.modelText.contains("locality: London"))
        XCTAssertFalse(placed.modelText.contains("region:"))
    }

    func testThePolesAndTheDateLineArePlacesAndGarbageIsNot() {
        XCTAssertTrue(LocationFix(latitude: 90, longitude: 180, horizontalAccuracyMeters: 0).isPlausible)
        XCTAssertFalse(LocationFix(latitude: 90.1, longitude: 0, horizontalAccuracyMeters: 1).isPlausible)
        XCTAssertFalse(LocationFix(latitude: .nan, longitude: 0, horizontalAccuracyMeters: 1).isPlausible)
        XCTAssertFalse(LocationFix(latitude: 0, longitude: 0, horizontalAccuracyMeters: -1).isPlausible)
    }


    /// A chat written before `get_location` existed has no switch for it on disk, and must still read: a
    /// missing key means "this chat predates the switch", not "this configuration is broken".
    func testAToggleBlobFromBeforeLocationStillDecodes() throws {
        let legacy = Data("""
            {"isEnabled":true,"webSearch":false,"webFetch":false,"wikiSearch":false,\
            "calculator":true,"composeMail":false}
            """.utf8)
        let decoded = try JSONDecoder().decode(ToolToggleSet.self, from: legacy)
        XCTAssertTrue(decoded.isEnabled, "the chip the chat already had survives")
        XCTAssertFalse(decoded.webSearch, "and so does the switch the user turned off")
        XCTAssertTrue(decoded.getLocation, "a switch nobody has seen yet is on, as in a new chat")
        XCTAssertTrue(decoded.isOn(BuiltInTool.getLocation))
        XCTAssertEqual(decoded.enabledToolNames, [BuiltInTool.calculator, BuiltInTool.getLocation])
    }

    func testTheNewSwitchRoundTripsAndCanBeTurnedOff() throws {
        var toggle = ToolToggleSet.armed
        toggle.setOn(BuiltInTool.getLocation, false)
        let decoded = try JSONDecoder().decode(
            ToolToggleSet.self, from: JSONEncoder().encode(toggle)
        )
        XCTAssertEqual(decoded, toggle)
        XCTAssertFalse(decoded.isOn(BuiltInTool.getLocation))
        XCTAssertEqual(decoded.enabledToolNames, BuiltInTool.allNames.filter {
            $0 != BuiltInTool.getLocation
        })
    }
}

