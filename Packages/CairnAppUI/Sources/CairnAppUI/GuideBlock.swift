import SwiftUI

/// One step of a how-to sheet: a heading, the reason, and the thing to type.
///
/// The command is monospaced and selectable as one block because it is meant to be copied into a terminal on
/// another machine, while the prose above it says why the command is shaped that way. `command` is nil for a
/// step that happens inside Cairn rather than in a shell, so a step with nothing to type does not render an
/// empty code box.
///
/// The stored prose is not called `body`: `View` already owns that name, and a stored property would shadow
/// the view's own `body`. The initializer keeps the `body:` label the call sites read.
struct GuideBlock: View {
    let title: String
    let prose: String
    let command: String?

    init(title: String, body: String, command: String? = nil) {
        self.title = title
        self.prose = body
        self.command = command
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(CairnTheme.amber)

            Text(prose)
                .font(.callout)
                .foregroundStyle(CairnTheme.stoneLight)
                .fixedSize(horizontal: false, vertical: true)

            if let command {
                Text(command)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(CairnTheme.stoneLight)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CairnTheme.stone.opacity(0.25))
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 4)
    }
}
