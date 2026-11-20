import SwiftUI
import CairnChatDomain

/// The card a library entry opens into: what it is, what it costs, and one button.
///
/// Three states, all of them on the same screen, because a download that leaves this screen with no trace
/// of itself is the failure this whole sheet exists to prevent. Idle states what the entry claims and
/// what it does not; expanded gives the metadata a person checks before committing their storage to a
/// gigabyte; in-flight shows the numbers as they arrive, in the words of whoever is fetching, with a
/// Cancel that really closes the connection.
///
/// The acknowledgement for weights is asked here rather than only in Settings, because the moment a person
/// decides to download a model is the moment the decision is actually about. It is off until granted, and
/// the Download button says what is missing instead of sitting there disabled.
struct ModelDetailSheet: View {
    private var model: ModelCatalogModel
    private let snapshot: LocalCatalogRow
    @State private var showsMetadata = false

    init(model: ModelCatalogModel, row: LocalCatalogRow) {
        self.model = model
        self.snapshot = row
    }

    /// Re-read from the list so a refresh that lands a download updates the sheet instead of leaving it
    /// describing the state as it was when the card was tapped.
    private var row: LocalCatalogRow {
        model.rows.first { $0.repoID == snapshot.repoID } ?? snapshot
    }

    private var status: ModelTransferStatus? { model.status(for: row) }

    var body: some View {
        CairnSheet {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    capabilityRow
                    Button {
                        showsMetadata.toggle()
                    } label: {
                        Label(showsMetadata ? "Fewer details" : "More details",
                              systemImage: showsMetadata ? "chevron.up" : "chevron.down")
                    }
                    .font(.callout.weight(.semibold))
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("cairn.detail.metadata")
                    if showsMetadata { metadataBlock }
                    Divider()
                    if let status { transferBlock(status) } else { idleBlock }
                }
                .padding(16)
            }
            .navigationTitle(row.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { model.focused = nil }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !row.lineage.isEmpty {
                Text(row.lineage).font(.subheadline.weight(.semibold))
                    .foregroundStyle(CairnTheme.stoneLight)
            }
            Text(row.summary).font(.body)
            Text(row.origin.destinationText + " — " + row.repoID)
                .font(.caption.monospaced())
                .foregroundStyle(CairnTheme.stoneLight)
                .textSelection(.enabled)
        }
        .accessibilityIdentifier("cairn.detail.header")
    }

    private var capabilityRow: some View {
        HStack(spacing: 6) {
            if row.capabilityLabels.isEmpty {
                Text("No capabilities published for this entry.")
                    .font(.caption)
                    .foregroundStyle(CairnTheme.stoneLight)
            } else {
                ForEach(row.capabilityLabels, id: \.self) { label in
                    ModelCatalogBadge(text: label)
                }
            }
        }
    }

    private var metadataBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            metaRow("Provider", row.provider)
            metaRow("Series", row.series)
            metaRow("Parameters", row.parameterSize)
            metaRow("Quantisation", row.quantization)
            metaRow("Context", row.contextLength.map { "\($0) tokens" })
            metaRow("Download", row.downloadBytes.map(bytesText) ?? "not stated by the publisher")
        }
        .accessibilityIdentifier("cairn.detail.metadata_block")
    }

    @ViewBuilder private func metaRow(_ label: String, _ value: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.caption).foregroundStyle(CairnTheme.stoneLight)
            Spacer(minLength: 8)
            Text(value ?? "not stated").font(.callout)
        }
    }

    /// Nothing is in flight for this entry. The button says where the bytes will land, and the missing
    /// acknowledgement is shown beside the button that cannot legally run yet rather than two screens
    /// away in Settings.
    @ViewBuilder private var idleBlock: some View {
        if row.isInstalled {
            Text(row.origin.landsOnThisPhone
                    ? "This model is already on this phone."
                    : "The server reports this tag as installed.")
                .font(.callout)
                .foregroundStyle(CairnTheme.amber)
        }
        Button {
            model.download(row)
        } label: {
            Label(row.origin.destinationText, systemImage: "arrow.down.circle")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(CairnTheme.amber)
        .disabled(row.isInstalled || model.isDownloading)
        .accessibilityIdentifier("cairn.detail.download")

        if row.origin.landsOnThisPhone && !model.weightsAreAllowed {
            Toggle(isOn: Binding(
                get: { model.weightsAreAllowed },
                set: { allowed in if allowed { model.allowWeights() } else { model.denyWeights() } }
            )) {
                Text("Model downloads may reach the internet")
                    .font(.callout)
            }
            .tint(CairnTheme.amber)
            .accessibilityIdentifier("cairn.detail.acknowledge")
            Text(ModelCatalogModel.trafficNotice)
                .font(.caption)
                .foregroundStyle(CairnTheme.stoneLight)
        }
    }

    private func transferBlock(_ status: ModelTransferStatus) -> some View {
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

