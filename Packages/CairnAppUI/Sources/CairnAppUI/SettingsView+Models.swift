import SwiftUI
import CairnChatDomain

/// The model-library half of Settings: the list a person can browse, and the permission that lets weights
/// move.
///
/// They sit together because they are the two halves of one screen, and they point in opposite directions.
/// Showing the library is a preference and defaults to on — a list that names models asks nothing of
/// anyone, and no request goes to a catalog service to build it. Fetching weights is a permission and
/// defaults to off, because a few gigabytes leaving the device is a decision, and it stays visible in the
/// outbound badge while it is granted.
///
/// The acknowledgement also appears on the download sheet itself, beside the button it gates. That is not
/// a duplicate to trim: the sheet is where the decision is actually being made, and Settings is where it
/// is found again later to be taken back off.
extension SettingsView {

    @ViewBuilder
    var modelsSection: some View {
        Section {
            InfoRow(
                key: .downloadCatalogShown,
                caption: "Names, publishers, stated sizes and stated capabilities, written into the app."
            ) {
                Toggle(
                    isOn: Binding(
                        get: { theme.settings.downloadCatalogIsShown },
                        set: { theme.setDownloadCatalogShown($0) }
                    )
                ) {
                    Text("Show the download library")
                }
                .tint(CairnTheme.amber)
            }
            InfoRow(
                key: .modelDownloadsOutbound,
                caption: "Off until you turn it on. The outbound badge stays up while it can flow."
            ) {
                Toggle(
                    isOn: Binding(
                        get: { theme.settings.modelDownloadsAreAllowed },
                        set: { theme.setModelDownloadsAllowed($0) }
                    )
                ) {
                    Text("Model downloads may reach the internet")
                }
                .tint(CairnTheme.amber)
            }
        } header: {
            Text("Models")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(
                    "A model downloaded here lands on this phone. A model downloaded to a server is "
                        + "fetched by that server, and the tag it is asked for is the exact tag this app "
                        + "names — Cairn never rewrites a model name to guess at what was meant."
                )
                if let error = theme.lastError {
                    Text(error).foregroundStyle(CairnTheme.rust)
                }
            }
            .font(.caption)
            .foregroundStyle(CairnTheme.stoneLight)
        }
    }
}
