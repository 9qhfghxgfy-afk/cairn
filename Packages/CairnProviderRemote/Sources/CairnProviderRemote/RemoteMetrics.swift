import Foundation
import CairnChatDomain

/// Builds measured metrics. Metrics exist only when the server actually reported token
/// counts ("measured, never estimated"); a dialect that stays silent produces `nil`, and
/// the UI shows "no usage reported" rather than a guess.
enum RemoteMetrics {
    static func make(
        promptTokens: Int?,
        completionTokens: Int?,
        elapsedSeconds: Double,
        timeToFirstTokenSeconds: Double?,
        finishReason: FinishReason
    ) -> GenerationMetrics? {
        guard let completionTokens, completionTokens > 0 else { return nil }
        return GenerationMetrics(
            tokensGenerated: completionTokens,
            promptTokens: promptTokens,
            elapsedSeconds: elapsedSeconds,
            timeToFirstTokenSeconds: timeToFirstTokenSeconds,
            finishReason: finishReason
        )
    }
}
