import XCTest
@testable import CairnChatDomain

final class RemoteServerProfileTests: XCTestCase {

    // MARK: canonicalize

    func testCanonicalizeAcceptsHTTPSWithoutPath() {
        XCTAssertEqual(
            ServerProfile.canonicalize(urlString: "https://your-host.your-tailnet.ts.net"),
            "https://your-host.your-tailnet.ts.net"
        )
        XCTAssertEqual(
            ServerProfile.canonicalize(urlString: "https://your-host.your-tailnet.ts.net/"),
            "https://your-host.your-tailnet.ts.net"
        )
        XCTAssertEqual(
            ServerProfile.canonicalize(urlString: "HTTPS://Example.COM:8443"),
            "https://example.com:8443"
        )
    }

    func testCanonicalizeRejectsNonHTTPSExceptLoopback() {
        XCTAssertNil(ServerProfile.canonicalize(urlString: "http://192.168.1.5:1234"))
        XCTAssertNil(ServerProfile.canonicalize(urlString: "http://ollama.internal:11434"))
        XCTAssertNil(ServerProfile.canonicalize(urlString: "ftp://host"))
        XCTAssertNil(ServerProfile.canonicalize(urlString: "192.168.1.5:1234"))
        XCTAssertNotNil(ServerProfile.canonicalize(urlString: "http://localhost:11434"))
        XCTAssertNotNil(ServerProfile.canonicalize(urlString: "http://127.0.0.1:1234"))
    }

    func testCanonicalizeRejectsUserInfoPathAndQuery() {
        XCTAssertNil(ServerProfile.canonicalize(urlString: "https://token@host"))
        XCTAssertNil(ServerProfile.canonicalize(urlString: "https://host/v1"))
        XCTAssertNil(ServerProfile.canonicalize(urlString: "https://host?x=1"))
        XCTAssertNil(ServerProfile.canonicalize(urlString: "   "))
    }

    // MARK: validate

    func testValidateRejectsReservedAndEmptyHeaders() {
        XCTAssertThrowsError(
            try ServerProfile.validate(name: "s", urlString: "https://host",
                                       headers: ["Authorization": "Bearer x"])
        ) { error in
            guard case ServerProfileValidationError.reservedHeader = error else {
                return XCTFail("expected reservedHeader, got \(error)")
            }
        }
        XCTAssertThrowsError(
            try ServerProfile.validate(name: "s", urlString: "https://host",
                                       headers: [" authorization ": "x"])
        )
        XCTAssertThrowsError(
            try ServerProfile.validate(name: "s", urlString: "https://host",
                                       headers: ["  ": "x"])
        )
    }

    func testValidateRejectsBadNameSchemeAndUserInfo() {
        XCTAssertThrowsError(
            try ServerProfile.validate(name: "  ", urlString: "https://host", headers: [:])
        )
        XCTAssertThrowsError(
            try ServerProfile.validate(name: "s", urlString: "http://10.0.0.9:11434", headers: [:])
        ) { error in
            guard case ServerProfileValidationError.wrongScheme("http") = error else {
                return XCTFail("expected wrongScheme(http), got \(error)")
            }
        }
        XCTAssertThrowsError(
            try ServerProfile.validate(name: "s", urlString: "https://u:p@host", headers: [:])
        )
    }

    // MARK: network class

    func testNetworkClassRouting() {
        // Only the placeholder hostname may ever appear in a tracked file.
        XCTAssertEqual(NetworkClassRouting.classify(host: "your-host.your-tailnet.ts.net"), .tailnet)
        XCTAssertEqual(NetworkClassRouting.classify(host: "ts.net"), .tailnet)
        XCTAssertEqual(NetworkClassRouting.classify(host: "100.64.1.2"), .tailnet)
        XCTAssertEqual(NetworkClassRouting.classify(host: "100.127.255.254"), .tailnet)
        XCTAssertEqual(NetworkClassRouting.classify(host: "100.128.0.1"), .publicInternet)

        XCTAssertEqual(NetworkClassRouting.classify(host: "10.1.2.3"), .privateLan)
        XCTAssertEqual(NetworkClassRouting.classify(host: "172.16.0.1"), .privateLan)
        XCTAssertEqual(NetworkClassRouting.classify(host: "172.32.0.1"), .publicInternet)
        XCTAssertEqual(NetworkClassRouting.classify(host: "192.168.1.10"), .privateLan)
        XCTAssertEqual(NetworkClassRouting.classify(host: "lmstudio.local"), .privateLan)
        XCTAssertEqual(NetworkClassRouting.classify(host: "deskserver"), .privateLan)
        XCTAssertEqual(NetworkClassRouting.classify(host: "localhost"), .privateLan)
        XCTAssertEqual(NetworkClassRouting.classify(host: "127.0.0.1"), .privateLan)

        XCTAssertEqual(NetworkClassRouting.classify(host: "api.openai.example.com"), .publicInternet)
        XCTAssertEqual(NetworkClassRouting.classify(fromURLString: "https://your-host.your-tailnet.ts.net"), .tailnet)
        XCTAssertEqual(NetworkClassRouting.classify(fromURLString: "garbage"), .publicInternet)
    }

    // MARK: opt-in + plaintext

    func testPublicInternetNeedsOptIn() {
        var profile = ServerProfile(name: "cloud", kind: .openAICompatible,
                                    baseURLString: "https://api.some-provider.example")
        XCTAssertEqual(profile.networkClass, .publicInternet)
        XCTAssertFalse(profile.usableNow)
        profile.publicInternetOptIn = true
        XCTAssertTrue(profile.usableNow)
        profile.enabled = false
        XCTAssertFalse(profile.usableNow)
    }

    func testTailnetIsPrivateAndNotPlaintext() {
        let profile = ServerProfile(name: "home", kind: .openAICompatible,
                                    baseURLString: "https://your-host.your-tailnet.ts.net")
        XCTAssertEqual(profile.networkClass, .tailnet)
        XCTAssertFalse(profile.isPlaintext)
        XCTAssertTrue(profile.usableNow, "tailnet never needs an outbound opt-in")
    }

    func testLoopbackProfileIsPrivateLanAndPlaintext() {
        let profile = ServerProfile(name: "stub", kind: .openAICompatible,
                                    baseURLString: "http://127.0.0.1:8080")
        XCTAssertEqual(profile.networkClass, .privateLan)
        XCTAssertTrue(profile.isPlaintext)
    }
}