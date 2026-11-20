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
    // `internal`, not `private`: the idle half of this sheet lives in
    // `ModelDetailSheet+Idle.swift` and the in-flight half in `ModelDetailSheet+Transfer.swift`, and a
    // `private` member is unreachable from an extension in another file.
    var model: ModelCatalogModel
    let snapshot: LocalCatalogRow
    @State var showsMetadata = false
    /// Set by the Cancel button rather than acting on the spot. A cancel is the one transfer control that
    /// cannot be undone, and on a multi-gigabyte download the question is worth one extra tap — asked in
    /// words that name the bytes at stake instead of "Are you sure?".
    @State var confirmingCancel = false

    init(model: ModelCatalogModel, row: LocalCatalogRow) {
        self.model = model
        self.snapshot = row
    }

    /// Re-read from the list so a refresh that lands a download updates the sheet instead of leaving it
    /// describing the state as it was when the card was tapped.
    var row: LocalCatalogRow {
        model.rows.first { $0.repoID == snapshot.repoID } ?? snapshot
    }

    var status: ModelTransferStatus? { model.status(for: row) }

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

    /// The capability badges the publisher states, or a line that says what is stated instead.
    ///
    /// "No capabilities published for this entry." on its own reads as a broken screen when the same entry
    /// lists its size, its quantisation and a context ceiling — the person concludes the app is failing
    /// rather than that the publisher said nothing. `capabilityNote` names the facts that are published,
    /// and only an entry that publishes nothing at all says so. Nothing is inferred here: a capability
    /// Cairn has not been told about is never shown as a badge, because a badge a person acts on has to be
    /// a fact rather than a guess from a model's name.
    private var capabilityRow: some View {
        HStack(spacing: 6) {
            if row.capabilityLabels.isEmpty {
                Text(row.capabilityNote)
                    .font(.caption)
                    .foregroundStyle(CairnTheme.stoneLight)
            } else {
                ForEach(row.capabilityLabels, id: \.self) { label in
                    ModelCatalogBadge(text: label)
                }
            }
        }
        .accessibilityIdentifier("cairn.detail.capabilities")
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

    /// The idle half of the sheet — what to press, and what has to be agreed to first — is in
    /// `ModelDetailSheet+Idle.swift`; the in-flight half is in `ModelDetailSheet+Transfer.swift`.

}


