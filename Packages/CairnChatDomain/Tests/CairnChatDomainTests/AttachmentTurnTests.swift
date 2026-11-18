import XCTest
@testable import CairnChatDomain

/// What an attachment does to a turn: what travels, what stays on the device, and what stops a send.
///
/// These are the M6 promises a user can actually feel. A photo either reaches a model that can see it or
/// the turn refuses; a document never travels as a file, only as the passages that answered; and a later
/// turn does not quietly re-send bytes the user attached to an earlier one.
@MainActor
final class AttachmentTurnTests: XCTestCase {

    private func image(_ name: String = "photo.jpg") -> ChatAttachment {
        ChatAttachment.image(payload: Data([0xFF, 0xD8, 0xFF, 0x01]), name: name)
    }

    private func document(
        _ name: String = "pump-manual.txt",
        _ text: String = "Wire the motor to a dedicated 20 amp breaker."
    ) -> ChatAttachment {
        ChatAttachment.document(payload: Data(text.utf8), name: name, text: text)
    }

    private func makeSession(_ engine: RecordingEngine) throws -> ChatSessionModel {
        let store = EphemeralStore()
        let conversation = try store.createConversation(
            title: "New chat", mode: .onDeviceOnly, config: ChatConfig(), isTemporary: true
        )
        return ChatSessionModel(conversation: conversation, store: store, providers: [engine])
    }

    func testAnImageAgainstAnEngineThatCannotSeeStopsTheSendAndWritesNothing() async throws {
        let engine = RecordingEngine(seesImages: false)
        let session = try makeSession(engine)
        session.send("look at this", attachments: [image()])
        XCTAssertTrue(session.lastError?.contains("has not been seen to accept images") == true)
        XCTAssertTrue(session.nodes.isEmpty, "a refused turn must not leave a message behind")
        XCTAssertTrue(engine.recorder.all.isEmpty)
    }

    func testAnImageTravelsOnTheTurnItWasAttachedToAndOnNoOtherTurn() async throws {
        let engine = RecordingEngine(seesImages: true)
        let session = try makeSession(engine)
        session.send("what is in this photo", attachments: [image()])
        await SessionHarness.settle(session)
        let first = try XCTUnwrap(engine.recorder.all.first)
        let bytes = try XCTUnwrap(first.messages.last(where: { $0.role == .user })?.imageData)
        XCTAssertEqual(bytes, [image().payload])
        XCTAssertEqual(session.path.last(where: { $0.role == .user })?.attachments.count, 1)

        session.send("and the background?")
        await SessionHarness.settle(session)
        let second = try XCTUnwrap(engine.recorder.all.last)
        XCTAssertTrue(
            second.messages.allSatisfy { $0.imageData.isEmpty },
            "a photo from an earlier turn was re-sent, doubling the bytes of this conversation"
        )
    }

    func testADocumentNeverTravelsAsAFileAndItsPassageTravelsInsideTheBlock() async throws {
        let engine = RecordingEngine(seesImages: false)
        let session = try makeSession(engine)
        session.send("what breaker does the motor need", attachments: [document()])
        await SessionHarness.settle(session)
        let request = try XCTUnwrap(engine.recorder.all.first)
        XCTAssertTrue(request.messages.allSatisfy { $0.imageData.isEmpty })
        let system = try XCTUnwrap(request.messages.first)
        XCTAssertTrue(system.text.contains("1 document"))
        XCTAssertTrue(system.text.contains("pump-manual.txt"))
        XCTAssertTrue(system.text.contains("[1]"), "passages must arrive numbered, not as loose text")
        XCTAssertFalse(
            request.messages.dropFirst().contains { $0.text.contains("20 amp breaker") },
            "the document must not be pasted into the conversation as a user message"
        )
    }

