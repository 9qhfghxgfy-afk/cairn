import XCTest
@testable import CairnChatDomain

/// The key check in front of every route.
final class ShareAuthChallengeTests: XCTestCase {

    private let key = "a-key-of-some-length-here"

    private func request(headers: [String: String]) -> ShareHTTPRequest {
        ShareHTTPRequest(method: "POST", path: "/api/chat", headers: headers)
    }

    func testEachSpellingRealClientsUseIsRead() {
        XCTAssertEqual(ShareAuthChallenge.presentedToken(in: request(headers: ["authorization": "Bearer \(key)"])), key)
        XCTAssertEqual(ShareAuthChallenge.presentedToken(in: request(headers: ["authorization": "bearer \(key)"])), key, "the scheme is case-insensitive")
        XCTAssertEqual(ShareAuthChallenge.presentedToken(in: request(headers: ["authorization": "Token \(key)"])), key)
        XCTAssertEqual(ShareAuthChallenge.presentedToken(in: request(headers: ["x-api-key": key])), key)
    }

    func testAnythingThatIsNotAKeyIsReadAsNoKey() {
        XCTAssertNil(ShareAuthChallenge.presentedToken(in: request(headers: [:])))
        XCTAssertNil(ShareAuthChallenge.presentedToken(in: request(headers: ["authorization": key])), "a bare value with no scheme is not a key")
        XCTAssertNil(ShareAuthChallenge.presentedToken(in: request(headers: ["authorization": "Basic \(key)"])), "Basic is not this surface's scheme")
        XCTAssertNil(ShareAuthChallenge.presentedToken(in: request(headers: ["authorization": "Bearer"])), "a scheme with nothing after it")
        XCTAssertNil(ShareAuthChallenge.presentedToken(in: request(headers: ["x-api-key": ""])), "an empty header is an absent header")
    }

    /// "You sent nothing" and "you sent the wrong thing" are different lines to show, and neither
    /// one may repeat what the client sent.
    func testTheOutcomeDistinguishesMissingFromWrong() {
        XCTAssertEqual(ShareAuthChallenge.check(request(headers: [:]), expected: key), .missing)
        XCTAssertEqual(ShareAuthChallenge.check(request(headers: ["authorization": "Bearer nope"]), expected: key), .mismatch)
        XCTAssertEqual(ShareAuthChallenge.check(request(headers: ["x-api-key": key]), expected: key), .accepted)
    }

    func testTheCompareDoesNotCareAboutLengthOrContent() {
        XCTAssertTrue(ShareAuthChallenge.matches("abc", "abc"))
        XCTAssertFalse(ShareAuthChallenge.matches("abc", "abd"))
        XCTAssertFalse(ShareAuthChallenge.matches("abc", "abcd"), "a shorter and a longer key are not equal")
        XCTAssertFalse(ShareAuthChallenge.matches("", "a"))
        XCTAssertTrue(ShareAuthChallenge.matches("", ""), "two empty keys are equal, which is why an empty key may never be stored")
    }
}
