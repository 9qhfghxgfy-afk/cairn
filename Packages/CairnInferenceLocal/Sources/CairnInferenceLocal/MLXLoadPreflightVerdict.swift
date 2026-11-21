import Foundation

/// The answer to "does this model fit in the memory this app still has", plus the sentence a person
/// reads when it does not.
///
/// Kept apart from the arithmetic that produces it so the words can be read on their own: the copy is
/// the part a person acts on, and a refusal that only prints a number sends them nowhere. Sizes are
/// reported because a size is the thing being decided about; nothing here carries model content, a
/// repository name, or a path.
public enum MLXLoadPreflightVerdict: Sendable, Equatable {
    /// Safe to load: `requiredBytes` is what the load is expected to cost, measured against a fresh
    /// headroom reading.
    case admit(requiredBytes: Int64)
    /// Do not load. The refusal is its own case because each one has a different fix.
    case refuse(MLXPreflightRefusal)

    public var isAdmitted: Bool {
        if case .admit = self { return true }
        return false
    }

    /// What to show the person. `nil` when the load was admitted.
    public var reasonText: String? {
        switch self {
        case .admit: return nil
        case .refuse(let refusal): return refusal.reasonText
        }
    }
}

/// Why a load was refused before a single weight was read.
public enum MLXPreflightRefusal: Sendable, Equatable {
    /// `os_proc_available_memory()` gave no figure, so no promise about fitting can be made either.
    case headroomUnknown(requiredBytes: Int64)
    /// The measured requirement does not fit inside the usable share of the measured headroom.
    case headroomTooLow(requiredBytes: Int64, availableBytes: Int64)
    /// The files on disk could not be sized, so the requirement could not be computed at all.
    case weightsUnmeasurable
    /// Another on-device model is resident and the registry would have to unload it first, which it
    /// declined — the caller asked for a second resident model the reading does not support.
    case residentConflict(String)

    public var reasonText: String {
        switch self {
        case .headroomUnknown(let required):
            return "Cairn cannot measure how much memory this app has left, so it will not load a "
                + "model that needs about \(MemoryByteReport.description(required)). Close other apps "
                + "and try again, or answer from a server on your own network."
        case .headroomTooLow(let required, let available):
            return "This model needs about \(MemoryByteReport.description(required)) of memory and "
                + "this app has \(MemoryByteReport.description(available)) to work with. Close other "
                + "apps, or choose a smaller model."
        case .weightsUnmeasurable:
            return "Cairn could not measure the size of this model's files, so it will not guess at "
                + "loading them. Reinstall the model from the Download tab."
        case .residentConflict(let otherModel):
            return "Another on-device model is already in memory (\(otherModel)) and there is not "
                + "room for two. Unload it first, or answer from a server."
        }
    }
}

/// Turns a byte count into the unit a person reads.
///
/// Sizes only. This is the one place the memory gate speaks in numbers, and a number is typed
/// metadata — the rule the rest of the app already follows for logs.
public enum MemoryByteReport {
    /// MiB below a gibibyte, GiB above it, always "about" rather than a false precise figure.
    public static func description(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 MiB" }
        let mebibytes = Double(bytes) / (1024.0 * 1024.0)
        if mebibytes >= 1024 {
            return String(format: "%.1f GiB", mebibytes / 1024.0)
        }
        return String(format: "%.0f MiB", mebibytes)
    }
}
