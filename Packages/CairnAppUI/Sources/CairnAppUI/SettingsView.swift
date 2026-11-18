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
    /// Not `private`: the theme section lives in `SettingsView+Theme`, and `private` in Swift means
    /// file-private, which a second file cannot see.
    let theme: ThemeModel
    /// Lets this screen hand the workspace the new baseline the moment it is saved, so a chat started
    /// five seconds later is seeded from it without relaunching.
    private var workspace: ChatWorkspace?
    /// The appearance the device is showing, which decides which half of each theme is being drawn —
    /// and therefore which half the swatches and the preview card show.
    @Environment(\.colorScheme) private var deviceScheme

    init(theme: ThemeModel, workspace: ChatWorkspace? = nil) {
        self.theme = theme
        self.workspace = workspace
    }

    var body: some View {
        Form {
            themeSection
            newChatSection
            turnSection
            toolsSection
            aboutSection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .cairnChrome(theme.palette, appearance: theme.settings.appearance)
    }

    /// The half of the theme the app is drawing with right now, so a preview cannot show a variant the
    /// user will never see. Read here rather than in the theme extension: `deviceScheme` is this view's
    /// own environment value, and a same-named `View` modifier is what a second file would resolve.
    var previewScheme: ColorScheme {
        ThemeProvider.resolveScheme(appearance: theme.settings.appearance, deviceScheme: deviceScheme)
    }

    // MARK: - New chats

    var newChatSection: some View {
        Section {
            NavigationLink {
                DefaultChatConfigScreen(theme: theme, workspace: workspace)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Default Configuration").font(.subheadline)
                        ConfiguredBadge(theme.settings.configuredOptionCount)
                    }
                    Text(
                        theme.settings.hasConfiguredDefaults
                            ? "Asserted for every chat you start from now on."
                            : "Nothing asserted — every new chat lets the server decide."
                    )
                    .font(.caption)
                    .foregroundStyle(CairnTheme.stoneLight)
                }
            }
        } header: {
            Text("Default Configuration")
        } footer: {
            Text(
                "New chats only. A chat you already had keeps the settings it started with — otherwise "
                    + "changing a default here would rewrite answers in a conversation you are reading."
            )
        }
    }

    var turnSection: some View {
        Section {
            Toggle(
                isOn: Binding(
                    get: { theme.settings.showsGenerationStats },
                    set: { theme.setShowsGenerationStats($0) }
                )
            ) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Generation Statistics").font(.subheadline)
                    Text(
                        "Show elapsed time, tokens generated, and tokens per second under every answer."
                    )
                    .font(.caption)
                    .foregroundStyle(CairnTheme.stoneLight)
                }
            }
            .tint(CairnTheme.amber)
        } header: {
            Text("Turns")
        } footer: {
            Text(
                "Turning this off hides the numbers; it does not stop them being measured. A turn that "
                    + "took 40 seconds still says so in its record, so a chat you open next month can "
                    + "still be understood."
            )
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
