import SwiftUI
import CairnChatDomain

/// The theme picker's proof: two message bubbles in the theme, shown before the user commits to it.
///
/// A colour list is not a preview. A user picking a theme is asking "will I still be able to read my
/// own message against the model's answer at 11pm", and only the two bubbles side by side on the
/// canvas answer that. This draws the same shapes `MessageRow` draws, so what is picked here is what
/// the transcript will look like — with the theme's own bubbles, not a paraphrase of them.
struct ThemePreviewCard: View {
    private let palette: CairnPalette
    /// Which half to render. The picker shows the half the app would actually use, so the preview
    /// cannot disagree with the app the user is looking at behind it.
    private let scheme: ColorScheme

    init(palette: CairnPalette, scheme: ColorScheme) {
        self.palette = palette
        self.scheme = scheme
    }

    var body: some View {
        let tokens = palette.tokens(for: scheme)
        VStack(alignment: .leading, spacing: 8) {
            bubble(
                who: "You",
                text: "What is on the trail today?",
                fill: tokens.userBubble,
                tint: tokens.accent,
                foreground: tokens.onCanvas
            )
            bubble(
                who: "Cairn",
                text: "Two loops are clear. The lower one is muddy.",
                fill: tokens.assistantBubble,
                tint: tokens.onCanvasMuted,
                foreground: tokens.onCanvas
            )
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tokens.canvas)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(palette.displayName) preview, \(scheme == .dark ? "dark" : "light")")
    }

    private func bubble(
        who: String,
        text: String,
        fill: Color,
        tint: Color,
        foreground: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(who)
                .font(.caption2.weight(.bold))
                .foregroundStyle(tint)
            Text(text)
                .font(.caption)
                .foregroundStyle(foreground)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(fill)
        )
    }
}
