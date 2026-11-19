import XCTest
@testable import CairnChatDomain

/// The whole route table in one place: what a keyed request gets, and what an unkeyed one gets.
final class ShareDispatchTests: XCTestCase {
    private let token = "0123456789abcdef0123456789abcdef"

    private struct StubEngine: InferenceProvider {
        let id: String
        let displayName: String
        var networkClass: NetworkClass { .onDevice }
        var capabilities: ProviderCapabilities { ProviderCapabilities() }
        var serverProfileID: UUID? { nil }
        func models() async throws -> [ModelInfo] { [] }
        func stream(_ request: GenerationRequest) -> AsyncThrowingStream<StreamChunk, any Error> {
            AsyncThrowingStream { $0.finish() }
        }
    }

    /// One served engine, named `m`, which every chat body below asks for.
    private var table: ShareEngineTable {
        ShareEngineTable.build(from: [StubEngine(id: "m", displayName: "Model")], selected: ["m"])
    }

    private func request(_ raw: String) -> ShareHTTPRequest {
        guard case .complete(let parsed) = ShareHTTPParser.parse(Data(raw.utf8)) else {
            XCTFail("test request is malformed: \(raw.prefix(40))")
            return ShareHTTPRequest(method: "GET", path: "/", headers: [:], body: Data())
        }
        return parsed
    }

    private func keyed(_ line: String, body: String = "") -> ShareHTTPRequest {
        request("\(line) HTTP/1.1\r\nAuthorization: Bearer \(token)\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)")
    }

    private func reply(_ outcome: ShareDispatchOutcome) -> ShareReply? {
        guard case .reply(let value) = outcome else { return nil }
        return value
    }

    private func bodyText(_ outcome: ShareDispatchOutcome) -> String {
        guard let reply = reply(outcome) else {
            XCTFail("expected a whole reply, not a turn")
            return ""
        }
        return String(decoding: reply.bodyData, as: UTF8.self)
    }

    private func status(_ outcome: ShareDispatchOutcome) -> Int? {
        reply(outcome)?.status
    }

    func testThePingRouteAnswersWithTheProxyVersion() {
        let outcome = ShareDispatch.dispatch(keyed("GET /api/version"), table: table, token: token)
        XCTAssertEqual(status(outcome), 200)
        XCTAssertTrue(bodyText(outcome).contains(ShareSettings.servedVersion))
    }

    /// The model list names the engines on a person's phone, so it is keyed like everything else. An
    /// unkeyed list would make the app a discovery beacon for a device never meant to be reachable.
    func testTheModelListIsKeyedLikeEverythingElse() {
        let outcome = ShareDispatch.dispatch(request("GET /api/tags HTTP/1.1\r\n\r\n"), table: table, token: token)
        XCTAssertEqual(status(outcome), 401)
        XCTAssertTrue(bodyText(outcome).contains("no key supplied"))
    }

    func testAWrongKeyIsRefusedInTheOpenAIShapeOnTheOpenAIPath() {
        let outcome = ShareDispatch.dispatch(
            request("GET /v1/models HTTP/1.1\r\nAuthorization: Bearer wrongwrongwrongwrong\r\n\r\n"),
            table: table, token: token
        )
        XCTAssertEqual(status(outcome), 401)
        XCTAssertTrue(bodyText(outcome).contains("\"error\""))
        XCTAssertFalse(bodyText(outcome).contains("wrongwrongwrongwrong"), "the refused key is never echoed")
    }

    func testTheKeyedListNamesTheServedEnginesInBothDialects() {
        let ollama = ShareDispatch.dispatch(keyed("GET /api/tags"), table: table, token: token)
        XCTAssertEqual(status(ollama), 200)
        XCTAssertTrue(bodyText(ollama).contains("\"name\":\"m\""))

        let openAI = ShareDispatch.dispatch(keyed("GET /v1/models"), table: table, token: token)
        XCTAssertEqual(status(openAI), 200)
        XCTAssertTrue(bodyText(openAI).contains("\"object\":\"list\""))
    }

    func testAPreflightIsAnsweredWithoutAKeyAndNeverRunsATurn() {
        let outcome = ShareDispatch.dispatch(
            request("OPTIONS /v1/chat/completions HTTP/1.1\r\nOrigin: http://192.168.1.20\r\n\r\n"),
            table: table, token: token
        )
        guard let preflight = reply(outcome) else { return XCTFail("a preflight is a reply, never a turn") }
        XCTAssertEqual(preflight.status, 204)
        XCTAssertEqual(preflight.extraHeaders["Access-Control-Allow-Origin"], "http://192.168.1.20")
    }

    func testAnUnknownPathIsRefusedInTheShapeTheClientIsReading() {
        XCTAssertEqual(status(ShareDispatch.dispatch(keyed("GET /nope"), table: table, token: token)), 404)
        let openAI = ShareDispatch.dispatch(keyed("GET /v1/nope"), table: table, token: token)
        XCTAssertTrue(bodyText(openAI).contains("\"error\""), "a /v1 client gets an OpenAI-shaped error")
    }

    func testAChatBodyForAServedEngineBecomesATurnNotAReply() {
        let body = "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}"
        let outcome = ShareDispatch.dispatch(keyed("POST /api/chat", body: body), table: table, token: token)
        guard case .turn(let turn, let shape) = outcome else { return XCTFail("a valid turn must be handed to the pump") }
        XCTAssertEqual(shape, .ollamaChat)
        XCTAssertEqual(turn.modelID, "m")
        XCTAssertEqual(turn.messages.count, 1)
        XCTAssertTrue(turn.streams, "Ollama streams unless the body says otherwise")
    }

    /// A name the user never ticked is refused rather than quietly served by a different engine, and
    /// a body that cannot be read is refused with none of its text in the answer.
    func testAnUnservedEngineIsFourOhFourAndAnUnreadableBodyIsFourHundred() {
        let missing = "{\"model\":\"other\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}"
        let missingOutcome = ShareDispatch.dispatch(keyed("POST /api/chat", body: missing), table: table, token: token)
        XCTAssertEqual(status(missingOutcome), 404)

        let broken = "{\"model\":\"m\""
        let brokenOutcome = ShareDispatch.dispatch(keyed("POST /api/chat", body: broken), table: table, token: token)
        XCTAssertEqual(status(brokenOutcome), 400)
        XCTAssertFalse(bodyText(brokenOutcome).contains("model"), "the unreadable body is not echoed back")
    }

    func testEachTurnRouteCarriesItsOwnResponseShape() {
        let generateOutcome = ShareDispatch.dispatch(
            keyed("POST /api/generate", body: "{\"model\":\"m\",\"prompt\":\"hi\"}"), table: table, token: token
        )
        guard case .turn(_, let shape) = generateOutcome else { return XCTFail("generate is a turn") }
        XCTAssertEqual(shape, .ollamaGenerate)

        let completionOutcome = ShareDispatch.dispatch(
            keyed("POST /v1/completions", body: "{\"model\":\"m\",\"prompt\":\"hi\"}"), table: table, token: token
        )
        guard case .turn(_, let completionShape) = completionOutcome else { return XCTFail("completions is a turn") }
        XCTAssertEqual(completionShape, .openAICompletion)
    }

    func testANonStreamingBodyIsStillATurnWithStreamingOff() {
        let body = "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"stream\":false}"
        let outcome = ShareDispatch.dispatch(keyed("POST /api/chat", body: body), table: table, token: token)
        guard case .turn(let turn, _) = outcome else { return XCTFail("a whole-answer turn is still a turn") }
        XCTAssertFalse(turn.streams)
    }
}
