import Foundation

/// The single-resident rule, expressed as a pure decision so it is unit-testable without a phone.
///
/// Hard rule: never hold two on-device models resident unless `os_proc_available_memory()` says
/// there is room for both **with the app's own reserve left intact**. Refusing a load is always
/// safe; overflowing the memory ceiling kills the process and loses the conversation.
public enum ResidentRefusal: String, Sendable, Equatable {
    case footprintBeyondHeadroom
    case secondResidentBeyondHeadroom

    public var reasonText: String {
        switch self {
        case .footprintBeyondHeadroom:
            return "Not enough memory free for this model at the requested context length."
        case .secondResidentBeyondHeadroom:
            return "Another on-device model is already resident and there is not room for two."
        }
    }
}

public enum ResidentDecision: Sendable, Equatable {
    case admit
    /// Unload these models first, then load. The common path: one model at a time.
    case evictThenAdmit(evict: [String])
    case refuse(ResidentRefusal)
}

public enum ResidentModelPolicy {
    /// - Parameter allowSecondResident: false unless the caller has a reason the rule permits.
    ///   A headroom reading of `nil` is **unknown**, not unlimited, so a second resident model is
    ///   never admitted on an unknown reading.
    public static func decide(
        current: [ResidentModel],
        candidate: ResidentModel,
        headroomBytes: Int64?,
        allowSecondResident: Bool = false
    ) -> ResidentDecision {
        // Already resident: loading is a no-op, and evicting it to reload it would be worse.
        if current.contains(where: { $0.modelID == candidate.modelID }) { return .admit }

        // Alone, it must still fit on its own.
        if let headroom = headroomBytes, candidate.footprintBytes > headroom {
            return .refuse(.footprintBeyondHeadroom)
        }
        guard !current.isEmpty else { return .admit }

        // A second resident model needs a measured "both fit inside the reserve" answer.
        if allowSecondResident, let headroom = headroomBytes,
           fitsAlongside(current: current, candidate: candidate, headroomBytes: headroom) {
            return .admit
        }

        // Eviction is only honest if removing the current set actually frees enough.
        if let headroom = headroomBytes, candidate.footprintBytes > headroom {
            return .refuse(.secondResidentBeyondHeadroom)
        }
        return .evictThenAdmit(evict: current.map(\.modelID))
    }

    /// True when the resident set plus the candidate stays inside the 80% headroom figure the
    /// estimator uses for a trusted fit.
    public static func fitsAlongside(
        current: [ResidentModel],
        candidate: ResidentModel,
        headroomBytes: Int64
    ) -> Bool {
        var total = candidate.footprintBytes
        for model in current {
            let (next, overflow) = total.addingReportingOverflow(model.footprintBytes)
            if overflow { return false }
            total = next
        }
        let (scaled, overflow) = headroomBytes.multipliedReportingOverflow(by: Int64(MemoryFitEstimator.usableNumerator))
        if overflow { return false }
        return total <= scaled / Int64(MemoryFitEstimator.usableDenominator)
    }
}
