import Foundation
import XCTest
@testable import CairnChatDomain

/// Endpoint and provider-kind rules.
///
/// The address rules are the privacy rules, so they are tested against real-shaped hosts: the documented
/// example LAN address, a loopback, a tunnel address, a `.local` name, a bare hostname, and a public host
/// that has no business being reached over http.
final class WebSearchProviderValidationTests: XCTestCase {
    private let lan = "http://192.168.1.20:8888"

    private func check(
        endpoint: String,
        kind: WebSearchProviderKind = .searxng,
        timeout: Int = 15,
        credential: WebSearchCredentialShape? = nil,
        hasCredential: Bool = false,
        language: String? = nil,
        categories: [String] = [],
        name: String = "Box",
        isUserAdded: Bool = true
    ) throws -> WebSearchProviderValidationError? {
        do {
            try WebSearchProviderValidator.validate(
                name: name, kind: kind, endpoint: endpoint, categories: categories,
                language: language, timeoutSeconds: timeout, credentialShape: credential,
                hasCredential: hasCredential, isUserAdded: isUserAdded
            )
            return nil
        } catch let error as WebSearchProviderValidationError {
            return error
        }
    }

    func testAPrivateAddressMayBeReachedOverPlainHTTP() throws {
        for host in [
            "http://192.168.1.20:8888", "http://127.0.0.1:8080", "http://10.8.0.1:8888",
            "http://box.local:8888", "http://searxng:8888",
        ] {
            XCTAssertNil(try check(endpoint: host), "\(host) is a private path; TLS adds nothing to it")
        }
    }

    func testAPublicAddressOverHTTPIsRefusedRatherThanBadged() throws {
        XCTAssertEqual(
            try check(endpoint: "http://search.example.com"), .plaintextPublicInternet,
            "the user's own words must not cross the internet in the clear"
        )
        XCTAssertNil(try check(endpoint: "https://search.example.com/searxng"), "a proxy subpath is fine")
    }

    func testAnAddressWithoutAUseableSchemeGetsItsOwnMessage() throws {
        XCTAssertEqual(try check(endpoint: "search.example.com"), .invalidEndpoint)
        XCTAssertEqual(try check(endpoint: "ftp://search.example.com"), .wrongScheme("ftp"))
        XCTAssertEqual(try check(endpoint: "   "), .invalidEndpoint)
        XCTAssertEqual(
            try check(endpoint: "https://user:pw@search.example.com"), .userInfoInEndpoint,
            "a token in the address would land in the settings blob"
        )
    }

    func testTheBuiltInAndCloudAddressesCannotBeRewritten() throws {
        XCTAssertEqual(
            try check(
                endpoint: "https://evil.example.com", kind: .duckDuckGo,
                name: "DuckDuckGo", isUserAdded: false
            ), .fixedEndpointLocked(.duckDuckGo),
            "a row called DuckDuckGo may not be pointed at some other company"
        )
        XCTAssertNil(
            try check(
                endpoint: WebSearchProviderKind.duckDuckGoEndpoint, kind: .duckDuckGo,
                name: "DuckDuckGo", isUserAdded: false
            )
        )
    }

    func testOnlyASearXNGRowCanBeAddedByHand() throws {
        XCTAssertEqual(
            try check(endpoint: WebSearchProviderKind.duckDuckGoEndpoint, kind: .duckDuckGo),
            .notUserAddable(.duckDuckGo)
        )
        XCTAssertEqual(
            try check(
                endpoint: WebSearchProviderKind.ollamaCloudEndpoint, kind: .ollamaCloud,
                credential: .bearer, hasCredential: true
            ), .notUserAddable(.ollamaCloud),
            "the cloud row is materialised from its profile, never typed in"
        )
    }

    func testACloudRowWithoutAKeyIsRefusedRatherThanOffered() throws {
        XCTAssertEqual(
            try check(
                endpoint: WebSearchProviderKind.ollamaCloudEndpoint, kind: .ollamaCloud,
                name: "Ollama Cloud", isUserAdded: false
            ), .credentialRequired(.ollamaCloud)
        )
    }

    func testACredentialOnTheBuiltInRowHasNowhereHonestToGo() throws {
        XCTAssertEqual(
            try check(
                endpoint: WebSearchProviderKind.duckDuckGoEndpoint, kind: .duckDuckGo,
                credential: .bearer, hasCredential: true, name: "DuckDuckGo", isUserAdded: false
            ), .fixedEndpointLocked(.duckDuckGo)
        )
    }

    func testASecretHeaderNameIsCheckedForForm() throws {
        XCTAssertEqual(
            try check(endpoint: lan, credential: .secretHeader(name: "X API Key")),
            .secretHeaderNameInvalid("X API Key")
        )
        XCTAssertEqual(try check(endpoint: lan, credential: .secretHeader(name: "")),
                       .secretHeaderNameInvalid(""))
        XCTAssertNil(try check(endpoint: lan, credential: .secretHeader(name: "X-API-Key"), hasCredential: true))
        XCTAssertNil(try check(endpoint: lan, credential: .bearer, hasCredential: true))
    }

    func testLanguageCategoryAndTimeoutAreChecked() throws {
        XCTAssertEqual(try check(endpoint: lan, language: "english"), .languageInvalid)
        XCTAssertNil(try check(endpoint: lan, language: "en"))
        XCTAssertNil(try check(endpoint: lan, language: "zh-Hans-CN"))
        XCTAssertEqual(try check(endpoint: lan, categories: ["general news"]), .categoryInvalid)
        XCTAssertNil(try check(endpoint: lan, categories: ["general", "news", "it"]))
        XCTAssertEqual(try check(endpoint: lan, timeout: 120), .timeoutOutOfRange)
        XCTAssertEqual(try check(endpoint: lan, name: "  "), .missingName)
    }
}
