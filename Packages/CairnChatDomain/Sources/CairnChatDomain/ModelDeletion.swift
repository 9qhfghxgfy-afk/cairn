import Foundation

/// Why a model cannot be removed, in words a person can act on.
///
/// Each case has a different fix, and showing one as another sends someone to the wrong place: "iOS owns
/// this model" is not a failure to retry, and "an answer is still being written" is not a storage
/// problem. The reasons are named here rather than at the button so the list row, the detail sheet, and
/// a test all say the same sentence.
public enum ModelDeletionBlock: String, Sendable, Equatable {
    /// Apple's model. iOS installs it and takes it back; Cairn has no verb for either.
    case systemManaged
    /// The bytes are on somebody else's machine, which is not Cairn's to clear.
    case notOnThisPhone
    /// A turn is running in this model right now, so its weights are mapped into the process.
    case turnRunning
    /// This build cannot reach its own model store.
    case storageUnavailable

    public var reasonText: String {
        switch self {
        case .systemManaged:
            return "iOS manages this model, so Cairn cannot delete it."
        case .notOnThisPhone:
            return "This model lives on the server. Cairn does not delete anything on that machine."
        case .turnRunning:
            return "An answer is still being written with this model. Wait for it to finish, or stop it "
                + "first — deleting the files underneath a running turn would tear the answer in half."
        case .storageUnavailable:
            return "Cairn cannot reach its model storage on this phone."
        }
    }
}

/// Whether one row may be deleted, and what it would cost.
public enum ModelDeletionVerdict: Sendable, Equatable {
    /// Deletable, with the bytes the phone would get back when known.
    case allowed(freedBytes: Int64?)
    case blocked(ModelDeletionBlock)

    public var isAllowed: Bool {
        if case .allowed = self { return true }
        return false
    }

    /// The reason a Delete control is absent, or nil when the row is deletable.
    public var blockReason: String? {
        switch self {
        case .allowed: return nil
        case .blocked(let reason): return reason.reasonText
        }
    }
}

/// The rules in front of taking a model's bytes back.
///
/// Two of them are structural rather than polite: a system-managed model is never deletable no matter
/// what a caller claims, and a model with a turn in flight is never removed from under it. The second is
/// the reason this is a verdict type instead of a boolean — the answer has to say *why not*, because a
/// Delete button that does nothing reads as a broken app and a Delete that works half the time reads as
/// a dangerous one.
public enum ModelDeletion {
    public static func verdict(for entry: InstalledModelEntry) -> ModelDeletionVerdict {
        guard entry.canDelete else {
            return .blocked(entry.isSystemManaged ? .systemManaged : .notOnThisPhone)
        }
        return .allowed(freedBytes: entry.sizeBytes)
    }

    /// The question a destructive control asks, naming the model rather than asking whether the person is
    /// sure — and naming the bytes when the store measured them.
    public static func confirmationTitle(for entry: InstalledModelEntry) -> String {
        "Delete \(entry.displayName)?"
    }

    /// The line under the destructive button.
    ///
    /// A measured figure is stated as the store measured it; an unmeasured one says so rather than
    /// quoting the publisher's advertised size, which is a claim about a download, not about this phone.
    public static func confirmationBody(for entry: InstalledModelEntry, freedText: String?) -> String {
        guard let freedText, !freedText.isEmpty else {
            return "Cairn removes the folder it downloaded and the transfer blocks kept with it. "
                + "The folder has not been measured, so no figure is promised here."
        }
        return "Cairn removes the folder it downloaded and the transfer blocks kept with it — "
            + "\(freedText) freed on this iPhone."
    }
}

/// The reasons a removal refuses, in the words the screen shows.
///
/// No path and no file name: a model store's path is this app's container layout, and none of it belongs
/// in a UI string or a log line. Sizes and reasons only.
public enum InstalledModelError: LocalizedError, Equatable {
    case systemManaged
    case notOnThisPhone
    case turnRunning
    case storageUnavailable
    case removalFailed

    public var errorDescription: String? {
        switch self {
        case .systemManaged: return ModelDeletionBlock.systemManaged.reasonText
        case .notOnThisPhone: return ModelDeletionBlock.notOnThisPhone.reasonText
        case .turnRunning: return ModelDeletionBlock.turnRunning.reasonText
        case .storageUnavailable: return ModelDeletionBlock.storageUnavailable.reasonText
        case .removalFailed: return "The model's files could not be removed."
        }
    }

    /// The same refusal as the rule's own reason, so a view model can answer "why is there no button"
    /// and "why did that fail" from one place.
    public var block: ModelDeletionBlock {
        switch self {
        case .systemManaged: return .systemManaged
        case .notOnThisPhone: return .notOnThisPhone
        case .turnRunning: return .turnRunning
        case .storageUnavailable: return .storageUnavailable
        case .removalFailed: return .storageUnavailable
        }
    }
}
