import SwiftUI
import CairnChatDomain

/// Settings: the theme, the appearance, and the Default Configuration a new chat starts from.
///
/// Each control here writes through `ThemeModel` the moment it changes. These are small, independent
/// values where "Cancel" would be a stranger affordance than the change itself — and the store write is
/// one row, so there is no half-saved state to back out of. The one thing that does get a draft and a
/// Save is the default configuration, on its own screen, because a default that seeds every future chat
/// deserves a deliberate commit.
struct SettingsView: View {
    private let theme: ThemeModel
    /// Lets this screen hand the workspace the new baseline the moment it is saved, so a chat started
    /// five seconds later is seeded from it without relaunching.
    private var workspace: ChatWorkspace?

    init(theme: ThemeModel, workspace: ChatWorkspace? = nil) {
        self.theme = theme
        self.workspace = workspace
    }

    var body: some View {
        Form {
            themeSection
            newChatSection
            turnSection
            aboutSection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .cairnChrome(theme.palette, scheme: theme.colorScheme)
    }

    // MARK: - Theme

    var themeSection: some View {
        Section {
            ForEach(CairnPalette.all) { palette in
                themeRow(palette)
            }
            Picker("Appearance", selection: Binding(
                get: { theme.settings.appearance },
                set: { theme.select(appearance: $0) }
            )) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .tint(CairnTheme.amber)
        } header: {
            Text("Theme")
        } footer: {
            Text(
                "A theme changes what Cairn looks like. It changes nothing about where your words go."
            )
        }
    }

    func themeRow(_ palette: CairnPalette) -> some View {
        Button {
            theme.select(themeID: palette.id)
        } label: {
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    Circle().fill(palette.canvas).frame(width: 18, height: 18)
                        .overlay(Circle().stroke(CairnTheme.stoneLight.opacity(0.5), lineWidth: 1))
                    Circle().fill(palette.surface).frame(width: 18, height: 18)
                        .overlay(Circle().stroke(CairnTheme.stoneLight.opacity(0.5), lineWidth: 1))
                    Circle().fill(palette.accent).frame(width: 18, height: 18)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(palette.displayName).font(.subheadline.weight(.semibold))
                    Text(palette.note)
                        .font(.caption)
                        .foregroundStyle(CairnTheme.stoneLight)
                }
                Spacer(minLength: 0)
                if theme.settings.themeID == palette.id {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(palette.accent)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - New chats

    var newChatSection: some View {
        Section {
            NavigationLink {
                DefaultChatConfigScreen(theme: theme, workspace: workspace)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Default chat configuration").font(.subheadline)
                    Text(
                        theme.settings.hasConfiguredDefaults
                            ? "\(theme.settings.configuredOptionCount) knobs asserted for every new chat"
                            : "Nothing asserted — every new chat lets the server decide"
                    )
                    .font(.caption)
                    .foregroundStyle(CairnTheme.stoneLight)
                }
            }
        } footer: {
            Text(
                "New chats only. A chat you already had keeps the settings it started with — otherwise "
                    + "changing a default here would rewrite answers in a conversation you are reading."
            )
        }
    }

    var turnSection: some View {
        Section("Turns") {
            Toggle(
                "Show tokens per second while a turn runs",
                isOn: Binding(
                    get: { theme.settings.showsGenerationStats },
                    set: { theme.setShowsGenerationStats($0) }
                )
            )
            .tint(CairnTheme.amber)
        }
    }

    var aboutSection: some View {
        Section("Cairn") {
            Label(
                "No account, and nothing leaves this device unless you add a server.",
                systemImage: "lock.shield"
            )
            Text(
                "A server on your own network is reached over that network. Anything sent to the public "
                    + "internet needs your opt-in first, and the app keeps a badge up while it does."
            )
            .font(.caption)
            .foregroundStyle(CairnTheme.stoneLight)
            if let error = theme.lastError {
                Text(error).font(.caption).foregroundStyle(CairnTheme.rust)
            }
        }
    }
}
