import CairnChatDomain
import CoreLocation
import Foundation

/// The device's own position, read with the only API iOS gives for it.
///
/// One shot, by construction. `requestLocation()` asks for a single fix and the manager is never put into
/// continuous mode, so there is no stream to leave running and nothing to unsubscribe from when a turn is
/// cancelled partway — which is what makes "Cairn does not track you" a property of the code rather than a
/// line in a policy.
///
/// Cairn's own consent is settled **before** this type is reached, by `LocationConsentGate`; a refusal never
/// constructs a manager and never wakes a radio. What is left for this file is the system's separate
/// permission, which is a different question with a different answer: the app's sheet says "may Cairn use
/// your location", iOS's prompt says "may Cairn, this time". Hundred-metre accuracy is asked for rather than
/// the best available — a chat answer does not need a metre, and a smaller request is a smaller ask.
@MainActor
final class LocationProvider: NSObject, LocationFixProviding, CLLocationManagerDelegate {
    private let manager: CLLocationManager
    /// The turn waiting for a fix. One at a time: a second caller joins the first rather than starting a
    /// second radio run.
    private var pending: CheckedContinuation<LocationFix, any Error>?
    /// The turn waiting on iOS's own prompt, which is a separate wait from the fix.
    private var permissionWaiter: CheckedContinuation<CLAuthorizationStatus, Never>?
    private var inFlight: Task<LocationFix, any Error>?

    /// The manager is injected so a test can build a provider around one without starting a request.
    init(manager: CLLocationManager = CLLocationManager()) {
        self.manager = manager
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// The protocol requirement is **nonisolated**, so this is the one line that admits what the class is:
    /// a `@MainActor` method cannot satisfy a nonisolated requirement in Swift 6, and CoreLocation is
    /// main-actor work — the manager is built here and delivers here. The requirement is therefore
    /// implemented nonisolated and hops, which keeps `LocationFixProviding` free of `@MainActor` and leaves
    /// every nonisolated test double in the domain module unchanged.
    nonisolated func currentFix() async throws -> LocationFix {
        try await awaitFix()
    }

    private func awaitFix() async throws -> LocationFix {
        if let running = inFlight { return try await running.value }
        // Typed as a throwing task on purpose: `Task { }` over a throwing closure is
        // `Task<Value, any Error>`, so the failure reaches a second caller as a value rather than as an
        // unhandled error. Spelling the type here means a later edit cannot silently narrow it and turn a
        // thrown refusal into a crash.
        let request: Task<LocationFix, any Error> = Task {
            defer { inFlight = nil }
            return try await readOnce()
        }
        inFlight = request
        return try await request.value
    }



    /// One reading, end to end: services, permission, then the fix. Each wait is cancellable, because the
    /// tool gives up on a device that does not answer, and a parked continuation would outlive the turn
    /// that asked.
    private func readOnce() async throws -> LocationFix {
        try await withTaskCancellationHandler {
            try await takeFix()
        } onCancel: {
            Task { @MainActor in self.giveUp(CancellationError()) }
        }
    }

    private func takeFix() async throws -> LocationFix {
        guard CLLocationManager.locationServicesEnabled() else {
            throw LocationFailureReason.servicesDisabled
        }
        if manager.authorizationStatus == .notDetermined {
            // The app's own sheet has been answered yes by the time this runs, so the system prompt is the
            // same decision carried to iOS rather than a second surprise. It is still a prompt a person can
            // refuse, and that refusal is reported as a refusal.
            manager.requestWhenInUseAuthorization()
            let status = await waitForPermission()
            if Task.isCancelled { throw CancellationError() }
            guard status == .authorizedWhenInUse || status == .authorizedAlways else {
                throw LocationFailureReason.permissionDenied
            }
        }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            break
        case .denied, .restricted, .notDetermined:
            throw LocationFailureReason.permissionDenied
        // `default` rather than `@unknown default`: `CLAuthorizationStatus` is imported from an Objective-C
        // NS_ENUM, and a future status that names nothing we can act on is still not a permission we may
        // assume. An unrecognised status is reported as no position rather than read as a yes.
        default:
            throw LocationFailureReason.unavailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            guard pending == nil else {
                continuation.resume(throwing: LocationFailureReason.unavailable)
                return
            }
            pending = continuation
            manager.requestLocation()
        }
    }

    private func waitForPermission() async -> CLAuthorizationStatus {
        await withCheckedContinuation { continuation in
            permissionWaiter = continuation
        }
    }

    /// Ends the current waits. Both are released, because a cancelled turn may be parked on iOS's prompt
    /// rather than on the fix, and a continuation left parked after its caller is gone is a task that never
    /// finishes and a manager that keeps a delegate alive for nothing.
    private func giveUp(_ error: any Error) {
        if let waiter = permissionWaiter {
            permissionWaiter = nil
            waiter.resume(returning: manager.authorizationStatus)
        }
        guard let pending else { return }
        self.pending = nil
        pending.resume(throwing: error)
    }


    // MARK: - CoreLocation's callbacks
    //
    // The manager delivers on the run loop it was created on, which is the main one because that is where
    // this object is built. `assumeIsolated` states that to the checker instead of pretending the class is
    // not main-actor-bound: if Apple ever moved the delivery thread, it would stop here loudly rather than
    // touch actor state from the wrong place.
    //
    // Nothing here captures `manager` inside the hop. `CLLocationManager` is **not** `Sendable`, so capturing
    // it in a `@MainActor` closure is a send the checker rejects — and it is right to reject it: a reference
    // the checker cannot prove is unshared is a reference the checker must not move. CI said so at
    // 44625858672 ("sending 'manager' risks causing data races"). Each method therefore reduces what arrived
    // to a value — a fix, a failure reason, an authorization status — and carries only the value across.

    nonisolated func locationManager(
        _ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]
    ) {
        let outcome: Result<LocationFix, LocationFailureReason>
        if let reading = locations.last {
            outcome = .success(Self.fix(from: reading))
        } else {
            outcome = .failure(.unavailable)
        }
        MainActor.assumeIsolated { settle(with: outcome) }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager, didFailWithError error: any Error
    ) {
        let reason = Self.reason(for: error)
        MainActor.assumeIsolated { fail(with: reason) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // The name is the requirement: `didChangeAuthorization:` was replaced by this one in iOS 14, and an
        // optional delegate method with a name of our own would simply never be called — which would not fail
        // loudly, it would leave the permission wait parked until the tool's budget ran out.
        //
        // The status is read on the delivery thread, outside the hop, because reading a property is not a send
        // and capturing the manager in a main-actor closure is.
        let status = manager.authorizationStatus
        MainActor.assumeIsolated { answerPrompt(with: status) }
    }


    private func settle(with outcome: Result<LocationFix, LocationFailureReason>) {
        guard let continuation = pending else { return }
        pending = nil
        switch outcome {
        case .success(let fix): continuation.resume(returning: fix)
        case .failure(let reason): continuation.resume(throwing: reason)
        }
    }

    private func fail(with reason: LocationFailureReason) {
        guard let continuation = pending else { return }
        pending = nil
        continuation.resume(throwing: reason)
    }

    private func answerPrompt(with status: CLAuthorizationStatus) {
        guard let waiter = permissionWaiter else { return }
        permissionWaiter = nil
        waiter.resume(returning: status)
    }
}

