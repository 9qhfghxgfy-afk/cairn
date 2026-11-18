import Foundation

/// How many model↔tool round trips one turn may take.
///
/// A step is one model call. A model that keeps calling tools keeps spending steps, and without a
/// bound a confused model can loop until the user stops it by hand. Six is the default the parity
/// brief records; it is a bound on how long one turn runs, and the user sets it.
public struct ToolLoopPolicy: Sendable, Equatable {
    /// Default round trips per turn, per the P3 brief.
    public static let defaultStepLimit = 6

    public var stepLimit: Int

    public init(stepLimit: Int = ToolLoopPolicy.defaultStepLimit) {
        self.stepLimit = ToolLoopPolicy.sanitize(stepLimit)
    }

    public static let `default` = ToolLoopPolicy()

    /// A zero or negative bound would mean "run a model call zero times", and an enormous one is
    /// the runaway this type exists to prevent, so both ends are brought into range here rather
    /// than at each call site.
    static func sanitize(_ requested: Int) -> Int {
        if requested < 1 { return 1 }
        if requested > 32 { return 32 }
        return requested
    }

    /// `stepsTaken` is how many model calls have already finished this turn.
    public func mayRunAnotherStep(stepsTaken: Int) -> Bool {
        stepsTaken < ToolLoopPolicy.sanitize(stepLimit)
    }

    /// Whether a call is worth a further step at all: a failure the model cannot fix by re-calling
    /// only burns the remaining budget.
    public func shouldContinue(after outcome: ToolOutcome, stepsTaken: Int) -> Bool {
        guard mayRunAnotherStep(stepsTaken: stepsTaken) else { return false }
        if outcome.succeeded { return true }
        return outcome.error?.modelCanRetry ?? true
    }
}
