import Foundation
import XCTest
@testable import CairnChatDomain

/// The page-reading answer, as three states rather than one switch.
///
/// `web_fetch` reads a page whose address came out of a model's prose, so the destination was never chosen by
/// the user the way a search provider was. One answer for the whole tool is the honest shape — asking afresh
/// per host would be asking all day — but the answer has to be *asked*, which means "absent" has to be a state
/// of its own. A Bool that defaulted to false would be a refusal the user could never see the reason for, and
/// one that defaulted to true would be permission nobody granted.
final class WebFetchConsentRecordTests: XCTestCase {

    func testAFirstInstallHasNeverBeenAsked() {
        XCTAssertNil(AppSettings.default.webFetchAllowed, "absent is not permission")
    }

    func testAnAnswerEitherWayIsHeld() {
        var allowed = AppSettings.default
        allowed.setWebFetchAllowed(true)
        XCTAssertEqual(allowed.webFetchAllowed, true)

        var refused = AppSettings.default
        refused.setWebFetchAllowed(false)
        XCTAssertEqual(refused.webFetchAllowed, false, "\"no\" is an answer, not a blank to try again")
    }

    func testTheQuestionCanBePutAgainByClearingTheRecord() {
        var settings = AppSettings.default
        settings.setWebFetchAllowed(true)
        settings.setWebFetchAllowed(nil)
        XCTAssertNil(settings.webFetchAllowed, "forgetting an answer must actually forget it")
    }

    /// The whole point of the field being optional: a row written by a build that had no such key must decode
    /// as "never asked", not as a refusal, and must not fail the row — a settings record that fails to decode
    /// would take the user's theme down with it.
    func testARowWrittenWithoutTheFieldDecodesAsNeverAsked() throws {
        let legacy = #"{"outboundAllowed":true,"searxngURL":null}"#
        let tools = try JSONDecoder().decode(WebToolSettings.self, from: Data(legacy.utf8))
        XCTAssertNil(tools.fetchAllowed)
        XCTAssertTrue(tools.outboundAllowed, "and the rest of the row still reads")
    }

    func testTheFieldRoundTripsThroughJSON() throws {
        var settings = AppSettings.default
        settings.setWebFetchAllowed(false)
        let restored = try JSONDecoder().decode(
            WebToolSettings.self,
            from: JSONEncoder().encode(WebToolSettings(fetchAllowed: settings.webFetchAllowed))
        )
        XCTAssertEqual(restored.fetchAllowed, false)
    }
}
