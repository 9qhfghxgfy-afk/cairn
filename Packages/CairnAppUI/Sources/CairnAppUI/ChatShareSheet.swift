import SwiftUI

#if canImport(UIKit)
import UIKit

/// The system's own share sheet, for a chat file the user asked for.
///
/// This is the whole of Cairn's export story. The sheet is where a person decides where the file goes —
/// Files, Mail, AirDrop, another app — and nothing in this app posts, syncs or uploads a chat on its own.
/// A URL is handed over rather than raw bytes, because that is what carries the file's name across, so
/// what lands in Files is called what the chat is called.
struct ChatShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

#else

/// A build with no share sheet on it — a Mac host build, which is what CI's host lane is. Says so, and
/// names the file it would have shared, rather than showing an empty sheet and implying the export worked.
struct ChatShareSheet: View {
    let url: URL

    var body: some View {
        VStack(spacing: 8) {
            Text("No share sheet in this build")
                .font(.headline)
            Text("The export was written to \(url.lastPathComponent).")
                .font(.callout)
                .foregroundStyle(CairnTheme.stoneLight)
        }
        .padding()
    }
}
#endif
