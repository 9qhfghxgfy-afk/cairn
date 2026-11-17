import SwiftUI
import CairnChatDomain

/// The Download tab: fetch a model into the server's own library, with live progress and a Stop
/// that really closes the connection.
///
/// The footer matters as much as the button. A download here lands on the machine running the
/// server, not on the phone — and for a public-internet server it means bytes leaving the device,
/// which is what the outbound badge is for.
struct ModelDownloadForm: View {
    private var model: ModelManagerModel
    @State private var requested = ""

    init(model: ModelManagerModel) { self.model = model }

    var body: some View {
        Section {
            TextField("Model name, as the server names it", text: $requested)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body.monospaced())

            Button {
                let name = requested.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                model.pull(name)
            } label: {
                Label("Download to this server", systemImage: "arrow.down.circle")
            }
            .disabled(requested.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      || model.isDownloading)

            if model.isDownloading, let progress = model.pullProgress {
                ModelProgressRow(model: model, progress: progress)
            }
        } footer: {
            Text("The model is stored by the server, not on this phone. A server on your own network downloads over that network; a server on the public internet pulls bytes through it, and Cairn shows the outbound badge while it does.")
        }
    }
}

struct ModelProgressRow: View {
    private var model: ModelManagerModel
    private var progress: ModelPullProgress

    init(model: ModelManagerModel, progress: ModelPullProgress) {
        self.model = model
        self.progress = progress
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(progress.statusText)
                .font(.callout)
            if let fraction = progress.fraction {
                ProgressView(value: fraction)
                Text(bytesText(progress.completedBytes ?? 0) + " of " + bytesText(progress.totalBytes ?? 0))
                    .font(.caption)
                    .foregroundStyle(CairnTheme.stoneLight)
            } else {
                // No denominator means the server never named a total. An indeterminate bar says
                // that honestly; a fake 0% bar would claim to know.
                ProgressView().progressViewStyle(.linear)
                if let done = progress.completedBytes {
                    Text(bytesText(done) + " so far").font(.caption)
                        .foregroundStyle(CairnTheme.stoneLight)
                }
            }
            Button("Stop", role: .destructive) {
                model.stopPull()
            }
            .font(.callout.weight(.semibold))
        }
        .accessibilityElement(children: .combine)
    }
}

/// Bytes in the user's units. Foundation's formatter, so a gigabyte means the same thing here as
/// it does in the Files app.
func bytesText(_ value: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useAll]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: value)
}
