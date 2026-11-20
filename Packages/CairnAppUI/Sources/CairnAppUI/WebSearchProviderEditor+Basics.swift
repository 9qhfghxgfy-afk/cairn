import SwiftUI
import CairnChatDomain

/// The instance half of the provider editor: what the row is called, where it is, and what it asks for.
///
/// Split from the credential half because the rules there are about a secret and the rules here are about an
/// address, and the two only share a sheet. Every row here carries its own `(i)`, so the note about what a
/// category does or what a timeout costs is one tap from the field it describes rather than a paragraph at the
/// foot of the form that nobody scrolls back to.
extension WebSearchProviderEditor {

    var basicsSection: some View {
        Section {
            InfoRow(key: .webSearchInstanceName) {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.never)
            }
            InfoRow(
                key: .webSearchAddress,
                caption: "http for a machine on your own network; https for anything else."
            ) {
                TextField("Address", text: $address, prompt: Text("http://192.168.1.20:8888"))
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            InfoRow(key: .webSearchCategories) {
                TextField("Categories", text: $categories, prompt: Text("general, news"))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            InfoRow(key: .webSearchLanguage) {
                TextField("Language", text: $language, prompt: Text("en"))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            InfoRow(key: .webSearchSafeSearch, caption: safeSearch.explanation) {
                Picker("Safe Search", selection: $safeSearch) {
                    ForEach(WebSearchSafeSearch.allCases, id: \.self) { option in
                        Text(option.label).tag(option)
                    }
                }
                .tint(CairnTheme.amber)
            }
            InfoRow(
                key: .webSearchTimeRange,
                caption: timeRange == nil
                    ? "No date filter — the provider decides how far back to look."
                    : "Only results from \(timeRange?.label.lowercased() ?? "")."
            ) {
                Picker("Only From", selection: $timeRange) {
                    Text("Any time").tag(Optional<WebSearchTimeRange>.none)
                    ForEach(WebSearchTimeRange.allCases, id: \.self) { range in
                        Text(range.label).tag(Optional(range))
                    }
                }
                .tint(CairnTheme.amber)
            }
            InfoRow(key: .webSearchTimeout) {
                Stepper(value: $timeoutSeconds, in: WebSearchProviderProfile.timeoutRange) {
                    Text("Timeout: \(timeoutSeconds) s")
                }
            }
        } header: {
            Text("Instance")
        } footer: {
            Group {
                Text(
                    "A private address — a LAN address, a tunnel address, a .local name — may use http, "
                        + "because that network is the thing protecting it. Anything on the public internet "
                        + "must be https, and Cairn refuses it otherwise rather than badging it."
                )
                if let error = model.lastError {
                    Text(error).foregroundStyle(CairnTheme.rust)
                }
            }
            .font(.caption)
            .foregroundStyle(CairnTheme.stoneLight)
        }
    }
}