    func testTheAnswerIsCreditedWithTheSourcesItsPassagesCameFrom() async throws {
        let engine = RecordingEngine(seesImages: false)
        let session = try makeSession(engine)
        session.send("what breaker does the motor need", attachments: [document()])
        await SessionHarness.settle(session)
        let answer = try XCTUnwrap(session.path.last(where: { $0.role == .assistant }))
        XCTAssertFalse(answer.citations.isEmpty)
        XCTAssertEqual(answer.citations.first?.documentName, "pump-manual.txt")
        XCTAssertEqual(answer.citations.first?.number, 1)
    }
    func testATurnWithNothingButAPhotoIsAllowedAndNamesTheChatAfterTheFile() async throws {
        let engine = RecordingEngine(seesImages: true)
        let session = try makeSession(engine)
        session.send("   ", attachments: [image("dock-sunset.jpg")])
        await SessionHarness.settle(session)
        XCTAssertEqual(session.conversation.title, "dock-sunset.jpg")
        XCTAssertEqual(session.nodes.count, 2)
    }

    // MARK: - A photo whose bytes live in a file

    /// A conversation that is already stored: a question carrying a photo whose pixels are in a file rather
    /// than in the row, and an answer beside it.
    private func storedTurnWithPhoto(
        engine: RecordingEngine, bytesReadable: Data?
    ) async throws -> ChatSessionModel {
        let store = EphemeralStore()
        var conversation = try store.createConversation(
            title: "Stored", mode: .onDeviceOnly, config: ChatConfig(), isTemporary: true
        )
        let user = ChatTree.append(
            to: [], conversationID: conversation.id, parentID: conversation.activeLeafID,
            role: .user, text: "what is this",
            attachments: [ChatAttachment(kind: .image, name: "photo.jpg", payload: Data())]
        )
        let answer = ChatTree.append(
            to: user.nodes, conversationID: conversation.id, parentID: user.node.id,
            role: .assistant, text: "A dock at sunset.",
            citations: [
                SourceCitation(
                    number: 1, documentName: "pump.txt", chunkIndex: 0, startCharacter: 0,
                    excerpt: "Wire the motor", characterCount: 12
                )
            ]
        )
        for node in answer.nodes { try store.saveNode(node) }
        conversation.activeLeafID = answer.node.id
        try store.saveConversation(conversation)
        let session = ChatSessionModel(conversation: conversation, store: store, providers: [engine])
        session.attachmentBytes = { _ in bytesReadable }
        await session.bootstrap()
        return session
    }

    func testARegenerateRefusesRatherThanAskingAgainWithoutThePhotoItNeeds() async throws {
        let engine = RecordingEngine(seesImages: true)
        let session = try await storedTurnWithPhoto(engine: engine, bytesReadable: nil)
        let answerID = try XCTUnwrap(session.path.last(where: { $0.role == .assistant }))
        session.regenerate(assistantNodeID: answerID.id)
        XCTAssertEqual(session.lastError, ChatSessionModel.unreadableAttachmentMessage)
        XCTAssertEqual(session.nodes.count, 2, "a refused regenerate must not add a branch")
        XCTAssertTrue(engine.recorder.all.isEmpty)
    }

    func testARegenerateReadsThePhotoBackFromItsFileAndAsksWithIt() async throws {
        let engine = RecordingEngine(seesImages: true)
        let session = try await storedTurnWithPhoto(engine: engine, bytesReadable: Data([0x09, 0x09]))
        let answerID = try XCTUnwrap(session.path.last(where: { $0.role == .assistant }))
        session.regenerate(assistantNodeID: answerID.id)
        await SessionHarness.settle(session)
        let request = try XCTUnwrap(engine.recorder.all.last)
        let payloads = try XCTUnwrap(request.messages.last(where: { $0.role == .user })?.imageData)
        XCTAssertEqual(payloads, [Data([0x09, 0x09])])
    }

    func testTheBytesOnTheNodeWinOverTheFileBehindIt() async throws {
        let engine = RecordingEngine(seesImages: true)
        let session = try await storedTurnWithPhoto(engine: engine, bytesReadable: Data([0x01]))
        XCTAssertEqual(session.attachmentPayload(image()), image().payload)
        let stored = ChatAttachment(kind: .image, name: "photo.jpg", payload: Data())
        XCTAssertEqual(session.attachmentPayload(stored), Data([0x01]))
    }

