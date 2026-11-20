import SwiftUI
import CairnChatDomain

/// One library entry, as a card.
///
/// A card rather than a table row because the decision being made is "is this the model I want", and that
/// needs the summary, the family, the stated size and the stated capabilities in one glance. The badges
/// are the publisher's words for what it claims, drawn only when the entry claims something; a row that
/// publishes nothing carries no badges rather than badges guessed from a name.
struct ModelCatalogCard: View {
    private var model: ModelCatalogModel
    private var row: LocalCatalogRow

    init(model: ModelCatalogModel, row: LocalCatalogRow) {
        self.model = model
        self.row = row
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.displayName)
                    .font(.body.weight(.semibold))
                Spacer(minLength: 8)
                stateMark
            }
            if !row.lineage.isEmpty {
                Text(row.lineage)
                    .font(.caption)
                    .foregroundStyle(CairnTheme.stoneLight)
            }
            if !row.summary.isEmpty {
                Text(row.summary)
                    .font(.callout)
                    .foregroundStyle(CairnTheme.stoneLight)
                    .lineLimit(2)
            }
            HStack(spacing: 6) {
                ForEach(row.capabilityLabels, id: \.self) { label in
                    ModelCatalogBadge(text: label)
                }
                Spacer(minLength: 4)
                Text(sizeText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(CairnTheme.stoneLight)
            }
            if let status = model.status(for: row), status.isInFlight {
                ModelCatalogProgress(status: status)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("cairn.catalog.card.\(row.repoID)")
    }

    @ViewBuilder private var stateMark: some View {
        if row.isInstalled {
            Text(row.origin.landsOnThisPhone ? "On this phone" : "Installed")
                .font(.caption.weight(.semibold))
                .foregroundStyle(CairnTheme.amber)
        } else if let status = model.status(for: row), !status.isInFlight {
            // A transfer that ended without landing still says so here; the sheet carries the reason.
            Text(status.stage.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(CairnTheme.rust)
        }
    }

    /// "size not stated" is a fact about the entry, not an error to hide. Offering a number nobody
    /// measured would let a person commit their storage to a guess.
    private var sizeText: String {
        guard let bytes = row.downloadBytes else { return "size not stated" }
        return bytesText(bytes)
    }
}

/// The capability chips. They narrow the list and never widen it, so a chip that is on is a requirement
/// every card below it meets.
struct ModelCatalogChipBar: View {
    private var model: ModelCatalogModel

    init(model: ModelCatalogModel) { self.model = model }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(ModelCatalogCapability.allCases) { capability in
                Button {
                    model.filter.toggle(capability)
                } label: {
                    Text(capability.label)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(model.filter.filtering(capability)
                                ? CairnTheme.amber.opacity(0.28)
                                : CairnTheme.stoneLight.opacity(0.14))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("cairn.catalog.chip.\(capability.rawValue)")
            }
            if model.filter.isNarrowed {
                Button("Clear") { model.filter.clearNarrowing() }
                    .font(.caption.weight(.semibold))
            }
        }
        .accessibilityIdentifier("cairn.catalog.chips")
    }
}

struct ModelCatalogBadge: View {
    private var text: String
    init(text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .overlay(Capsule().stroke(CairnTheme.stoneLight.opacity(0.5), lineWidth: 1))
            .foregroundStyle(CairnTheme.stoneLight)
            .accessibilityLabel("States \(text)")
    }
}
