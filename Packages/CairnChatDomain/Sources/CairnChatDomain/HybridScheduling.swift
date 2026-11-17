import Foundation

/// One batch of candidates the engine may run at the same instant.
public struct HybridRunGroup: Sendable, Equatable {
    /// Indexes into the plan's candidate array, in declared order.
    public var indexes: [Int]
    public var concurrent: Bool

    public init(indexes: [Int], concurrent: Bool) {
        self.indexes = indexes
        self.concurrent = concurrent
    }

    public var isSingle: Bool { indexes.count == 1 }
}

/// What may run together in one hybrid turn — the residency rule as a pure function, so it is
/// proven on a macOS host instead of hoped for on a phone.
///
/// A remote candidate costs the app nothing but a socket, so any number of them run at once. An
/// on-device candidate holds weights in this process. One on-device candidate may still run
/// alongside the remotes; **two** on-device candidates never overlap unless the injected
/// residency gate says a fresh reading has room for both, and when they must take turns they do
/// so with a release between them.
public enum HybridScheduling {

    public static func candidateGroups(
        networkClasses: [NetworkClass],
        allowsTwoOnDeviceModelsResident: Bool = false
    ) -> [HybridRunGroup] {
        let all = Array(networkClasses.indices)
        let onDevice = all.filter { networkClasses[$0] == .onDevice }
        let remote = all.filter { networkClasses[$0] != .onDevice }

        guard onDevice.count > 1, !allowsTwoOnDeviceModelsResident else {
            return [HybridRunGroup(indexes: all, concurrent: all.count > 1)]
        }

        // Remotes first and together, then the on-device candidates one at a time. Running the
        // phone's model last also gives it the whole memory budget rather than a share.
        var groups: [HybridRunGroup] = []
        if !remote.isEmpty {
            groups.append(HybridRunGroup(indexes: remote, concurrent: remote.count > 1))
        }
        for index in onDevice {
            groups.append(HybridRunGroup(indexes: [index], concurrent: false))
        }
        return groups
    }

    /// True when running this group put on-device weights into this process, which is what
    /// decides whether a release is owed before anything else on-device runs.
    public static func groupRanOnDevice(
        _ group: HybridRunGroup,
        networkClasses: [NetworkClass]
    ) -> Bool {
        group.indexes.contains { networkClasses[$0] == .onDevice }
    }

    /// The synthesizer reads every draft, so it runs after the candidates by construction. When
    /// it is itself on-device it must additionally run **after** the last on-device candidate has
    /// been released — two on-device models resident is the same rule as before.
    public static func synthesisNeedsRelease(
        synthesizerClass: NetworkClass?,
        candidatesRanOnDevice: Bool
    ) -> Bool {
        synthesizerClass == .onDevice && candidatesRanOnDevice
    }

    /// The synthesizer default, in one rule: remote first. Only when there is no remote
    /// candidate at all does an on-device candidate get the job, and then it runs sequentially.
    public static func resolveSynthesizer(
        plan: HybridPlan,
        networkClasses: [NetworkClass]
    ) -> HybridCandidate? {
        if let chosen = plan.synthesizer, chosen.isChosen { return chosen }
        let remoteIndex = plan.candidates.indices.first { index in
            index < networkClasses.count && networkClasses[index] != .onDevice
        }
        guard let index = remoteIndex ?? plan.candidates.indices.first else { return nil }
        return plan.candidates[index]
    }
}