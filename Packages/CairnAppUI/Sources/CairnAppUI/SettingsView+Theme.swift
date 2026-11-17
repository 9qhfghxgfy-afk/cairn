import SwiftUI
import CairnChatDomain

/// The theme section of Settings: every theme, its swatches, and a live preview of what picking it
/// does to a conversation.
///
/// Swatches alone are not enough, and a checkmark alone is worse. A theme is chosen to make a
/// transcript readable, so the section shows two message bubbles in the theme being considered, in the
/// appearance the app is actually using — which is also the point of splitting a theme into a light
/// half and a dark half in the first place.
extension SettingsView {
    var themeSection: some View {
        Section {
            ForEach(ThemeProvider.themes) { palette in
                themeRow(palette)
            }
            ThemePreviewCard(palette: theme.palette, scheme: previewScheme)
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
                "A theme changes what Cairn looks like, in light and in dark. It changes nothing about "
                    + "where your words go."
            )
        }
    }

    /// The half of the theme the app is drawing with, supplied by `SettingsView`, which owns the
    /// environment value that decides it.

    func themeRow(_ palette: CairnPalette) -> some View {
        Button {
            theme.select(themeID: palette.id)
        } label: {
            HStack(spacing: 10) {
                swatches(for: palette)
                VStack(alignment: .leading, spacing: 2) {
                    Text(palette.displayName).font(.subheadline.weight(.semibold))
                    Text(palette.note)
                        .font(.caption)
                        .foregroundStyle(CairnTheme.stoneLight)
                }
                Spacer(minLength: 0)
                if theme.settings.themeID == palette.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(palette.tokens(for: previewScheme).accent)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(palette.displayName)
        .accessibilityValue(theme.settings.themeID == palette.id ? "Selected" : "Not selected")
    }

    /// Canvas, surface and accent of the half being previewed. A row that painted the other half would
    /// advertise a look the user would not get.
    func swatches(for palette: CairnPalette) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(palette.tokens(for: previewScheme).swatches.enumerated()), id: \.offset) {
                _, color in
                Circle()
                    .fill(color)
                    .frame(width: 18, height: 18)
                    .overlay(Circle().stroke(CairnTheme.stoneLight.opacity(0.5), lineWidth: 1))
            }
        }
    }
}
