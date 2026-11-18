import CairnChatDomain
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// The paperclip: the two ways a file gets into a message, and what each of them can hand over.
///
/// Photo Library and Files are separate because they really are separate, and the difference shows up in what
/// Cairn is given: a library item arrives as bytes with no name of its own, a Files item arrives as a
/// security-scoped URL that has to be claimed and then given back. Both paths end the same way — bytes and a
/// name handed to `ComposerDraft`, which decides what they may become. Nothing here writes anywhere, and
/// nothing here reads a file the user did not just point at.
///
/// What Cairn can read is stated in the menu, before the pick rather than after the refusal, because a PDF is
/// a reasonable thing to try and a plain-text-only reader is a surprising limit. Saying it first turns a
/// rejection into a fact the user already had.
struct AttachmentPickerMenu: View {
    let draft: ComposerDraft
    @State private var pickedPhotos: [PhotosPickerItem] = []
    @State private var importingFiles = false

    /// Types the picker is allowed to show. A PDF is in the list deliberately: the extractor refuses it with
    /// the instruction to export it as text first, which is a better answer than hiding the format.
    static let allowedTypes: [UTType] = [
        .image, .plainText, .utf8PlainText, .text, .commaSeparatedText, .json, .sourceCode, .pdf,
    ]

    var body: some View {
        Menu {
            PhotosPicker(selection: $pickedPhotos, matching: .images) {
                Label("Photo Library", systemImage: "photo.on.rectangle.angled")
            }
            Button {
                importingFiles = true
            } label: {
                Label("Files", systemImage: "folder")
            }
            Section {
                Text(
                    "Photos are resized on this phone before they are sent. Documents are read as text here "
                        + "— plain text, CSV and JSON now, and a PDF has to be exported as text first."
                )
                .font(.caption2)
                .foregroundStyle(CairnTheme.stoneLight)
            }
        } label: {
            Image(systemName: "paperclip")
                .font(.system(size: 17))
                .foregroundStyle(draft.isEmpty ? CairnTheme.stoneLight : CairnTheme.amber)
                .padding(.vertical, 4)
        }
        .accessibilityLabel("Attach a file")
        .onChange(of: pickedPhotos) { _, picked in
            guard !picked.isEmpty else { return }
            // The selection is cleared straight away so picking the same photo twice is possible; the bytes
            // are already on their way to the draft by then.
            Task { await take(photos: picked) }
            pickedPhotos = []
        }
        .fileImporter(
            isPresented: $importingFiles,
            allowedContentTypes: Self.allowedTypes,
            allowsMultipleSelection: true
        ) { result in
            take(files: result)
        }
    }

    // MARK: - Taking what was picked

    private func take(photos: [PhotosPickerItem]) async {
        for (offset, item) in photos.enumerated() {
            guard let bytes = try? await item.loadTransferable(type: Data.self), !bytes.isEmpty else {
                draft.refuse("That photo could not be read out of the library. Try again, or pick it from Files.")
                continue
            }
            // No file name of its own, so it gets a name that says what it is without inventing a path on the
            // phone — a path is a fact about the device, not about the message. The preparer reports the type
            // the header actually carries, and adds an extension only when it re-encoded the bytes.
            draft.accept(imageBytes: bytes, name: "Photo \(offset + 1)")
        }
    }

    private func take(files: Result<[URL], Error>) {
        switch files {
        case .success(let urls):
            for url in urls { take(fileAt: url) }
        case .failure:
            // The picker's own failure — a cancelled multi-select, a file iCloud could not fetch. No file was
            // taken in, so the draft stays as it was and the user is told which of the two happened.
            draft.refuse("That pick could not be opened. The files stayed where they were.")
        }
    }

    private func take(fileAt url: URL) {
        // The claim is taken for one read and dropped immediately: a picked file outside the app belongs to
        // the system, and holding a grant Cairn no longer needs would be keeping a permission nobody asked for.
        let claimed = url.startAccessingSecurityScopedResource()
        defer { if claimed { url.stopAccessingSecurityScopedResource() } }
        guard let bytes = try? Data(contentsOf: url) else {
            draft.refuse("Cairn could not read \(url.lastPathComponent). It may still be downloading in Files.")
            return
        }
        let isImage = UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false
        draft.accept(bytes: bytes, name: url.lastPathComponent, isImage: isImage)
    }
}
