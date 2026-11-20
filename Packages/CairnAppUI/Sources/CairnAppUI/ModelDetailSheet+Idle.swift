import SwiftUI
import CairnChatDomain

/// The idle half of the detail sheet: one button, and the two things that can stand in front of it.
///
/// A download used to be blocked by sending the person elsewhere — to Settings for the acknowledgement,
/// to another server's Models screen for a pull this server cannot run. Both answers are here instead,
/// because the decision being made is about this model, at this moment. The acknowledgement is one tap
/// that also starts the download it authorises, and the server is named in a chooser that says where the
/// tag is about to go.
extension ModelDetailSheet {
    @ViewBuilder var idleBlock: some View {
        if row.isInstalled { installedNote }
        if model.needsAnotherServer { serverChoice }
        if row.origin.landsOnThisPhone && !model.weightsAreAllowed {
            consentBlock
        } else if !isWaitingOnAServer {
            // No button at all while the tag has nowhere to go. A greyed-out button reads as a broken
            // app; the chooser above already names what is missing.
            downloadButton
        }
    }

    @ViewBuilder private var installedNote: some View {
        Text(row.origin.landsOnThisPhone
                ? "This model is already on this phone."
                : "The server reports this tag as installed.")
            .font(.callout)
            .foregroundStyle(CairnTheme.amber)
    }

    /// True when the tag in front of the user has no server that can take it as things stand: the tab is
    /// on the Ollama library, the open server cannot pull, and no other server has been chosen yet.
    private var isWaitingOnAServer: Bool {
        model.needsAnotherServer && model.pullTarget == nil && !row.origin.landsOnThisPhone
    }

    @ViewBuilder private var downloadButton: some View {
        Button {
            if model.needsAnotherServer, let target = model.pullTarget {
                Task { await model.routePull(to: target, for: row) }
            } else {
                model.download(row)
            }
        } label: {
            Label(downloadLabel, systemImage: "arrow.down.circle")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(CairnTheme.amber)
        .disabled(row.isInstalled || model.isDownloading || isWaitingOnAServer)
        .accessibilityIdentifier("cairn.detail.download")
    }

    /// The button names the machine that will hold the model, because "Download" on a tag pointed at
    /// someone else's server is not the same promise as "Download" to this phone.
    private var downloadLabel: String {
        if model.needsAnotherServer, let target = model.pullTarget {
            return "Pull onto \(target.name)"
        }
        return row.origin.destinationText
    }

    @ViewBuilder private var serverChoice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("This server does not install models, so it cannot take this tag.")
                .font(.callout)
                .foregroundStyle(CairnTheme.stoneLight)
            if model.ollamaChoices.isEmpty {
                Text("No Ollama server is configured. Add one on the Servers screen, or switch this tab "
                        + "back to Hugging Face and download the weights to this phone instead.")
                    .font(.caption)
                    .foregroundStyle(CairnTheme.stoneLight)
            } else {
                Menu {
                    ForEach(model.ollamaChoices) { profile in
                        Button(profile.name) { model.choosePullTarget(profile) }
                    }
                } label: {
                    Label(model.pullTarget?.name ?? "Choose an Ollama server", systemImage: "server")
                }
                .accessibilityIdentifier("cairn.detail.server")
            }
        }
    }

    /// The one tap. It is labelled for both halves it performs, and the line above it says where the
    /// bytes go before the tap, not after.
    @ViewBuilder private var consentBlock: some View {
        Text("Hugging Face is on the public internet. This tap turns on model downloads for the whole "
                + "app and Cairn shows the outbound badge while the weights are in flight. Take it back "
                + "any time in Settings.")
            .font(.caption)
            .foregroundStyle(CairnTheme.stoneLight)
        Button {
            model.allowAndDownload(row)
        } label: {
            Label("Allow & Download", systemImage: "arrow.down.circle")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(CairnTheme.amber)
        .disabled(model.isDownloading || row.isInstalled)
        .accessibilityIdentifier("cairn.detail.allow")
    }
}
