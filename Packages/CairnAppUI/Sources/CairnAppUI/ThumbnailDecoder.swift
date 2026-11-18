import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Turning stored or picked bytes into something small enough to draw in a row.
///
/// This is the one place `CairnAppUI` touches a system image codec, and it decodes only for display: it never
/// writes, never resamples, and never decides what goes to a model. That decision belongs to
/// `ImagePreparationPolicy` in the domain, and the resampling belongs to the app's `ImagePreparing`, so a
/// thumbnail cannot accidentally become the copy the app sends.
///
/// The bytes come from `ChatSessionModel.attachmentPayload`, so this never opens a file itself. When the
/// codec cannot read the data — a file the user deleted in the Files app, a format this iOS cannot decode —
/// the answer is nil, and the row draws the file's name instead of an empty box.
enum ThumbnailDecoder {
    /// A bounded edge for the drawn thumbnail. Decoding is still whole-image — iOS has no cheap partial
    /// decode of an arbitrary JPEG without `ImageIO` downsample options — so the real saving is that a
    /// transcript draws only the images of the messages on screen, not every photograph the chat ever held.
    static let maximumEdge: CGFloat = 96

    static func image(from data: Data) -> Image? {
        #if canImport(UIKit)
        guard let bitmap = UIImage(data: data) else { return nil }
        return Image(uiImage: bitmap)
        #else
        return nil
        #endif
    }
}
