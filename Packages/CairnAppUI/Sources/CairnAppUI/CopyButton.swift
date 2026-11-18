import SwiftUI

/// A button that puts text on the pasteboard and says, for a moment, that it did.
///
/// The text is handed in as a closure so an answer is only parsed when the user actually presses the
/// button, and so the caller decides what the text is: the prose of an answer, its Markdown source, or
/// the exact lines of a code block. What is copied is never the rendering.
struct CopyButton: View {
    let title: String
    let text: () -> String
    @Environment(\.cairnTokens) private var tokens
    @State private var copied = false

    init(_ title: String = "Copy", text: @escaping () -> String) {
        self.title = title
        self.text = text
    }

    var body: some View {
        Button(action: copyNow) {
            Label(copied ? "Copied" : title, systemImage: copied ? "checkmark" : "doc.on.doc")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(tokens.onCanvasMuted)
    }

    private func copyNow() {
        guard Pasteboard.copy(text()) else { return }
        copied = true
        Task { try? await Task.sleep(for: .seconds(2)); copied = false }
    }
}
