import SwiftUI
import CairnChatDomain

/// Reading and writing one knob through its `SamplingKey`.
///
/// The rows above are generic over the key; this is where the key stops being generic. Kept together so
/// a new knob is one switch case here rather than a fifth copy of the same closure — and so the two
/// rules that matter stay in one place: a getter never invents a value for an unset knob (it shows the
/// reference), and a setter never writes anything when the switch goes off.
extension ChatConfigEditor {
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
                // control with no selection at all.
                return SamplingReference.snap(raw, to: ladder)
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
        writeInt(key, SamplingReference.snap(reference, to: ladder))
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

    /// Read by the rows to label what an unset knob would have used, so the status line can name the
    /// reference it is not sending.
    func referenceDouble(_ key: SamplingKey) -> Double {
        switch key {
        case .temperature: return SamplingReference.temperature
        case .topP: return SamplingReference.topP
        case .minP: return SamplingReference.minP
        default: return SamplingReference.repeatPenalty
        }
    }

    func referenceInt(_ key: SamplingKey) -> Int {
        switch key {
        case .contextWindow: return SamplingReference.contextWindow
        case .maxTokens: return SamplingReference.maxTokensLadder.first ?? 256
        default: return SamplingReference.repeatLastN
        }
    }
}
