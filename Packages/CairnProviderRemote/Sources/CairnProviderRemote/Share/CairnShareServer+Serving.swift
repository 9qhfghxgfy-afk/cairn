import CairnChatDomain
import Foundation

extension CairnShareServer {
    /// One client, accepted. The served table and the key are read here, on the main actor, and handed
    /// to the servicer as values — so a two-minute generation never runs with the main actor as its
    /// executor, and a table that changed while the turn was running cannot change the turn mid-flight.
    func accept(_ socket: ShareSocket) {
        guard status.answersRequests else {
            socket.abandon()
            return
        }
        noteClient(opened: true)
        let snapshot = table
        let key = token
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            await ShareSocketServicer.serve(socket, table: snapshot, token: key) { busy in
                await MainActor.run { [weak self] in self?.noteTurn(active: busy) }
            }
            await MainActor.run { [weak self] in
                self?.noteTurn(active: false)
                self?.noteClient(opened: false)
            }
        }
        turnTasks.append(task)
    }
}

/// Answers one request on one socket, off the main actor.
///
/// Nothing here decides policy — the policy decided whether this socket could exist at all. This is
/// the mechanical part: read, dispatch, write, close. A request that never finishes arriving is
/// closed rather than answered, because half a request answered is a wrong answer.
///
/// `onTurn` is how the screen learns a port is busy: the servicer never touches status itself, it
/// reports the turn and the surface decides what that means.
enum ShareSocketServicer {
    static func serve(
        _ socket: ShareSocket,
        table: ShareEngineTable,
        token: String,
        onTurn: @escaping @Sendable (Bool) async -> Void = { _ in }
    ) async {
        guard await socket.begin() else {
            socket.abandon()
            return
        }
        switch await socket.readRequest() {
        case .needMoreBytes:
            socket.abandon()
        case .rejected:
            await socket.writeHead(ShareHTTPResponse.error(status: 400, dialect: .ollama, message: "unreadable request"))
            await socket.finishWriting()
        case .complete(let request):
            switch ShareDispatch.dispatch(request, table: table, token: token) {
            case .reply(let reply):
                await socket.writeHead(reply)
                for frame in reply.frames { await socket.writeFrame(frame) }
                await socket.finishWriting()
            case .turn(let turn, _):
                guard let provider = table.provider(forModelID: turn.modelID) else {
                    await socket.writeHead(ShareHTTPResponse.error(status: 503, dialect: turn.endpoint.errorDialect, message: "no engine behind that name"))
                    await socket.finishWriting()
                    return
                }
                await onTurn(true)
                await ShareTurnPump.run(turn: turn, provider: provider, to: socket)
                await onTurn(false)
            }
        }
    }
}
