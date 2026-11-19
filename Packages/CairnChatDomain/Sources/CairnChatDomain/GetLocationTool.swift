import Foundation

/// `get_location`: one position, and only after a person has said yes.
///
/// The order of this file is the privacy rule. Consent is settled **first** — through
/// `LocationConsentGate`, which never asks twice and treats "undecided with nobody to ask" as a refusal —
/// and only then is a position source reached. A declined call therefore performs no work at all: there
/// is no fix taken and thrown away, no manager initialised, no radio woken.
///
/// The result is the device's own numbers, rounded, with a line saying what they do not prove. Cairn does
/// not reverse-geocode and does not send a position anywhere; this tool's `networkClass` is `.onDevice`,
/// which is also why the outbound acknowledgement never gates it.
public struct GetLocationTool: ToolExecuting {
    /// How long one fix may take before the tool answers for itself. A phone with clear sky answers in a
    /// second or two; one indoors can take longer, and a turn must not sit on it indefinitely.
    public static let fixBudget: Duration = .seconds(12)

    private let source: any LocationFixProviding
    private let consent: LocationConsentGate
    /// The sheet. nil means nobody is there to ask, which `LocationConsentGate` answers as a refusal.
    private let asker: LocationConsentRequester?
    private let budget: Duration

    public init(
        source: any LocationFixProviding,
        consent: LocationConsentGate,
        asker: LocationConsentRequester? = nil,
        budget: Duration = GetLocationTool.fixBudget
    ) {
        self.source = source
        self.consent = consent
        self.asker = asker
        self.budget = budget
    }

    public var definition: ToolDefinition {
        ToolDefinition(
            name: BuiltInTool.getLocation,
            blurb: """
                Read this device's current position as latitude and longitude, with the accuracy in \
                metres the hardware reported. It runs only after the user has allowed location for \
                Cairn, so it can also answer that it was refused, that Location Services are off, or \
                that the device did not answer in time. Call it when an answer genuinely depends on \
                where the user is — not out of curiosity, and not more than once per question. Never \
                name a city, a country or a time zone that this tool did not return.
                """,
            // Nothing to ask for: the position is the device's, and the user is not an address the model
            // can pass in.
            parameters: .none,
            networkClass: .onDevice
        )
    }

    public func execute(
        _ call: ToolCall, context: ToolExecutionContext
    ) async throws -> ToolOutcome {
        let decision = await consent.authorize(asking: asker)
        if case .refused(let reason) = decision {
            throw ToolFailure(reason.toolError, detail: reason.userText)
        }
        let fix: LocationFix
        do {
            fix = try await Self.bounded(budget) { [source] in try await source.currentFix() }
        } catch let reason as LocationFailureReason {
            throw ToolFailure(reason.toolError, detail: reason.userText)
        }
        guard fix.isPlausible else {
            // A source that reports a coordinate outside the legal range is broken, and a broken reading
            // sent to a model becomes a confident answer about a place that does not exist.
            throw ToolFailure(
                LocationFailureReason.unavailable.toolError,
                detail: LocationFailureReason.unavailable.userText
            )
        }
        return .success(callID: call.id, toolName: call.name, output: fix.modelText)
    }

    /// `work`, bounded by `budget`, so a device that never answers cannot hold a turn open.
    ///
    /// Both children return a `Result` instead of throwing: a group whose losing child throws on
    /// cancellation rethrows that cancellation at the end of the scope, which would turn a fix that
    /// arrived in time into a reported failure.
    static func bounded<T: Sendable>(
        _ budget: Duration,
        _ work: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: Result<T, any Error>.self) { group in
            group.addTask {
                do { return .success(try await work()) }
                catch { return .failure(error) }
            }
            group.addTask {
                try? await Task.sleep(for: budget)
                if Task.isCancelled { return .failure(CancellationError()) }
                return .failure(LocationFailureReason.timedOut)
            }
            guard let first = try await group.next() else {
                throw LocationFailureReason.unavailable
            }
            group.cancelAll()
            return try first.get()
        }
    }
}
