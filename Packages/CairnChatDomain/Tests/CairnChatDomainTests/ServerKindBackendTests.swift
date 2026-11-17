import XCTest
@testable import CairnChatDomain

/// The kind → endpoint/capability table is pure data, and it is the only place a path is written
/// down. These tests are what stop a table edit from silently reintroducing a path this app never
/// speaks, or a relative path that would resolve against the wrong host.
final class ServerKindBackendTests: XCTestCase {

    func testEveryKindDeclaresOnlyAbsolutePaths() {
        for kind in ServerProfileKind.allCases {
            for path in kind.backend.endpoints.declaredPaths {
                XCTAssertTrue(
                    path.hasPrefix("/"),
                    "\(kind.displayName) declares a relative path: \(path)"
                )
            }
        }
    }

    func testNoKindSpeaksTheV0Namespace() {
        for kind in ServerProfileKind.allCases {
            for path in kind.backend.endpoints.declaredPaths {
                XCTAssertFalse(
                    path.contains("/v0"),
                    "\(kind.displayName) declares a v0 path: \(path)"
                )
            }
        }
    }

    func testLMStudioChatsThroughOpenAICompatibilityAndListsItsOwnModels() {
        let backend = ServerBackend.backend(for: .lmStudio)
        XCTAssertEqual(backend.endpoints.chat, "/v1/chat/completions")
        XCTAssertTrue(backend.capabilities.modelListing)
        // Its model list is not the OpenAI one, so it has to be declared separately.
        XCTAssertNotEqual(backend.endpoints.models, "/v1/models")
    }

    func testOllamaIsTheOnlyKindThatClaimsPullAndLoadedModelInspection() {
        let ollama = ServerBackend.backend(for: .ollama)
        XCTAssertTrue(ollama.capabilities.modelPull)
        XCTAssertTrue(ollama.capabilities.loadedModelInspection)
        for kind in ServerProfileKind.allCases where kind != .ollama {
            XCTAssertFalse(
                kind.backend.capabilities.modelPull,
                "\(kind.displayName) must not claim model pulling"
            )
        }
    }

    func testCloudKindArrivesNamedOffAndExpectingAKey() {
        let cloud = ServerProfile.draft(for: .ollamaCloud)
        XCTAssertEqual(cloud.kind, .ollamaCloud)
        XCTAssertFalse(cloud.enabled, "a hosted server starts switched off")
        XCTAssertTrue(cloud.baseURLString.contains(ServerBackend.cloudHost))
        // Off by default is not enough: it must not be usable until the outbound opt-in is given.
        XCTAssertFalse(cloud.usableNow)
    }

    func testLANKindsArriveWithoutAGuessedAddress() {
        for kind in [ServerProfileKind.ollama, .lmStudio, .openAICompatible] {
            let draft = ServerProfile.draft(for: kind)
            XCTAssertTrue(draft.enabled, "a server on your own network is usable as soon as it is named")
            XCTAssertFalse(draft.publicInternetOptIn, "a LAN server never leaves the network it is on")
            let host = draft.baseURLString.replacingOccurrences(of: "http://", with: "")
            XCTAssertTrue(
                host.isEmpty,
                "\(kind.displayName) guessed an address: \(draft.baseURLString)"
            )
        }
    }

    func testRemoteEngineIDRoundTripsAndRejectsAnythingElse() {
        let id = UUID()
        let engineID = RemoteEngineID.make(profileID: id)
        XCTAssertEqual(RemoteEngineID.parse(engineID), id)
        XCTAssertNil(RemoteEngineID.parse("mock"))
        XCTAssertNil(RemoteEngineID.parse(RemoteEngineID.prefix + "not-a-uuid"))
    }
}
