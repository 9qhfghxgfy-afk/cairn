import CairnChatDomain
import CairnPersistence
import XCTest

/// The app-layer join between a store that can read an attachment file and a session that asks for it.
///
/// Neither half can be tested in the module it lives in: the domain must not open a file, and the UI may not
/// import SwiftData. So the seam is one file in `App/`, compiled into the simulator suite for the same reason
/// the residency and tool wiring are — it is the only place the two facts can meet, and it is where a wrong
/// answer would otherwise be found by a user with a missing photograph.
///
/// The two claims worth proving are that a session really is handed the reader (a session with no reader
/// reports a stored photo as unreadable and refuses the turn), and that a session is never promised storage the
/// store does not have — a promise like that is how "it was there yesterday" happens.
@MainActor
final class AttachmentWiringTests: XCTestCase {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cairn-wiring-\(UUID().uuidString)", isDirectory: true)
    }

    private func wired() async throws -> (ChatWorkspace, SwiftDataStore) {
        let store = try SwiftDataStore(inMemory: true, attachments: AttachmentFiles(directory: directory()))
        let workspace = ChatWorkspace(
            persistentStore: store,
            providers: [MockStreamingProvider.instant],
            mode: .onDeviceOnly,
            temporaryChat: false
        )
        // Installed before `start()`, as the app does it: the point of the wiring is that no session is ever
        // built without a reader, so the order is part of what is being tested.
        AttachmentWiring.install(on: workspace, store: store)
        await workspace.start()
        return (workspace, store)
    }

    /// The description a stored row carries: the file's name and size, and none of its bytes.
    private func described(_ photo: ChatAttachment) -> ChatAttachment {
        ChatAttachment(
            id: photo.id, kind: .image, name: photo.name, declaredType: photo.declaredType,
            byteCount: photo.byteCount, payload: Data()
        )
    }

    private func photo() -> ChatAttachment {
        ChatAttachment.image(payload: Data([0xFF, 0xD8, 0xAA, 0xBB]), name: "Photo 1")
    }

    func testTheSessionReadsBackAStoredFileThroughTheWiring() async throws {
        let (workspace, store) = try await wired()
        let session = try XCTUnwrap(workspace.session)
        XCTAssertTrue(session.attachmentStorageAvailable)
        XCTAssertNotNil(session.attachmentBytes, "a session with no reader could never show a stored photo")

        let picture = photo()
        var row = ChatTree.append(
            to: [], conversationID: session.conversation.id, parentID: nil, role: .user, text: "look at this"
        ).node
        row.attachments = [picture]
        try store.saveNode(row)

        XCTAssertEqual(
            session.attachmentPayload(described(picture)), picture.payload,
            "the row's description plus the store's file is the whole picture"
        )
        XCTAssertTrue(
            session.attachmentsReadable(in: [row]),
            "and the turn that has to send that photo is allowed to go rather than be refused for nothing"
        )
    }

    func testAChatStartedAfterTheWiringGetsTheSameReader() async throws {
        let (workspace, _) = try await wired()
        workspace.startNewChat()
        let session = try XCTUnwrap(workspace.session)
        XCTAssertTrue(session.attachmentStorageAvailable)
        XCTAssertNotNil(session.attachmentBytes)
    }

    func testAWorkspaceWithNoFilesBehindItSaysItCannotKeepOne() async throws {
        let store = try SwiftDataStore(inMemory: true)
        let workspace = ChatWorkspace(
            persistentStore: store,
            providers: [MockStreamingProvider.instant],
            mode: .onDeviceOnly,
            temporaryChat: false
        )
        AttachmentWiring.installNothing(on: workspace)
        await workspace.start()

        let session = try XCTUnwrap(workspace.session)
        XCTAssertFalse(session.attachmentStorageAvailable)
        XCTAssertNil(session.attachmentBytes)

        // A staged photo still rides the turn it was picked for, because its bytes are in memory. What is
        // missing is the promise about next time, and the composer is told that instead of guessing at it.
        let picture = photo()
        XCTAssertEqual(session.attachmentPayload(picture), picture.payload)
        XCTAssertNil(session.attachmentPayload(described(picture)))
    }

    func testAStoreThatCouldNotGetADirectoryPassesThatOnRatherThanPromising() async throws {
        // A path that is already a file cannot become a directory, so every write fails. The same blocker the
        // persistence tests use, here to prove the flag travels onward to the session that states it to the
        // user — an installed wiring on a store that cannot write must not read as a store that can.
        let blocker = directory()
        try Data("not a directory".utf8).write(to: blocker)
        let store = try SwiftDataStore(inMemory: true, attachments: AttachmentFiles(directory: blocker))
        let workspace = ChatWorkspace(
            persistentStore: store,
            providers: [MockStreamingProvider.instant],
            mode: .onDeviceOnly,
            temporaryChat: false
        )
        AttachmentWiring.install(on: workspace, store: store)
        await workspace.start()

        XCTAssertFalse(store.canStoreAttachments)
        XCTAssertFalse(
            try XCTUnwrap(workspace.session).attachmentStorageAvailable,
            "the composer must not promise a file this store cannot keep"
        )
    }

    func testTheComposersWarningIsTheSameSentenceAsTheSendsDecision() async throws {
        let (workspace, _) = try await wired()
        let session = try XCTUnwrap(workspace.session)
        var draft = ComposerDraft()
        draft.accept(imageBytes: Data([0xFF, 0xD8, 0x01]), name: "Photo 1")
        XCTAssertEqual(draft.staged.count, 1, "whether this engine can see is not the composer's business")

        // The mock declares no vision, which is the case the warning exists for. Both readings come from the
        // session, so they cannot drift apart — that agreement is what is tested here, not the wording.
        XCTAssertFalse(session.canSeeImages)
        let warning = try XCTUnwrap(draft.visionWarning(in: session))
        XCTAssertEqual(warning, session.visionWarning(for: draft.attachments))
        XCTAssertTrue(session.visionDecision(for: draft.attachments).blocksSend)
    }
}

