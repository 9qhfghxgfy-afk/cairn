import SwiftUI
import CairnChatDomain

/// Max Tokens, stated the way it actually works: either there is no limit, or there is one.
///
/// This knob is not a slider with a switch beside it. "Unlimited" is the **absence of the key** — Cairn
/// sends nothing and the server answers until it finishes — so drawing a slider at some number and
/// separately claiming it is unset would show a position that means something else. The two-state
/// control is the honest shape, and the ladder only appears once a limit exists.
///
/// `maxTokens` is a sampling parameter the user chooses for their own answer, not a ceiling Cairn puts
/// on the user; nothing here restricts how much Cairn will do.
struct MaxTokensRow: View {
    @Binding var config: ChatConfig
    let isSupported: Bool

    private var isLimited: Bool { config.sampling.maxTokens != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(SamplingKey.maxTokens.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isLimited ? .primary : CairnTheme.stoneLight)
                        InfoButton(
                            title: SamplingKey.maxTokens.displayName,
                            text: SamplingKey.maxTokens.explainer
                        )
                    }
                    Text(statusLine)
                        .font(.caption)
                        .foregroundStyle(CairnTheme.stoneLight)
                }
                Spacer(minLength: 6)
            }

            Picker("Max Tokens", selection: limitBinding) {
                Text("Unlimited").tag(false)
                Text("Limited").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .tint(CairnTheme.amber)

            if isLimited {
                HStack(spacing: 8) {
                    LadderSlider(
                        value: Binding(
                            get: {
                                SamplingReference.snap(
                                    config.sampling.maxTokens ?? SamplingReference.contextWindow,
                                    to: SamplingReference.maxTokensLadder
                                )
                            },
                            set: { config.sampling.maxTokens = $0 }
                        ),
                        ladder: SamplingReference.maxTokensLadder
                    )
                    Text(SamplingReference.contextLabel(config.sampling.maxTokens ?? 0))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(CairnTheme.amber)
                        .frame(minWidth: 44, alignment: .trailing)
                }
            }

            if !isSupported {
                Label(
                    isLimited
                        ? "This server does not read that key, so Cairn leaves it out of the request."
                        : "This server does not read that key.",
                    systemImage: "slash.circle"
                )
                .font(.caption)
                .foregroundStyle(isLimited ? CairnTheme.rust : CairnTheme.stoneLight)
            }
        }
        .padding(.vertical, 2)
    }

    private var statusLine: String {
        if isLimited, let value = config.sampling.maxTokens {
            return "Cairn asks for at most \(SamplingReference.contextLabel(value)) tokens."
        }
        return "Unlimited — Cairn sends no limit; the server answers until it is finished."
    }

    /// Choosing "Limited" puts the chat on the ladder at a real rung; choosing "Unlimited" removes the
    /// key entirely rather than setting it to zero, which would be a limit of zero.
    private var limitBinding: Binding<Bool> {
        Binding(
            get: { isLimited },
            set: { limited in
                if limited {
                    config.sampling.maxTokens = SamplingReference.snap(
                        config.sampling.maxTokens ?? 2048,
                        to: SamplingReference.maxTokensLadder
                    )
                } else {
                    config.sampling.clear(.maxTokens)
                }
            }
        )
    }
}
