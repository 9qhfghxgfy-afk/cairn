import Foundation
import Observation

/// The one question `get_location` may not answer for the user, held as observable state so a sheet can be
/// the answer.
///
/// The domain owns the record (`LocationConsentGate`) and the app layer closes the gate's asker closure over
/// this object, which is what lets `CairnAppUI` draw the question without ever importing CoreLocation: the
/// view speaks in Bools, and the thing that reads a radio never appears in this module.
///
/// Three rules, and they are the reason this is an object rather than a `@State` bool on a view:
///
/// - **A sheet closed without an answer is a no.** Dismissal is not permission; the waiters are resumed with
///   `false` and the gate files that as a denial, so the next turn does not ask again.
/// - **Nobody is left waiting.** A tool parks a turn on a continuation until this object answers. A sheet
///   that could vanish without resuming would hang that turn for the rest of the app's life.
/// - **One sheet, however many ask.** The gate already asks once at a time; joining the waiters rather than
///   raising a second sheet means a second turn gets the same answer instead of a second interruption.
@Observable @MainActor
public final class LocationConsentModel {
    /// True while the question is on screen. `CairnRootView` draws the sheet off this.
    public private(set) var isAsking = false

    /// Everyone blocked on the sheet that is up. The gate hands one question to one asker, so in practice
    /// this holds a single waiter; a queue costs nothing and means a second caller is answered rather than
    /// ignored. Ignored by Observation on purpose: a continuation is plumbing for resuming a turn, not
    /// something a view should redraw over, and tracking it would repaint the sheet for bookkeeping.
    @ObservationIgnored private var waiters: [CheckedContinuation<Bool, Never>] = []


    public init() {}

    /// Puts the question up and waits for it. Called from the gate's asker closure inside a turn, never from
    /// a view.
    public func allowLocation() async -> Bool {
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
            isAsking = true
        }
    }

    /// A button was pressed. The answer goes to the gate by the asker's return value, so nothing is filed
    /// here — this object's whole job is to be the sheet.
    public func resolve(allow: Bool) {
        guard isAsking else { return }
        isAsking = false
        let waiting = waiters
        waiters = []
        for waiter in waiting { waiter.resume(returning: allow) }
    }

    /// Swiped away, or closed. Denial, and resumed — a warning that can be dismissed into silence is a
    /// warning that means nothing, and an unanswered continuation is a turn that never finishes.
    public func declineUnanswered() {
        resolve(allow: false)
    }
}
