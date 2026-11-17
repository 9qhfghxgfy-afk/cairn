import SwiftUI
import CairnChatDomain

/// A slider that can only stop on a rung of a ladder.
///
/// Context size is not a free number: a value between rungs is a value no server was started with, and
/// a free field invites one. The slider moves over **rung indices**, so every position it can reach is
/// a rung, and the label under it is the token count that rung means. Snapping is therefore structural,
/// not a rounding step someone has to remember to apply.
struct LadderSlider: View {
    @Binding var value: Int
    let ladder: [Int]

    var body: some View {
        Slider(
            value: Binding(
                get: { Double(SamplingReference.rungIndex(value, of: ladder)) },
                set: { newValue in
                    let rung = Int(newValue.rounded())
                    let index = min(max(rung, 0), ladder.count - 1)
                    value = ladder[index]
                }
            ),
            in: 0...Double(max(ladder.count - 1, 1)),
            step: 1
        )
        .tint(CairnTheme.amber)
        .accessibilityValue(SamplingReference.contextLabel(value))
    }
}
