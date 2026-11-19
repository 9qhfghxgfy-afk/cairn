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

    func currentFix() async throws -> LocationFix {
        if let running = inFlight { return try await running.value }
        // Typed as a throwing task on purpose. `Task { }` over a throwing closure is `Task<Value, any Error>`,
        // so the failure reaches the second caller as a value rather than as an unhandled error; spelling the
        // type here means a later edit cannot silently narrow it and turn a thrown refusal into a crash.
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

    nonisolated func locationManager(
        _ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]
    ) {
        MainActor.assumeIsolated { deliver(locations) }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager, didFailWithError error: any Error
    ) {
        MainActor.assumeIsolated { fail(with: Self.reason(for: error)) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // The name is the requirement: `didChangeAuthorization:` was replaced by this one in iOS 14, and an
        // optional delegate method with a name of our own would simply never be called — which would not fail
        // loudly, it would leave the permission wait parked until the tool's budget ran out.
        MainActor.assumeIsolated { answerPrompt(with: manager.authorizationStatus) }
    }


    private func deliver(_ locations: [CLLocation]) {
        guard let continuation = pending else { return }
        pending = nil
        guard let reading = locations.last else {
            continuation.resume(throwing: LocationFailureReason.unavailable)
            return
        }
        continuation.resume(returning: Self.fix(from: reading))
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

