import Foundation

/// What the surface owes a request: either a reply it can write right now, or a turn it has to run.
///
/// The split exists because the two have different lifetimes. A reply is one buffer; a turn is a
/// stream that outlives the call that parsed it and needs a connection still open when each token
/// arrives. Keeping them apart means the socket layer never has to guess what a request meant.
public enum ShareDispatchOutcome: Sendable, Equatable {
    case reply(ShareReply)
    case turn(ShareTurnRequest, shape: ShareStreamShape)
}

/// Route + key + model table → outcome, in one pure place.
///
/// **Every route is keyed, including the model list.** `/api/tags` and `/v1/models` look harmless,
/// but they name the models on a person's phone and tell a stranger the phone is there, so an
/// unauthenticated listing is a discovery beacon for a device that is not meant to be reachable at
/// all. There is no route below that is answered without the key.
///
/// An error never carries the request body, the key, or the caller's address — only a short reason
/// in the shape the client is reading.
public enum ShareDispatch {
    public static func dispatch(
        _ request: ShareHTTPRequest,
        table: ShareEngineTable,
        token: String,
        now: Date = Date()
    ) -> ShareDispatchOutcome {
        let route = request.endpoint
        if route == .preflight {
            return .reply(ShareHTTPResponse.preflight(origin: request.header("origin")))
        }
        let dialect = errorDialect(for: route)
        switch ShareAuthChallenge.check(request, expected: token) {
        case .missing:
            return .reply(ShareHTTPResponse.error(status: 401, dialect: dialect, message: "no key supplied"))
        case .mismatch:
            return .reply(ShareHTTPResponse.error(status: 401, dialect: dialect, message: "key not accepted"))
        case .accepted:
            break
        }

        switch route {
        case .version:
            return .reply(ShareHTTPResponse.json(status: 200, body: ShareOllamaEncoder.versionBody()))
        case .modelList(let listDialect):
            return .reply(ShareHTTPResponse.json(status: 200, body: listBody(for: listDialect, table: table, now: now)))
        case .chat(let turnDialect):
            return turnOutcome(for: request, table: table, dialect: turnDialect)
        case .generate, .completion:
            return turnOutcome(for: request, table: table, dialect: dialect)
        case .preflight:
            // Unreachable: a preflight is answered above, before the key check.
            return .reply(ShareHTTPResponse.error(status: 405, dialect: dialect, message: "method not allowed"))
        case .unknown(let path):
            return .reply(ShareHTTPResponse.error(status: 404, dialect: ShareDispatch.dialect(forPath: path), message: "no such path"))
        }
    }

    /// The dialect an error on this route is written in. An unknown path decides by its own prefix,
    /// because a client pointed at `/v1/…` is an OpenAI-compatible client whatever this app serves
    /// elsewhere.
    static func errorDialect(for route: ShareEndpoint) -> ShareDialect {
        if case .unknown(let path) = route { return dialect(forPath: path) }
        return route.errorDialect
    }

    static func dialect(forPath path: String) -> ShareDialect {
        path.hasPrefix("/v1") ? .openAI : .ollama
    }

    static func listBody(for dialect: ShareDialect, table: ShareEngineTable, now: Date) -> String {
        switch dialect {
        case .ollama: return ShareOllamaEncoder.modelListBody(table.entries)
        case .openAI: return ShareOpenAIEncoder.modelListBody(table.entries, created: ShareTimestamp.openAI(now))
        }
    }

    /// A turn body is read, then checked against the table the surface was started with. A name the
    /// user never ticked is answered 404 rather than run: silently serving a different engine than
    /// the one the client asked for would be answering a question nobody asked.
    static func turnOutcome(
        for request: ShareHTTPRequest,
        table: ShareEngineTable,
        dialect: ShareDialect
    ) -> ShareDispatchOutcome {
        let route = request.endpoint
        guard let shape = ShareStreamShape.forEndpoint(route) else {
            return .reply(ShareHTTPResponse.error(status: 405, dialect: dialect, message: "no turn on this path"))
        }
        switch ShareTurnDecoder.decode(body: request.body, endpoint: route) {
        case .failure(let failure):
            return .reply(ShareHTTPResponse.error(status: 400, dialect: dialect, message: failure.wireText))
        case .success(let turn):
            guard table.provider(forModelID: turn.modelID) != nil else {
                return .reply(ShareHTTPResponse.error(status: 404, dialect: dialect, message: "no such model"))
            }
            return .turn(turn, shape: shape)
        }
    }
}

private extension ShareRequestFailure {
    /// A reason in the client's words, with nothing from the body in it.
    var wireText: String {
        switch self {
        case .undecodable: return "unreadable request body"
        case .missingModel: return "no model named"
        case .emptyMessages: return "no messages to answer"
        case .unknownModel: return "no such model"
        }
    }
}
