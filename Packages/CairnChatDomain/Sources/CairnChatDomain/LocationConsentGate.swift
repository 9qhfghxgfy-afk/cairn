import Foundation

/// The outcome of asking for permission to read a position.
public enum LocationConsentDecision: Sendable, Equatable {
    /// The person in front of the phone has said yes — now, or on an earlier turn.
    case allowed
    /// Nothing may be read. The reason says which kind of no this is.
    case refused(LocationFailureReason)
}

/// The record of whether this app may read a position, and the only door to asking.
///
/// An actor rather than a `Bool`, because the question and the answer arrive on different tasks: the tool
/// asks from inside a turn, and a button on a sheet answers from the main actor. The record has to be
/// written in one place for the two to agree, and a second call must not slip past a question that is
/// still open on the screen.
///
/// The one rule that matters is the order: the record is consulted and, if needed, the person is asked
/// **before** anything that could touch a radio. A refusal here never reaches a position source, so a
/// declined tool performs zero hardware calls rather than reading a fix and then deciding to hide it.
public actor LocationConsentGate {
    public private(set) var state: LocationConsentState

    /// The question that is up on the screen right now, if one is.
    ///
    /// Held as a shared task rather than as a flag, because everyone who arrives while the sheet is up has
    /// to be answered from the **same** answer. A second sheet stacked on the first, or a silent refusal for
    /// whoever arrived second, are wrong in opposite directions.
    private var question: Task<Bool, Never>?

    public init(state: LocationConsentState = .undecided) { self.state = state }

    /// Files an answer from a sheet, a Settings switch, or a test.
    public func resolve(allow: Bool) { state = LocationConsentPolicy.state(after: allow) }

    /// Takes the record back to "nobody has been asked", which is the state a fresh install is in.
    public func reset() {
        question = nil
        state = .undecided
    }

    /// The only path a tool may take.
    ///
    /// `asker` is the sheet. nil means there is nothing to put in front of a person — a preview, a headless
    /// build — and `undecided` with nobody to ask is answered as a refusal, never as permission. A granted
    /// record never calls `asker`, so an allowed tool does not interrupt anyone a second time.
    public func authorize(asking asker: LocationConsentRequester?) async -> LocationConsentDecision {
        switch LocationConsentPolicy.action(state: state, canAsk: asker != nil) {
        case .proceed:
            return .allowed
        case let .refuse(reason):
            return .refused(reason)
        case .askOnce:
            guard let asker else { return .refused(.permissionDenied) }
            if let question {
                // The sheet is already up in front of somebody. Wait for their answer; do not stack a
                // second one on top of it, and do not answer for them.
                return Self.decision(for: await question.value)
            }
            let request = asker
            let asked = Task { () -> Bool in
                let answer = await request()
                resolve(allow: answer)
                return answer
            }
            question = asked
            let answer = await asked.value
            question = nil
            return Self.decision(for: answer)
        }
    }

    /// A shared task carries a plain yes or no, so the yes or no becomes the decision here rather than in
    /// two places that could drift.
    private static func decision(for answer: Bool) -> LocationConsentDecision {
        answer ? .allowed : .refused(.permissionDenied)
    }
}
