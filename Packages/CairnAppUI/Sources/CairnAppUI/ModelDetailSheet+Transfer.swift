import SwiftUI
import CairnChatDomain

/// The in-flight half of the detail sheet: the numbers as they arrive, and the three verbs a person
/// reaches for while they arrive.
///
/// Split from the sheet because these things are the part a person reads while something is happening, and
/// they have to survive a sheet that is dismissed — the transfer runs on, and the badge stays up, which is a
/// promise this block exists to keep visibly.
///
/// The verbs are the point of this file. A progress bar with one button under it offers the person two
/// choices — watch it, or throw it away — which is how a phone mid-download becomes a phone that has to start
/// again in the wrong place at the wrong time. Pause keeps what was fetched, Resume carries on from it, and
/// Cancel is the only one that costs anything, so it is the only one that asks.
extension ModelDetailSheet {
    func transferBlock(_ status: ModelTransferStatus) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ModelCatalogProgress(status: status)
            Text(explainer(for: status))
                .font(.caption)
                .foregroundStyle(CairnTheme.stoneLight)
            controlRow(status)
        }
        .confirmationDialog(
            ModelTransferControl.lossLine(doneBytes: status.completedBytes,
                                          totalBytes: status.totalBytes),
            isPresented: $confirmingCancel,
            titleVisibility: .visible
        ) {
            Button("Throw it away", role: .destructive) {
                Task { await model.control(.cancel, for: row) }
            }
            // The other answer is offered because it is usually the one people mean. "Cancel" is what a hand
            // reaches for when it wants to stop for now, and a dialog that only asks whether the person is
            // sure offers one answer and calls the other one a mistake.
            //
            // Deliberately no `role: .cancel` here. A cancel-role button is the sheet's *dismissal* control,
            // and dismissing this dialog by tapping past it runs that button's action — which would pause a
            // download someone only wanted to close the question about. SwiftUI supplies its own Cancel for a
            // dialog with no cancel role, and that one does nothing, which is exactly what a dismissal means.
            Button("Stop for now, keep what was fetched") {
                Task { await model.control(.pause, for: row) }
            }
        }
    }

    /// Why the numbers are standing still, in as many words as are true.
    ///
    /// A parked bar and a failed bar look the same and mean opposite things. The old text — "the bytes are
    /// moving now" — was a lie during a wait and an accusation after a failure, which is how a person ends up
    /// killing a transfer that was about to carry on by itself.
    private func explainer(for status: ModelTransferStatus) -> String {
        switch status.stage {
        case .waiting:
            return "Nothing is arriving right now, and Cairn is holding the connection rather than giving up "
                + "on it. These are the numbers where it stopped, not where it failed."
        case .paused:
            return "Cairn has kept what it fetched. Resume carries on from the same place; Cancel throws it "
                + "away."
        case .failed, .stopped:
            return "Nothing is running. The outbound badge shows only while bytes are actually moving."
        case .queued, .running, .verifying, .finished:
            return "The bytes are moving now. Closing this sheet leaves the transfer running; Cairn keeps the "
                + "outbound badge up until it ends."
        }
    }

    /// The buttons, drawn only for the states that can act.
    ///
    /// Pause needs a transfer in flight and Cancel needs something to throw away; a control that has nothing
    /// to act on is not a disabled button, it is a button that is not drawn. This is also why the row asks the
    /// view model rather than reading the stage itself — whether *this* row can be paused depends on which
    /// machine is pulling, and that is not a fact a sheet can be trusted to remember.
    @ViewBuilder
    private func controlRow(_ status: ModelTransferStatus) -> some View {
        HStack(spacing: 10) {
            if model.canPause(row) {
                controlButton(.pause)
                controlButton(.cancel)
            } else if status.stage == .paused {
                controlButton(.resume)
                controlButton(.cancel)
            } else if status.stage == .failed || status.stage == .stopped {
                controlButton(.resume, named: "Download again")
            }
        }
    }

    @ViewBuilder
    private func controlButton(_ control: ModelTransferControl, named override: String? = nil) -> some View {
        Button {
            if control.destroysProgress {
                confirmingCancel = true
            } else {
                Task { await model.control(control, for: row) }
            }
        } label: {
            Label(override ?? control.label, systemImage: control.symbolName)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .tint(control.destroysProgress ? CairnTheme.rust : CairnTheme.amber)
        .accessibilityIdentifier("cairn.detail.\(control.rawValue)")
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
