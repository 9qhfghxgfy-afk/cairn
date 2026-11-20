import SwiftUI
import CairnChatDomain

/// The in-flight half of the detail sheet: the numbers as they arrive, and the Cancel that really
/// closes the connection.
///
/// Split from the sheet because these two things are the part a person reads while something is
/// happening, and they have to survive a sheet that is dismissed — the transfer runs on, and the badge
/// stays up, which is a promise this block exists to keep visibly.
extension ModelDetailSheet {
    func transferBlock(_ status: ModelTransferStatus) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ModelCatalogProgress(status: status)
            Text("The bytes are moving now. Closing this sheet leaves the transfer running; Cairn keeps "
                    + "the outbound badge up until it ends.")
                .font(.caption)
                .foregroundStyle(CairnTheme.stoneLight)
            Button("Cancel the download", role: .destructive) {
                model.cancel()
            }
            .font(.callout.weight(.semibold))
            .accessibilityIdentifier("cairn.detail.cancel")
        }
    }
}

/// One transfer's numbers, drawn from whichever side stated them. A phone transfer names its own byte
/// counts; a server pull names its own status line and whatever totals it chose to state.
struct ModelCatalogProgress: View {
    private var status: ModelTransferStatus
    init(status: ModelTransferStatus) { self.status = status }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(status.line)
                .font(.callout)
            if let fraction = status.fraction {
                ProgressView(value: fraction)
                Text("\(bytesText(status.completedBytes ?? 0)) of "
                        + "\(bytesText(status.totalBytes ?? 0)) · \(status.percentText)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(CairnTheme.stoneLight)
            } else {
                // No denominator was ever named, so no bar claims to know how far it has to go.
                ProgressView().progressViewStyle(.linear)
                if let done = status.completedBytes {
                    Text("\(bytesText(done)) so far · \(status.percentText)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(CairnTheme.stoneLight)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("cairn.detail.progress")
    }
}