    // MARK: - The tree keeps attachments and sources when it branches

    private let conversationID = UUID()

    func testEditingAMessageCarriesItsAttachmentIntoTheNewSibling() {
        let user = ChatTree.append(
            to: [], conversationID: conversationID, parentID: nil, role: .user, text: "look",
            attachments: [image()]
        )
        let edited = ChatTree.edit(
            nodes: user.nodes, nodeID: user.node.id, newText: "look again"
        )
        // Compared by name and bytes, not by equality: the sibling carries the same file, not a re-picked
        // one, and a fresh id would be a different attachment.
        XCTAssertEqual(edited?.node.attachments.map(\.name), ["photo.jpg"])
        XCTAssertEqual(edited?.node.attachments.first?.payload, image().payload)
        XCTAssertEqual(edited?.node.text, "look again")
    }

    func testRegeneratingCarriesTheSourcesOfTheSameQuestion() {
        let answer = ChatTree.append(
            to: [], conversationID: conversationID, parentID: nil, role: .assistant, text: "A dock.",
            citations: [
                SourceCitation(
                    number: 1, documentName: "notes.txt", chunkIndex: 2, startCharacter: 400,
                    excerpt: "the dock", characterCount: 900
                )
            ]
        )
        let again = ChatTree.regenerate(
            nodes: answer.nodes, assistantNodeID: answer.node.id, providerID: "p", modelID: "m"
        )
        XCTAssertEqual(again?.node.citations, answer.node.citations)
        XCTAssertTrue(again?.node.attachments.isEmpty ?? false)
    }

    func testOnlyTheNewestUsersImagesGoForwardAndDocumentsNeverDo() {
        var nodes: [ChatNode] = []
        let withPhoto = ChatTree.append(
            to: nodes, conversationID: conversationID, parentID: nil, role: .user, text: "one",
            attachments: [image("a.jpg")]
        )
        nodes = withPhoto.nodes
        let withFile = ChatTree.append(
            to: nodes, conversationID: conversationID, parentID: withPhoto.node.id,
            role: .user, text: "two", attachments: [document()]
        )
        nodes = withFile.nodes
        // The newest message carries no photo, so nothing is sent this turn even though a photo is
        // somewhere in the conversation — re-sending it would cost bytes the user never offered.
        XCTAssertTrue(ChatTree.currentTurnImages(in: nodes).isEmpty)
        XCTAssertEqual(ChatTree.documents(in: nodes).map(\.name), ["pump-manual.txt"])
        XCTAssertEqual(ChatTree.images(in: nodes).map(\.name), ["a.jpg"])
        XCTAssertTrue(ChatTree.hasAttachments(in: nodes))
    }

    func testImagesAttachToTheLastRealUserMessageAndNotToAToolResult() {
        let messages = [
            ChatMessagePayload(role: .system, text: "block"),
            ChatMessagePayload(role: .user, text: "question"),
            ChatMessagePayload(role: .assistant, text: "calling", toolCalls: []),
            ChatMessagePayload.toolResult(callID: "call-1", text: "3 records"),
        ]
        let withImages = ChatTree.attaching([Data([0x07])], toLastUserOf: messages)
        XCTAssertEqual(withImages[1].imageData, [Data([0x07])])
        XCTAssertTrue(withImages[3].imageData.isEmpty, "a tool result is not the user's photo")
        XCTAssertTrue(messages.allSatisfy { $0.imageData.isEmpty }, "the input must not be mutated")
    }

    func testNothingAttachedMeansNothingSentAndNoBadge() {
        let nodes = ChatTree.append(
            to: [], conversationID: conversationID, parentID: nil, role: .user, text: "plain"
        ).nodes
        XCTAssertFalse(ChatTree.hasAttachments(in: nodes))
        XCTAssertTrue(ChatTree.currentTurnImages(in: nodes).isEmpty)
        XCTAssertTrue(ChatTree.attaching([Data([0x02])], toLastUserOf: []).isEmpty)
    }
}
