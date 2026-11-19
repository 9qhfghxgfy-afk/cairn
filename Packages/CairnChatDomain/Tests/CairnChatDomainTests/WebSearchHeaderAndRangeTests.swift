import Foundation
import XCTest
@testable import CairnChatDomain

/// The credential-header guard and the numeric ranges.
///
/// The guard is the interesting one. `.clinerules` has always said credential-bearing headers belong in the
/// Keychain, but the server-profile editor refused only `Authorization` — so `X-API-Key` or `Cookie` were a
/// legal way to put a secret into the persisted settings store by accident. One shared list now covers both
/// settings surfaces, and these tests are what keep it shared.
final class WebSearchHeaderAndRangeTests: XCTestCase {
    func testCredentialBearingNamesAreRefusedInOrdinaryHeaderRows() {
        for name in [
            "Authorization", "authorization", "X-API-Key", "api-key", "Proxy-Authorization", "Cookie",
            "Set-Cookie", "x-auth-token", "x-access-token",
        ] {
            XCTAssertTrue(
                HTTPHeaderNames.isCredentialBearing(name),
                "\(name) can only ever carry a credential"
            )
        }
        // A spelling trick lands in the same set, because matching drops case and inner whitespace.
        XCTAssertTrue(HTTPHeaderNames.isCredentialBearing("X -Api -Key"))
        XCTAssertTrue(HTTPHeaderNames.isCredentialBearing(" AUTHORIZATION "))
        XCTAssertFalse(HTTPHeaderNames.isCredentialBearing("X-Instance"))
        XCTAssertFalse(HTTPHeaderNames.isCredentialBearing(""))
    }

    func testTheValidatorRefusesThoseRowsAndAcceptsOrdinaryOnes() throws {
        for name in ["Authorization", "X-API-Key", "Cookie", "Proxy-Authorization", "X -Api -Key"] {
            XCTAssertThrowsError(
                try WebSearchProviderValidator.validateHeaderRows([name: "value"]),
                "\(name) must not be storable in a settings row"
            ) { error in
                XCTAssertEqual(error as? WebSearchProviderValidationError, .credentialInHeaderRow(name))
            }
        }
        XCTAssertNoThrow(
            try WebSearchProviderValidator.validateHeaderRows(["X-Instance": "home box"]),
            "an ordinary header row is storable"
        )
    }

    func testAnEmptyHeaderNameIsItsOwnProblem() {
        XCTAssertThrowsError(try WebSearchProviderValidator.validateHeaderRows([" ": "value"])) { error in
            XCTAssertEqual(error as? WebSearchProviderValidationError, .emptyHeaderName)
        }
    }

    /// A named secret header is a legitimate shape — a reverse proxy in front of an instance often wants
    /// `X-API-Key` — so the name is checked for form, not refused as a credential name.
    func testASecretHeaderNameIsJudgedOnFormAlone() {
        XCTAssertTrue(HTTPHeaderNames.isUsableSecretHeaderName("X-API-Key"))
        XCTAssertTrue(HTTPHeaderNames.isUsableSecretHeaderName("X_InstanceId"))
        XCTAssertFalse(HTTPHeaderNames.isUsableSecretHeaderName("has a space"))
        XCTAssertFalse(HTTPHeaderNames.isUsableSecretHeaderName("n"))
        XCTAssertFalse(HTTPHeaderNames.isUsableSecretHeaderName(String(repeating: "a", count: 65)))
    }

    func testServerProfilesShareTheSameGuardTheyAlwaysClaimed() throws {
        // The pre-existing rule, now backed by the shared list rather than one hardcoded name.
        XCTAssertThrowsError(
            try ServerProfile.validate(
                name: "Box", kind: .ollama, urlString: "http://192.168.1.20:11434",
                headers: ["X-API-Key": "hunter2"]
            )
        ) { error in
            XCTAssertEqual(
                error as? ServerProfileValidationError, .reservedHeader("X-API-Key")
            )
        }
        XCTAssertNoThrow(
            try ServerProfile.validate(
                name: "Box", kind: .ollama, urlString: "http://192.168.1.20:11434",
                headers: ["X-Instance": "home box"]
            )
        )
    }

    func testTheResultCountIsClampedIntoTheRangeTheControlOffers() {
        XCTAssertEqual(WebSearchProviderValidator.normalizedResultCount(2), 3)
        XCTAssertEqual(WebSearchProviderValidator.normalizedResultCount(5), 5)
        XCTAssertEqual(WebSearchProviderValidator.normalizedResultCount(99), 10)
        XCTAssertEqual(WebSearchSettings.default.resultCount, 5, "five results out of the box")
        XCTAssertEqual(WebSearchSettings().setResultCount(11).resultCount, 10)
        XCTAssertEqual(WebSearchSettings(resultCount: 0).resultCount, 3)
    }

    func testTheAppWideSettingIsTheOneThatReachesTheTool() {
        var settings = AppSettings.default
        XCTAssertNil(settings.webTools, "a fresh install stores nothing at all")
        XCTAssertEqual(settings.webSearch.activeProvider.kind, .duckDuckGo)
        settings.setWebSearchResultCount(8)
        XCTAssertEqual(settings.webSearch.resultCount, 8)
        settings.selectWebSearchProvider(id: UUID())
        XCTAssertEqual(settings.webSearch.activeProvider.kind, .duckDuckGo)
        XCTAssertEqual(settings.webSearch.revertNotice?.reason, .selectionLost)
        settings.grantWebSearchConsent(for: settings.webSearch.activeProvider)
        XCTAssertFalse(settings.webSearch.requiresConsentPrompt)
    }
}
