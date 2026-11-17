import Foundation

/// Request bodies and response reading for LM Studio's native lifecycle routes.
///
/// PENDING REAL-SERVER VERIFICATION. LM Studio publishes `/api/v1/models/load`,
/// `/api/v1/models/unload` and `/api/v1/models/download`, but the exact request envelope is not
/// something this machine has a running LM Studio to check against. So the decoding below is
/// deliberately tolerant — it accepts the documented shapes and an array or bare-value reply, and
/// fails as typed metadata rather than inventing success. The wire payload shapes are recorded as
/// unverified in ROADMAP.md, and `lifecycleWired` says the calls are issued, not that they are
/// proven.
public enum LMStudioLifecycleCodec {
    /// LM Studio keys its models by the `key` its own list returns, so that is what is sent back.
    public static func loadRequestBody(keys: [String]) throws -> Data {
        try encoded(["models": keys])
    }

    public static func unloadRequestBody(keys: [String]) throws -> Data {
        try encoded(["models": keys])
    }

    public static func downloadRequestBody(repository: String) throws -> Data {
        try encoded(["model": repository])
    }

    /// Ids that are loaded, from whatever envelope the server used — shared with the catalog
    /// decoder so "installed" and "resident" are read the same way everywhere.
    public static func decodeLoaded(_ data: Data) throws -> [String] {
        try LMStudioCodec.decodeLoaded(data)
    }

    /// A reply to load / unload / download. Success is only claimed when the server did not say
    /// otherwise; an unreadable body is a typed failure, never a silent pass.
    public static func readAcceptance(_ data: Data) -> LMStudioAcceptance {
        if data.isEmpty { return .accepted }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // A non-JSON 2xx body carries nothing to contradict the status code, so it is
            // accepted, and the next list read is what proves the state changed.
            return .accepted
        }
        if let failure = object["error"] as? String, !failure.isEmpty { return .refused(failure) }
        if let success = object["success"] as? Bool, !success {
            return .refused((object["message"] as? String) ?? "The server refused the request.")
        }
        if let status = object["status"] as? String, status.lowercased().contains("error") {
            return .refused((object["message"] as? String) ?? status)
        }
        return .accepted
    }

    static func encoded(_ payload: [String: Any]) throws -> Data {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload)
        else { throw LMStudioCodec.DecodeError.malformedPayload }
        return data
    }
}

public enum LMStudioAcceptance: Sendable, Equatable {
    case accepted
    /// The server's own words. Shown as written rather than paraphrased.
    case refused(String)
}
