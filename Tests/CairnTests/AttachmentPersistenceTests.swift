import XCTest
import CairnChatDomain
import CairnPersistence

/// The file half of persistence, against a throwaway directory instead of the app's own.
///
/// The default `SwiftDataStore(inMemory:)` gives an in-memory database no directory at all, which is right on
/// a phone and useless in a test: everything worth proving about an attachment file is about a file being
/// written, read back, and removed. So every test here builds an in-memory database **plus** a temporary
/// directory and watches that directory.
///
/// What is being proven, in the order it would hurt to get wrong:
/// - a photograph is written **before** the row that names it, so a row can never describe a file that does
///   not exist — the failure this design exists to prevent;
/// - deleting a message, or the conversation that held it, really removes the bytes;
/// - a row survives without its bytes and says so, rather than pretending to still hold the photograph.
@MainActor
final class AttachmentPersistenceTests: XCTestCase {

    private func freshDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cairn-attachments-\(UUID().uuidString)", isDirectory: true)
    }

    private func makeStore() throws -> (store: SwiftDataStore, files: AttachmentFiles) {
        let files = AttachmentFiles(directory: freshDirectory())
        return (try SwiftDataStore(inMemory: true, attachments: files), files)
    }

    private func conversation(in store: SwiftDataStore, titled title: String = "Attachments") throws -> Conversation {
        try store.createConversation(title: title, mode: .onDeviceOnly, config: .default, isTemporary: false)
    }

    /// A user row carrying one file, exactly as a send would write it.
    private func node(with attachment: ChatAttachment, in conversation: Conversation) -> ChatNode {
        let appended = ChatTree.append(
            to: [], conversationID: conversation.id, parentID: nil, role: .user, text: "look at this"
        )
        var row = appended.node
        row.attachments = [attachment]
        return row
    }

    func testAPhotographIsWrittenBesideTheRowAndReadsBackByItsOwnID() throws {
        let (store, files) = try makeStore()
        let chat = try conversation(in: store)
        let bytes = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x01, 0x02])
        let photo = ChatAttachment.image(payload: bytes, name: "Photo 1", declaredType: "public.jpeg")

        try store.saveNode(node(with: photo, in: chat))

        XCTAssertTrue(files.contains(id: photo.id), "the file is named by the attachment id, not by its name")
        XCTAssertEqual(store.attachmentData(id: photo.id), bytes)
        XCTAssertTrue(store.canStoreAttachments, "a store with a directory can promise it kept the file")

        // The row itself holds no pixels — that is the whole design, so it is asserted rather than assumed.
        let stored = try XCTUnwrap(store.nodes(conversationID: chat.id).first?.attachments.first)
        XCTAssertTrue(stored.payload.isEmpty, "a row never carries the bytes back in")
        XCTAssertEqual(stored.name, "Photo 1")
        XCTAssertEqual(stored.byteCount, bytes.count)
        XCTAssertEqual(stored.declaredType, "public.jpeg")
    }

    func testADocumentKeepsItsTextInTheRowAndItsBytesInTheFile() throws {
        let (store, files) = try makeStore()
        let chat = try conversation(in: store)
        let text = "The north face holds snow longer than the south."
        let document = ChatAttachment.document(
            payload: Data(text.utf8), name: "notes.txt", text: text, declaredType: "public.plain-text"
        )

        try store.saveNode(node(with: document, in: chat))

        let stored = try XCTUnwrap(store.nodes(conversationID: chat.id).first?.attachments.first)
        XCTAssertEqual(stored.text, text, "retrieval must search a file attached three turns ago without a disk")
        XCTAssertEqual(store.attachmentData(id: document.id), Data(text.utf8))
        XCTAssertTrue(files.contains(id: document.id))
    }

    func testDeletingTheMessageDeletesTheFileWithIt() throws {
        let (store, files) = try makeStore()
        let chat = try conversation(in: store)
        let photo = ChatAttachment.image(payload: Data([0xFF, 0xD8, 0x01]), name: "Photo 1")
        let row = node(with: photo, in: chat)
        try store.saveNode(row)
        XCTAssertTrue(files.contains(id: photo.id))

        try store.deleteNode(id: row.id)

        XCTAssertNil(store.attachmentData(id: photo.id))
        XCTAssertFalse(files.contains(id: photo.id), "a deleted message leaves no photograph behind")
    }

    func testDeletingTheConversationDeletesEveryFileItHeld() throws {
        let (store, files) = try makeStore()
        let chat = try conversation(in: store)
        var photos: [ChatAttachment] = []
        for index in 1...3 {
            let photo = ChatAttachment.image(payload: Data(count: index * 4), name: "Photo \(index)")
            try store.saveNode(node(with: photo, in: chat))
            photos.append(photo)
        }
        XCTAssertTrue(photos.allSatisfy { files.contains(id: $0.id) })

        try store.deleteConversation(id: chat.id)

        XCTAssertTrue(photos.allSatisfy { !files.contains(id: $0.id) }, "delete means the bytes go too")
        XCTAssertTrue(try store.nodes(conversationID: chat.id).isEmpty)
    }

    func testARowSurvivesItsFileAndSaysTheBytesAreGone() throws {
        let (store, files) = try makeStore()
        let chat = try conversation(in: store)
        let photo = ChatAttachment.image(payload: Data([0xFF, 0xD8, 0x02]), name: "Photo 1")
        try store.saveNode(node(with: photo, in: chat))

        // What doing it yourself looks like: the file removed in the Files app, or swept by the system. The row
        // is still readable, and the app must not invent pixels to fill the gap.
        try FileManager.default.removeItem(at: files.url(for: photo.id))

        let stored = try XCTUnwrap(store.nodes(conversationID: chat.id).first?.attachments.first)
        XCTAssertNil(store.attachmentData(id: stored.id))
        XCTAssertEqual(stored.name, "Photo 1", "the description outlives the file, because the row holds it")
        XCTAssertEqual(stored.byteCount, 3)
    }

    func testAFileThatCannotBeWrittenFailsTheSaveInsteadOfWritingARowWithoutIt() throws {
        // A path that is already a file cannot become a directory, so every write into it fails. That is the
        // ordering proof in one test: bytes first, row second. A row naming a file that was never written is a
        // message whose photograph silently vanished, which is worse than a send that visibly failed.
        let blocker = freshDirectory()
        try Data("not a directory".utf8).write(to: blocker)

        let store = try SwiftDataStore(inMemory: true, attachments: AttachmentFiles(directory: blocker))
        XCTAssertFalse(store.canStoreAttachments, "and the composer is told, rather than promised a file")

        let chat = try conversation(in: store)
        let photo = ChatAttachment.image(payload: Data([0xFF, 0xD8, 0x03]), name: "Photo 1")
        let row = node(with: photo, in: chat)

        XCTAssertThrowsError(try store.saveNode(row))
        XCTAssertTrue(try store.nodes(conversationID: chat.id).isEmpty, "no row for bytes that never landed")
    }

    func testAnInMemoryStoreWithNoDirectoryKeepsNothingAndSaysSo() throws {
        let store = try SwiftDataStore(inMemory: true)
        XCTAssertFalse(store.canStoreAttachments, "the default in-memory store has nowhere to put a file")

        let chat = try conversation(in: store)
        let photo = ChatAttachment.image(payload: Data([0xFF, 0xD8, 0x04]), name: "Photo 1")
        try store.saveNode(node(with: photo, in: chat))
        XCTAssertNil(store.attachmentData(id: photo.id))
    }
}

