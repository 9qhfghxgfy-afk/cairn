import SwiftUI
import CairnChatDomain

/// The Installed tab: every model this iPhone holds, the one iOS built in, and the ones the open server
/// reports about itself — in one list, each row saying which of those it is.
///
/// One list rather than three sections, because the question a person brings to this tab is "what do I
/// have", and the same model name can appear twice in it honestly: a GGUF build this phone downloaded and
/// a LAN tag with the same name are different bytes on different machines. The badge is what makes that
/// readable, which is why no row is drawn without one.
struct ModelInstalledList: View {
    private var model: ModelManagerModel

    init(model: ModelManagerModel) { self.model = model }

    var body: some View {
        if model.installedEntries.isEmpty {
            Section {
                Text(emptyText)
                    .font(.callout)
                    .foregroundStyle(CairnTheme.stoneLight)
            } footer: {
                Text("A model that is here is one a turn can use with no server and no badge.")
            }
        } else {
            Section {
                ForEach(model.installedEntries) { entry in
                    ModelInstalledRow(model: model, entry: entry)
                }
            } footer: {
                Text("The badge names the runtime that runs the model. A size is shown only for bytes this "
                     + "phone measured or a server published — never for a model nobody read.")
            }
        }
    }

    /// An empty list says which kind of emptiness it is. A build with no readable model store and a phone
    /// whose store is genuinely empty are different situations, and "no models" describes both while
    /// explaining neither.
    private var emptyText: String {
        model.servingLocalModels
            ? "Nothing is installed yet. The Download tab puts a model on this iPhone; a server reports "
              + "models of its own."
            : "This build cannot reach its model store, so nothing can be installed on this iPhone."
    }
}

/// One Installed row: name, badge, whose it is, what it measures, and Delete only where deleting is real.
///
/// The row never draws both a control and a reason. A Delete button on a row that cannot delete is the
/// failure this whole type exists to prevent — it reads as a promise about Apple's model or someone
/// else's server — and a bare reason with no control at least tells the person what is true.
struct ModelInstalledRow: View {
    private var model: ModelManagerModel
    private var entry: InstalledModelEntry
    @State private var expanded = false
    @State private var confirmingDelete = false

    init(model: ModelManagerModel, entry: InstalledModelEntry) {
        self.model = model
        self.entry = entry
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(entry.displayName)
                        ModelFormatBadge(format: entry.format)
                    }
                    Text(entry.sourceLine)
                        .font(.caption)
                        .foregroundStyle(CairnTheme.stoneLight)
                    Text(factLine)
                        .font(.caption)
                        .foregroundStyle(CairnTheme.stoneLight)
                }
                Spacer(minLength: 8)
                InfoButton(title: entry.infoTitle, text: entry.infoText)
                deleteControl
            }
            if let reason = verdict.blockReason {
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(CairnTheme.stoneLight)
            }
            if expanded, entry.host == .remoteServer, let detail = model.detail,
               detail.id == entry.hostModelID {
                ModelDetailLines(detail: detail)
            }
        }
        // A server row can be asked for more; a phone row has already said everything it knows, and a
        // system row has nothing behind it. So the tap is offered only where an answer exists, and it asks
        // the host rather than the list. The request is made only on the way *in*: `detail` is one shared
        // value on the view model, so re-asking on the way out would spend a round trip on a row that is
        // already closing.
        .contentShape(Rectangle())
        .onTapGesture {
            guard entry.host == .remoteServer else { return }
            expanded.toggle()
            if expanded { Task { await model.inspectRemote(entry) } }
        }
        .confirmationDialog(
            ModelDeletion.confirmationTitle(for: entry),
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete from this iPhone", role: .destructive) {
                Task { await model.removeInstalled(entry) }
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text(ModelDeletion.confirmationBody(for: entry, freedText: freedText))
        }
    }

    /// The rule, asked once per row.
    private var verdict: ModelDeletionVerdict { model.deletionVerdict(for: entry) }

    @ViewBuilder private var deleteControl: some View {
        if verdict.isAllowed {
            Button("Delete", role: .destructive) { confirmingDelete = true }
                .font(.caption.weight(.semibold))
        }
    }

    /// Only measured or published figures. A folder that could not be read reads "size not measured"
    /// rather than the size the publisher advertised, which is a claim about a download and not about this
    /// phone.
    private var factLine: String {
        var parts: [String] = []
        parts.append(entry.sizeBytes.map(bytesText) ?? "size not measured")
        if let files = entry.fileCount { parts.append("\(files) files") }
        if let on = entry.installedOn { parts.append(Self.stamp.string(from: on)) }
        if let detail = entry.detail, !detail.isEmpty { parts.append(detail) }
        return parts.joined(separator: " · ")
    }

    /// What the Delete confirmation may promise to free — only ever the number this phone measured.
    private var freedText: String? {
        guard let bytes = entry.sizeBytes else { return nil }
        return bytesText(bytes)
    }

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

/// The runtime badge. Its own view because the label has to be a sentence: a VoiceOver user who hears
/// "MLX" after a model name is not told what MLX is doing there, and the badge exists precisely to say
/// which runtime runs those bytes.
struct ModelFormatBadge: View {
    private var format: ModelFormat

    init(format: ModelFormat) { self.format = format }

    var body: some View {
        Text(format.badgeText)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(CairnTheme.stone.opacity(0.25), in: Capsule())
            .foregroundStyle(CairnTheme.stoneLight)
            .accessibilityLabel("Runs on \(format.badgeText)")
    }
}

