import SwiftUI
import CairnChatDomain

/// A control with its explanation one tap away, on a strip beneath it.
///
/// The `(i)` is a **sibling** of the control, never inside its label. A toggle's label sits inside the toggle's
/// own tap area and a picker's label opens its menu, so a button placed there can deliver the control's action
/// instead of opening its card — a note that flips the thing it is describing is worse than no note. Placed
/// under the control, in the same row, the tap can only reach the button.
///
/// The caption stays on the same strip so the row keeps its one-line hint and the full card stays one tap
/// away. A row with no caption gets the button alone, right-aligned, rather than an empty line above it.
struct InfoRow<Control: View>: View {
    private let key: SettingInfoKey
    private let caption: String?
    @ViewBuilder private let control: () -> Control

    init(
        key: SettingInfoKey,
        caption: String? = nil,
        @ViewBuilder control: @escaping () -> Control
    ) {
        self.key = key
        self.caption = caption
        self.control = control
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            control()
            HStack(alignment: .center, spacing: 6) {
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(CairnTheme.stoneLight)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                InfoButton(key: key)
            }
        }
    }
}

/// A section header carrying the `(i)` for the group beneath it.
///
/// Two jobs. Where the thing worth explaining is the group rather than one control — a set of header rows, the
/// engines that get shared. And where the row itself is a navigation link: the link makes the entire row its
/// tap target, so that row's `(i)` belongs on the header above it, naming the same control, rather than
/// inside a label the link owns.
struct InfoSectionHeader: View {
    private let title: String
    private let count: Int?
    private let key: SettingInfoKey

    init(_ title: String, count: Int? = nil, key: SettingInfoKey) {
        self.title = title
        self.count = count
        self.key = key
    }

    var body: some View {
        HStack(spacing: 6) {
            SectionHeader(title, count: count)
            InfoButton(key: key)
        }
    }
}
