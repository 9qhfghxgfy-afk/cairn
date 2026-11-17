import SwiftUI
import CairnChatDomain

/// The seed control: who owns the number, the number itself, and a way to roll a new one.
///
/// Three states, and the sheet must not blur them (see `SeedSetting`):
/// - **unset** — no seed key goes out, and the server applies its own rule;
/// - **Random** — Cairn chose this number. It is still sent on every request, so a replay of the same
///   chat replays the same answers; `Randomize` replaces it;
/// - **Fixed** — the user typed this number and Cairn will not change it.
///
/// Typing a number moves the seed to Fixed rather than editing a Random value in place, because
/// "Cairn chose it" stops being true the moment the user writes it. And Cairn never re-rolls a seed per
/// turn: a node has to replay and export as it was, so the number that produced the answer is the
/// number that is stored.
extension ChatConfigEditor {
    var seedRow: some View {
        SamplingControlRow(
            title: SamplingKey.seed.displayName,
            explainer: SamplingKey.seed.explainer,
            isSet: SamplingKey.seed.isSet(in: config.sampling),
            isSupported: support.supports(.seed),
            valueText: seedValueText,
            reference: "no seed key",
            onSetChanged: { on in
                if on { config.sampling.seed = .random(from: seedCandidate()) }
                else { config.sampling.clear(.seed) }
            }
        ) {
            seedEditor
        }
    }

    private var seedValueText: String {
        guard let seed = config.sampling.seed else { return "Random 0" }
        return "\(seed.value) · \(seed.mode.displayName)"
    }

    @ViewBuilder private var seedEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Picker(
                    "Seed mode",
                    selection: Binding(
                        get: { config.sampling.seed?.mode ?? .random },
                        set: { mode in
                            config.sampling.seed = SeedSetting(
                                mode: mode, value: config.sampling.seed?.value ?? seedCandidate()
                            )
                        }
                    )
                ) {
                    ForEach(SeedSetting.Mode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                Button {
                    config.sampling.seed = .random(from: seedCandidate())
                } label: {
                    Image(systemName: "dice")
                }
                .accessibilityLabel("Randomize the seed")

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                TextField(
                    "seed value",
                    value: Binding(
                        get: { config.sampling.seed?.value ?? 0 },
                        set: { typed in config.sampling.seed = .fixed(typed) }
                    ),
                    format: .number
                )
                .keyboardType(.numberPad)
                .frame(width: 120)
                .foregroundStyle(.primary)
                .accessibilityLabel("Seed value")

                Text(config.sampling.seed?.mode.note ?? SeedSetting.Mode.random.note)
                    .font(.caption2)
                    .foregroundStyle(CairnTheme.stoneLight)
            }
        }
    }
}
