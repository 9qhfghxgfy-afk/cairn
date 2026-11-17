import SwiftUI
import CairnChatDomain

/// The sampling section: every knob is a set/unset decision first and a value second. An unset knob is
/// absent from the request, which is the only way "let the server decide" can mean anything, so the
/// switch is drawn before the control and the reference value is named in its status line.
///
/// The section header carries the "N configured" count, which is the one number that answers "does
/// this chat ask anything of the server at all" without reading nine rows.
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
        ladderRow(.contextWindow, ladder: SamplingReference.contextWindowLadder)
        doubleRow(.temperature, range: SamplingReference.temperatureRange)
        seedRow
    }

    @ViewBuilder var advancedKnobs: some View {
        DisclosureGroup {
            doubleRow(.topP, range: SamplingReference.topPRange)
            doubleRow(.minP, range: SamplingReference.minPRange)
            topKRow
            MaxTokensRow(config: $config, isSupported: support.supports(.maxTokens))
            doubleRow(.repeatPenalty, range: SamplingReference.repeatPenaltyRange)
            ladderRow(.repeatLastN, ladder: SamplingReference.repeatLastNLadder)
        } label: {
            HStack(spacing: 6) {
                Text("Advanced Options")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CairnTheme.stoneLight)
                if advancedConfiguredCount > 0 {
                    ConfiguredBadge(advancedConfiguredCount)
                }
            }
        }
        .tint(CairnTheme.amber)
    }

    /// How many of the collapsed knobs are asserted, so a closed group does not hide a number the user
    /// has to expand it to find.
    var advancedConfiguredCount: Int {
        SamplingKey.advancedKeys.filter { $0.isSet(in: config.sampling) }.count
    }

    // MARK: - Rows

    func doubleRow(_ key: SamplingKey, range: ClosedRange<Double>) -> some View {
        SamplingControlRow(
            title: key.displayName,
            explainer: key.explainer,
            isSet: key.isSet(in: config.sampling),
            isSupported: support.supports(key),
            valueText: String(format: "%.2f", doubleBinding(key).wrappedValue),
            reference: referenceText(referenceDouble(key)),
            onSetChanged: { setDouble(key, $0) }
        ) {
            Slider(value: doubleBinding(key), in: range, step: 0.01)
                .tint(CairnTheme.amber)
        }
    }

    /// A knob whose legal values are a fixed ladder, drawn as a snapping slider.
    func ladderRow(_ key: SamplingKey, ladder: [Int]) -> some View {
        SamplingControlRow(
            title: key.displayName,
            explainer: key.explainer,
            isSet: key.isSet(in: config.sampling),
            isSupported: support.supports(key),
            valueText: SamplingReference.contextLabel(intBinding(key, ladder: ladder).wrappedValue),
            reference: referenceText(referenceInt(key)),
            onSetChanged: { setInt(key, $0, ladder: ladder) }
        ) {
            LadderSlider(value: intBinding(key, ladder: ladder), ladder: ladder)
        }
    }

    var topKRow: some View {
        SamplingControlRow(
            title: SamplingKey.topK.displayName,
            explainer: SamplingKey.topK.explainer,
            isSet: SamplingKey.topK.isSet(in: config.sampling),
            isSupported: support.supports(.topK),
            valueText: "\(config.sampling.topK ?? SamplingReference.topK)",
            reference: "\(SamplingReference.topK)",
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
                in: SamplingReference.topKRange,
                step: 5
            )
            .labelsHidden()
            .tint(CairnTheme.amber)
        }
    }
}
