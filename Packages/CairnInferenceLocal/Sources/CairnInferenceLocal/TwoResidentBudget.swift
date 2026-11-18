import Foundation

/// The headroom question a hybrid turn asks before it puts a second set of weights in this
/// process, written as a pure function so the answer is proven on a host, not hoped for on a phone.
///
/// The rule is `ResidentModelPolicy`'s rule restated for the case where the two candidate
/// footprints are not known yet: both may be resident at one instant only when **two** model
/// footprints fit inside the same usable share (4/5) of a fresh `os_proc_available_memory()`
/// reading. A reading of `nil` means the platform declined to say, which is not a licence — the
/// answer is no.
public enum TwoResidentBudget {
    /// The footprint counted for each side. The gate is asked before the candidate models are
    /// resolved, so it cannot know their sizes; this is a deliberately conservative stand-in, and
    /// it is a parameter rather than a hidden constant so a caller with real figures can pass them.
    public static let conservativeModelFootprintBytes: Int64 = 1_500_000_000

    /// True only when a measured reading shows room for both sides at once with the app's own
    /// reserve intact. Overflow saturates to "no" — an absurd footprint never reads as a fit.
    public static func allowsTwoResident(
        headroomBytes: Int64?,
        modelFootprintBytes: Int64 = conservativeModelFootprintBytes
    ) -> Bool {
        guard let headroom = headroomBytes, headroom > 0, modelFootprintBytes > 0 else { return false }

        var total: Int64 = 0
        for _ in 0..<2 {
            let (next, overflow) = total.addingReportingOverflow(modelFootprintBytes)
            if overflow { return false }
            total = next
        }

        let (scaled, overflow) = headroom.multipliedReportingOverflow(
            by: Int64(MemoryFitEstimator.usableNumerator)
        )
        if overflow { return false }
        return total <= scaled / Int64(MemoryFitEstimator.usableDenominator)
    }
}
