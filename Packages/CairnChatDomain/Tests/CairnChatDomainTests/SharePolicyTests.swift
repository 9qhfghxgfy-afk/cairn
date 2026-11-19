import XCTest
@testable import CairnChatDomain

/// P4's privacy rules, before a single socket exists: what may be bound, and what has to be true
/// before a phone is allowed to open a port on its own network.
final class SharePolicyTests: XCTestCase {

    private let key = "0123456789abcdef0123456789abcdef"

    func testAKeyIsNeededAndAShortWordIsNotAKey() {
        XCTAssertFalse(SharePolicy.tokenIsUsable(""))
        XCTAssertFalse(SharePolicy.tokenIsUsable("hunter2"), "a word is not a key")
        XCTAssertFalse(SharePolicy.tokenIsUsable("short key with spaces"), "a phrase is not a key")
        XCTAssertTrue(SharePolicy.tokenIsUsable(key))
        XCTAssertTrue(SharePolicy.tokenIsUsable("  \(key)  "), "pasted in with whitespace is still the key")
    }

    func testOnlyPortsAnAppMayBindAreAccepted() {
        XCTAssertFalse(SharePolicy.portIsUsable(80), "a well-known port belongs to the system")
        XCTAssertFalse(SharePolicy.portIsUsable(1023))
        XCTAssertTrue(SharePolicy.portIsUsable(1024))
        XCTAssertTrue(SharePolicy.portIsUsable(ShareSettings.defaultPort))
        XCTAssertTrue(SharePolicy.portIsUsable(65_535))
        XCTAssertFalse(SharePolicy.portIsUsable(65_536))
        XCTAssertFalse(SharePolicy.portIsUsable(0))
    }

    /// LAN-only bind, stated as a rule rather than as a comment. Loopback and RFC 1918 are the
    /// phone's own link; a public address and the CGNAT block a VPN allocates are not.
    func testOnlyAPrivateLocalAddressMayBeBound() {
        XCTAssertTrue(SharePolicy.addressIsBindable("192.168.1.20"))
        XCTAssertTrue(SharePolicy.addressIsBindable("10.8.0.2"))
        XCTAssertTrue(SharePolicy.addressIsBindable("127.0.0.1"))
        XCTAssertTrue(SharePolicy.addressIsBindable("cairn-phone.local"))
        XCTAssertTrue(SharePolicy.addressIsBindable("cairn-phone"))
        XCTAssertFalse(SharePolicy.addressIsBindable("203.0.113.7"), "a public address is never this surface")
        XCTAssertFalse(SharePolicy.addressIsBindable("100.64.1.2"), "a VPN address is not the local link")
        XCTAssertFalse(SharePolicy.addressIsBindable("models.example.com"))
        XCTAssertFalse(SharePolicy.addressIsBindable(""), "nothing to bind is nothing to bind")
    }

    func testTheGeneratedKeyIsLongEnoughAndNotARepeat() {
        let first = ShareToken.generate()
        XCTAssertEqual(first.count, 32, "128 bits as hex")
        XCTAssertTrue(SharePolicy.tokenIsUsable(first))
        XCTAssertNotEqual(first, ShareToken.generate())
    }

    /// The refusal order is the order a user can act in: a key before a model, a model before a
    /// port, a port before the network the phone is standing on.
    func testTheDecisionRefusesInTheOrderAUserCanActOn() {
        XCTAssertEqual(
            SharePolicy.decide(running: false, token: nil, address: "192.168.1.20", port: 11434, sharedEngineCount: 1),
            .refused(.needsToken)
        )
        XCTAssertEqual(
            SharePolicy.decide(running: false, token: "abc", address: "192.168.1.20", port: 11434, sharedEngineCount: 1),
            .refused(.tokenTooWeak)
        )
        XCTAssertEqual(
            SharePolicy.decide(running: false, token: key, address: "192.168.1.20", port: 11434, sharedEngineCount: 0),
            .refused(.needsModel)
        )
        XCTAssertEqual(
            SharePolicy.decide(running: false, token: key, address: "192.168.1.20", port: 22, sharedEngineCount: 1),
            .refused(.portUnusable)
        )
        XCTAssertEqual(
            SharePolicy.decide(running: false, token: key, address: nil, port: 11434, sharedEngineCount: 1),
            .refused(.noAddress)
        )
        XCTAssertEqual(
            SharePolicy.decide(running: false, token: key, address: "203.0.113.7", port: 11434, sharedEngineCount: 1),
            .refused(.notLocalAddress)
        )
        XCTAssertEqual(
            SharePolicy.decide(running: true, token: key, address: "192.168.1.20", port: 11434, sharedEngineCount: 1),
            .refused(.alreadyRunning)
        )
        XCTAssertTrue(
            SharePolicy.decide(running: false, token: key, address: "192.168.1.20", port: 11434, sharedEngineCount: 2).isAllowed
        )
    }

    /// A refusal is a code, never a value: no address and no key can ride out of this type into a
    /// log, an alert, or a CI line.
    func testARefusalCarriesNoAddressAndNoKey() {
        for refusal in ShareRefusal.allCases {
            let text = ShareStatusText.failureText(refusal)
            XCTAssertTrue(text.count > 10)
            XCTAssertFalse(text.contains(key))
            XCTAssertFalse(text.contains("192.168"))
        }
        XCTAssertFalse(ShareStatusText.failureText(nil).isEmpty)
    }
}
