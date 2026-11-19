import Foundation
@testable import CairnChatDomain

/// A position source that counts how often it is reached.
///
/// The count is the point. Every refusal test asserts `calls == 0`, which is what proves the tool declines
/// **before** it touches anything that could read a radio, rather than reading a position and then
/// deciding to withhold it. A tool that did the second thing would pass every outcome test in the suite
/// and still be the bug this file exists to catch.
@MainActor
final class RecordingLocationSource: LocationFixProviding {
    private(set) var calls = 0
    var fix: LocationFix?
    var failure: (any Error)?
    /// How long to hold the caller before answering, so a bound is observable without a real 12 s wait.
    var hold: Duration?

    init(fix: LocationFix? = nil, failure: (any Error)? = nil, hold: Duration? = nil) {
        self.fix = fix
        self.failure = failure
        self.hold = hold
    }

    func currentFix() async throws -> LocationFix {
        calls += 1
        if let hold { try? await Task.sleep(for: hold) }
        if let failure { throw failure }
        guard let fix else { throw LocationFailureReason.unavailable }
        return fix
    }
}

/// Counts the questions a sheet was asked, from outside the main actor.
///
/// An actor rather than a counter object, because the asker closure is `@MainActor @Sendable` and
/// whatever it captures has to be sendable — and because "how many times was I asked" is the fact several
/// tests assert, so reading the count must not race the asker.
actor AskCounter {
    private(set) var count = 0
    private let answer: Bool
    private let pause: Duration?

    init(answer: Bool, pause: Duration? = nil) {
        self.answer = answer
        self.pause = pause
    }

    func ask() async -> Bool {
        count += 1
        if let pause { try? await Task.sleep(for: pause) }
        return answer
    }
}

/// A sheet that always answers the same way, shaped like the one in the UI.
@MainActor
func askedSheet(_ counter: AskCounter) -> LocationConsentRequester {
    { await counter.ask() }
}
