import SwiftUI
import CairnChatDomain

/// Rows and the download form for the Model Manager, kept apart from the tab container so each
/// file stays small and single-purpose.

struct ModelRunningRow: View {
    private var model: ModelManagerModel
    private var entry: ResidentServerModel

    init(model: ModelManagerModel, entry: ResidentServerModel) {
        self.model = model
        self.entry = entry
    }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.displayName)
                Text(detailLine)
                    .font(.caption)
                    .foregroundStyle(CairnTheme.stoneLight)
            }
            Spacer()
            Button("Release") {
                Task { await model.unload(entry.id) }
            }
            .font(.caption.weight(.semibold))
        }
        .accessibilityElement(children: .combine)
    }

    /// Only the numbers the server actually reported. An estimate here would be read as a fact
    /// about someone else's machine.
    private var detailLine: String {
        var parts: [String] = []
        if let bytes = entry.memoryBytes { parts.append("\(bytesText(bytes)) held") }
        if let vram = entry.vramBytes { parts.append("\(bytesText(vram)) on GPU") }
        if let context = entry.contextLength { parts.append("context \(context)") }
        if let expires = entry.expiresAt {
            parts.append("releases at " + Self.clock.string(from: expires))
        }
        return parts.isEmpty ? "size not reported" : parts.joined(separator: " · ")
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

struct ModelDetailLines: View {
    private var detail: ModelDetail

    init(detail: ModelDetail) { self.detail = detail }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let quantization = detail.quantization {
                Text("Quantization \(quantization)").font(.caption)
            }
            if let context = detail.contextLength {
                Text("Context \(context)").font(.caption)
            }
            if !detail.capabilityLabels.isEmpty {
                Text(detail.capabilityLabels.joined(separator: " · ")).font(.caption)
            }
            if let note = detail.publishedNote, !note.isEmpty {
                Text(note).font(.caption2).foregroundStyle(CairnTheme.stoneLight)
            }
        }
    }
}
