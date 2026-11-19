import XCTest
@testable import CairnChatDomain

/// The route table, in both dialects, including what an unknown path is answered with.
final class ShareRoutingTests: XCTestCase {

    func testEachSurfaceRoutesInItsOwnDialect() {
        XCTAssertEqual(ShareRouting.endpoint(method: "GET", path: "/api/version"), .version)
        XCTAssertEqual(ShareRouting.endpoint(method: "GET", path: "/api/tags"), .modelList(dialect: .ollama))
        XCTAssertEqual(ShareRouting.endpoint(method: "GET", path: "/v1/models"), .modelList(dialect: .openAI))
        XCTAssertEqual(ShareRouting.endpoint(method: "POST", path: "/api/chat"), .chat(dialect: .ollama))
        XCTAssertEqual(ShareRouting.endpoint(method: "POST", path: "/api/generate"), .generate)
        XCTAssertEqual(ShareRouting.endpoint(method: "POST", path: "/v1/chat/completions"), .chat(dialect: .openAI))
        XCTAssertEqual(ShareRouting.endpoint(method: "POST", path: "/v1/completions"), .completion)
    }

    /// Verbs are case-insensitive in HTTP, and a client that writes `get` is a client that expects
    /// to be understood.
    func testTheVerbIsReadWithoutCareAboutCase() {
        XCTAssertEqual(ShareRouting.endpoint(method: "get", path: "/api/tags"), .modelList(dialect: .ollama))
        XCTAssertEqual(ShareRouting.endpoint(method: "Post", path: "/api/chat"), .chat(dialect: .ollama))
    }

    func testAWrongVerbOnARoutedPathIsStillNotFound() {
        // Routing is (method, path) together: POST /api/tags is not a chat turn and not a list.
        XCTAssertEqual(ShareRouting.endpoint(method: "POST", path: "/api/tags"), .unknown(path: "/api/tags"))
        XCTAssertEqual(ShareRouting.endpoint(method: "GET", path: "/api/chat"), .unknown(path: "/api/chat"))
    }

    func testEveryPathHasADialectForItsErrors() {
        XCTAssertEqual(ShareRouting.endpoint(method: "GET", path: "/api/version").errorDialect, .ollama)
        XCTAssertEqual(ShareRouting.endpoint(method: "POST", path: "/v1/completions").errorDialect, .openAI)
        XCTAssertEqual(ShareRouting.endpoint(method: "GET", path: "/api/nope").errorDialect, .ollama, "an /api path answers in Ollama's shape")
        XCTAssertEqual(ShareRouting.endpoint(method: "GET", path: "/v1/nope").errorDialect, .ollama, "unknown paths answer in the default shape")
    }

    /// A browser preflight carries no turn and no key, so it must be recognised before the key
    /// check rather than refused by it.
    func testAPreflightIsRecognisedRatherThanRefused() {
        let route = ShareRouting.endpoint(method: "OPTIONS", path: "/v1/chat/completions")
        XCTAssertEqual(route, .preflight)
        XCTAssertNil(route.dialect)
    }

    func testTheDialectDescribesItselfConsistently() {
        XCTAssertEqual(ShareDialect.ollama.listPath, "/api/tags")
        XCTAssertEqual(ShareDialect.ollama.chatPath, "/api/chat")
        XCTAssertEqual(ShareDialect.ollama.streamContentType, "application/x-ndjson")
        XCTAssertEqual(ShareDialect.openAI.listPath, "/v1/models")
        XCTAssertEqual(ShareDialect.openAI.chatPath, "/v1/chat/completions")
        XCTAssertEqual(ShareDialect.openAI.streamContentType, "text/event-stream")
        XCTAssertEqual(ShareDialect.openAI.contentType, "application/json")

        // Every path the surface advertises really routes somewhere, with the verb it is asked with.
        let asked: [(String, String)] = [
            ("GET", "/api/version"), ("GET", "/api/tags"), ("POST", "/api/chat"), ("POST", "/api/generate"),
            ("GET", "/v1/models"), ("POST", "/v1/chat/completions"), ("POST", "/v1/completions"),
        ]
        for (verb, path) in asked {
            XCTAssertFalse(
                ShareRouting.endpoint(method: verb, path: path).isUnknown,
                "\(verb) \(path) is advertised, so it must route"
            )
        }
        XCTAssertEqual(Set(asked.map { $0.1 }), Set(ShareRouting.answeredPaths), "the advertised list is the routed list")
    }
}

private extension ShareEndpoint {
    var isUnknown: Bool {
        if case .unknown = self { return true }
        return false
    }
}
