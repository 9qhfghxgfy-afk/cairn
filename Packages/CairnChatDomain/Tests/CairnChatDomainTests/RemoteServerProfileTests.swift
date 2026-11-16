import XCTest
@testable import CairnChatDomain

final class RemoteServerProfileTests: XCTestCase {

    // MARK: canonicalize

    func testCanonicalizeAcceptsHTTPSWithoutPath() {
        XCTAssertEqual(
            ServerProfile.canonicalize(urlString: "https://your-host.your-vpn.ts.net"),
            "https://your-host.your-vpn.ts.net"
        )
        XCTAssertEqual(
            ServerProfile.canonicalize(urlString: "https://your-host.your-vpn.ts.net/"),
            "https://your-host.your-vpn.ts.net"
        )
        XCTAssertEqual(
            ServerProfile.canonicalize(urlString: "HTTPS://Example.COM:8443"),
            "https://example.com:8443"
        )
    }

    /// A private address over http is the primary supported route, and a public-internet
    /// host over http is refused. Generic RFC 1918 addresses only — never a real host.
    func testCanonicalizeAcceptsPrivatePlaintextAndRefusesPublicPlaintext() {
        XCTAssertEqual(ServerProfile.canonicalize(urlString: "http://192.168.1.5:1234"),
                       "http://192.168.1.5:1234")
        XCTAssertEqual(ServerProfile.canonicalize(urlString: "http://10.0.0.5:11434"),
                       "http://10.0.0.5:11434")
        XCTAssertEqual(ServerProfile.canonicalize(urlString: "http://100.64.1.2:11434"),
                       "http://100.64.1.2:11434")
        XCTAssertEqual(ServerProfile.canonicalize(urlString: "http://ollama.local:11434"),
                       "http://ollama.local:11434")
        XCTAssertEqual(ServerProfile.canonicalize(urlString: "http://deskserver:8080/"),
                       "http://deskserver:8080")
        XCTAssertEqual(ServerProfile.canonicalize(urlString: "http://localhost:11434"),
                       "http://localhost:11434")

        XCTAssertNil(ServerProfile.canonicalize(urlString: "http://api.some-provider.example"))
        XCTAssertNil(ServerProfile.canonicalize(urlString: "http://203.0.113.9:11434"))
        XCTAssertNil(ServerProfile.canonicalize(urlString: "ftp://host"))
        XCTAssertNil(ServerProfile.canonicalize(urlString: "192.168.1.5:1234"))
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

    func testValidateRejectsBlankNameForeignSchemeAndUserInfo() {
        XCTAssertThrowsError(
            try ServerProfile.validate(name: "  ", urlString: "https://host", headers: [:])
        )
        XCTAssertThrowsError(
            try ServerProfile.validate(name: "s", urlString: "http://api.some-provider.example", headers: [:])
        ) { error in
            guard case ServerProfileValidationError.plaintextPublicInternet = error else {
                return XCTFail("expected plaintextPublicInternet, got \(error)")
            }
        }
        XCTAssertThrowsError(
            try ServerProfile.validate(name: "s", urlString: "ftp://10.0.0.9", headers: [:])
        ) { error in
            guard case ServerProfileValidationError.wrongScheme("ftp") = error else {
                return XCTFail("expected wrongScheme(ftp), got \(error)")
            }
        }
        XCTAssertThrowsError(
            try ServerProfile.validate(name: "s", urlString: "https://u:p@host", headers: [:])
        )
    }

    /// The user's actual setup: a llama.cpp / Ollama box on the LAN, reached over http.
    func testValidateAcceptsAPlaintextServerOnTheLAN() throws {
        try ServerProfile.validate(name: "Home box", urlString: "http://192.168.1.20:8181", headers: [:])
        try ServerProfile.validate(name: "VPN box", urlString: "http://10.8.0.2:11434", headers: [:])
    }

    // MARK: network class

    func testNetworkClassRouting() {
        // Only the placeholder hostname may ever appear in a tracked file.
        XCTAssertEqual(NetworkClassRouting.classify(host: "your-host.your-vpn.ts.net"), .privateVPN)
        XCTAssertEqual(NetworkClassRouting.classify(host: "ts.net"), .privateVPN)
        XCTAssertEqual(NetworkClassRouting.classify(host: "100.64.1.2"), .privateVPN)
        XCTAssertEqual(NetworkClassRouting.classify(host: "100.127.255.254"), .privateVPN)
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
        XCTAssertEqual(NetworkClassRouting.classify(fromURLString: "https://your-host.your-vpn.ts.net"), .privateVPN)
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

    func testPrivateVpnIsPrivateAndNotPlaintext() {
        let profile = ServerProfile(name: "home", kind: .openAICompatible,
                                    baseURLString: "https://your-host.your-vpn.ts.net")
        XCTAssertEqual(profile.networkClass, .privateVPN)
        XCTAssertFalse(profile.isPlaintext)
        XCTAssertTrue(profile.usableNow, "a private VPN address never needs an outbound opt-in")
    }

    func testLoopbackProfileIsPrivateLanAndPlaintext() {
        let profile = ServerProfile(name: "stub", kind: .openAICompatible,
                                    baseURLString: "http://127.0.0.1:8080")
        XCTAssertEqual(profile.networkClass, .privateLan)
        XCTAssertTrue(profile.isPlaintext)
    }

    /// A LAN server over http is usable with no opt-in: the traffic never leaves the
    /// user's own network, so plaintext there is a warning to display, not a rule to enforce.
    func testLanPlaintextIsPrivateAndNeedsNoOptIn() {
        let profile = ServerProfile(name: "Wired box", kind: .openAICompatible,
                                    baseURLString: "http://192.168.1.20:8181")
        XCTAssertEqual(profile.networkClass, .privateLan)
        XCTAssertTrue(profile.isPlaintext)
        XCTAssertTrue(profile.networkClass.allowsPlaintext)
        XCTAssertTrue(profile.usableNow, "a private server is never gated by the outbound opt-in")
    }

    func testPublicInternetNeverAllowsPlaintextButPrivateClassesDo() {
        XCTAssertFalse(NetworkClass.publicInternet.allowsPlaintext)
        XCTAssertTrue(NetworkClass.privateLan.allowsPlaintext)
        XCTAssertTrue(NetworkClass.privateVPN.allowsPlaintext)
        XCTAssertTrue(NetworkClass.onDevice.allowsPlaintext)
    }
}