import SwiftUI
import CairnChatDomain

/// The sampling section: every knob is a set/unset decision first and a value second. An unset knob is
/// absent from the request, which is the only way "let the server decide" can mean anything, so the
/// switch is drawn before the control.
extension ChatConfigEditor {
    var samplingSection: some View {
        Section {
            headlineKnobs
            advancedKnobs
            answerStyleRow
            thinkingRow
            if let supportNote {
                Text(supportNote)
                    .font(.caption)
                    .foregroundStyle(CairnTheme.stoneLight)
            }
        } header: {
            SectionHeader("Sampling", count: config.configuredOptionCount)
        }
    }

    @ViewBuilder var headlineKnobs: some View {
        ladderRow(.contextWindow, ladder: Self.contextLadder)
        doubleRow(.temperature, range: SamplingReference.temperatureRange)
        seedRow
    }

    @ViewBuilder var advancedKnobs: some View {
        DisclosureGroup {
            doubleRow(.topP, range: SamplingReference.topPRange)
            doubleRow(.minP, range: SamplingReference.minPRange)
            topKRow
            ladderRow(.maxTokens, ladder: Self.maxTokensLadder)
            doubleRow(.repeatPenalty, range: SamplingReference.repeatPenaltyRange)
            ladderRow(.repeatLastN, ladder: Self.repeatLastNLadder)
        } label: {
            Text("Advanced knobs")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CairnTheme.stoneLight)
        }
        .tint(CairnTheme.amber)
    }

    /// Ladders, not free text: a free number invites a value the server refuses outright. `max_tokens`
    /// and `repeat_last_n` double like the context ladder does, so the same label helper covers them.
    static let contextLadder = SamplingReference.contextWindowLadder
    static let maxTokensLadder: [Int] = [256, 512, 1024, 2048, 4096, 8192, 16_384, 32_768]
    static let repeatLastNLadder: [Int] = [0, 16, 32, 64, 128, 256, 512]

    // MARK: - Rows

    func doubleRow(_ key: SamplingKey, range: ClosedRange<Double>) -> some View {
        SamplingControlRow(
            title: key.displayName,
            explainer: key.explainer,
            isSet: key.isSet(in: config.sampling),
            isSupported: support.supports(key),
            valueText: String(format: "%.2f", doubleBinding(key).wrappedValue),
            onSetChanged: { setDouble(key, $0) }
        ) {
            Slider(value: doubleBinding(key), in: range, step: 0.01)
                .tint(CairnTheme.amber)
        }
    }

    func ladderRow(_ key: SamplingKey, ladder: [Int]) -> some View {
        SamplingControlRow(
            title: key.displayName,
            explainer: key.explainer,
            isSet: key.isSet(in: config.sampling),
            isSupported: support.supports(key),
            valueText: SamplingReference.contextLabel(intBinding(key, ladder: ladder).wrappedValue),
            onSetChanged: { setInt(key, $0, ladder: ladder) }
        ) {
            Picker(key.displayName, selection: intBinding(key, ladder: ladder)) {
                ForEach(ladder, id: \.self) { rung in
                    Text(SamplingReference.contextLabel(rung)).tag(rung)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(CairnTheme.amber)
        }
    }

    var topKRow: some View {
        SamplingControlRow(
            title: SamplingKey.topK.displayName,
            explainer: SamplingKey.topK.explainer,
            isSet: SamplingKey.topK.isSet(in: config.sampling),
            isSupported: support.supports(.topK),
            valueText: "\(config.sampling.topK ?? SamplingReference.topK)",
            onSetChanged: { on in
                if on { config.sampling.topK = SamplingReference.topK }
                else { config.sampling.clear(.topK) }
            }
        ) {
            Stepper(
                "top_k",
                value: Binding(
                    get: { config.sampling.topK ?? SamplingReference.topK },
                    set: { config.sampling.topK = $0 }
                ),
                in: 1...1000,
                step: 5
            )
            .labelsHidden()
            .tint(CairnTheme.amber)
        }
    }
}


extension ChatConfigEditor {
    var seedRow: some View {
        SamplingControlRow(
            title: SamplingKey.seed.displayName,
            explainer: SamplingKey.seed.explainer,
            isSet: SamplingKey.seed.isSet(in: config.sampling),
            isSupported: support.supports(.seed),
            valueText: config.sampling.seed?.mode.displayName ?? "Random",
            onSetChanged: { on in
                if on { config.sampling.seed = .random(from: 0) }
                else { config.sampling.clear(.seed) }
            }
        ) {
            HStack(spacing: 8) {
                Picker(
                    "Seed",
                    selection: Binding(
                        get: { config.sampling.seed?.mode ?? .random },
                        set: { mode in
                            config.sampling.seed = SeedSetting(
                                mode: mode, value: config.sampling.seed?.value ?? 0
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

                if config.sampling.seed?.mode == .fixed {
                    TextField(
                        "seed value",
                        value: Binding(
                            get: { config.sampling.seed?.value ?? 0 },
                            set: { config.sampling.seed = SeedSetting(mode: .fixed, value: $0) }
                        ),
                        format: .number
                    )
                    .keyboardType(.numberPad)
                    .frame(width: 100)
                    .foregroundStyle(.primary)
                }
            }
        }
    }

    // MARK: - Reading and writing one knob through its key

    /// The row above is generic over the key; this is where the key stops being generic. Kept together
    /// so a new knob is one switch case here rather than a fifth copy of the same closure.
    func doubleBinding(_ key: SamplingKey) -> Binding<Double> {
        Binding(
            get: { readDouble(key) ?? referenceDouble(key) },
            set: { writeDouble(key, $0) }
        )
    }

    func intBinding(_ key: SamplingKey, ladder: [Int]) -> Binding<Int> {
        Binding(
            get: {
                let raw = readInt(key) ?? referenceInt(key)
                // A stored value off the ladder snaps to the nearest rung rather than showing a
                // picker with no selection at all.
                guard ladder.contains(raw) else {
                    return ladder.min(by: { abs($0 - raw) < abs($1 - raw) }) ?? raw
                }
                return raw
            },
            set: { writeInt(key, $0) }
        )
    }

    func setDouble(_ key: SamplingKey, _ on: Bool) {
        guard on else { config.sampling.clear(key); return }
        writeDouble(key, referenceDouble(key))
    }

    func setInt(_ key: SamplingKey, _ on: Bool, ladder: [Int]) {
        guard on else { config.sampling.clear(key); return }
        let reference = referenceInt(key)
        writeInt(key, ladder.contains(reference) ? reference : (ladder.first ?? reference))
    }

    private func readDouble(_ key: SamplingKey) -> Double? {
        switch key {
        case .temperature: return config.sampling.temperature
        case .topP: return config.sampling.topP
        case .minP: return config.sampling.minP
        default: return config.sampling.repeatPenalty
        }
    }

    private func writeDouble(_ key: SamplingKey, _ value: Double) {
        switch key {
        case .temperature: config.sampling.temperature = value
        case .topP: config.sampling.topP = value
        case .minP: config.sampling.minP = value
        default: config.sampling.repeatPenalty = value
        }
    }

    private func readInt(_ key: SamplingKey) -> Int? {
        switch key {
        case .contextWindow: return config.sampling.contextWindow
        case .maxTokens: return config.sampling.maxTokens
        default: return config.sampling.repeatLastN
        }
    }

    private func writeInt(_ key: SamplingKey, _ value: Int) {
        switch key {
        case .contextWindow: config.sampling.contextWindow = value
        case .maxTokens: config.sampling.maxTokens = value
        default: config.sampling.repeatLastN = value
        }
    }

    private func referenceDouble(_ key: SamplingKey) -> Double {
        switch key {
        case .temperature: return SamplingReference.temperature
        case .topP: return SamplingReference.topP
        case .minP: return SamplingReference.minP
        default: return SamplingReference.repeatPenalty
        }
    }

    private func referenceInt(_ key: SamplingKey) -> Int {
        switch key {
        case .contextWindow: return SamplingReference.contextWindow
        case .maxTokens: return 512
        default: return SamplingReference.repeatLastN
        }
    }
}
