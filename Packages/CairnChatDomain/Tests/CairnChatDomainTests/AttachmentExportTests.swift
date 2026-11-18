import XCTest
@testable import CairnChatDomain

/// What an exported chat says about the files it carried, and what it refuses to say.
///
/// An export is a file a user opens in a text editor, diffs against an older export, or sends to another
/// person. Two claims follow, and both are tested here rather than assumed:
///
/// - the file describes an attachment (name, kind, size, the text read from a document) and **never carries
///   its bytes**, because moving a photograph somewhere as a side effect of "export the chat" is a decision
///   the app is not allowed to make for the user;
/// - a grounded answer keeps its sources — file, place in the file, ranking number, a short quote — because
///   a citation that cannot be checked once the file is gone is not a citation.
@MainActor
final class AttachmentExportTests: XCTestCase {
    /// Bytes whose base64 form is easy to look for, so "the file carries no bytes" is an assertion about the
    /// JSON text rather than about a field nobody reads.
    private static let bytes = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06])
    private static let bytesInBase64 = "AQIDBAUG"

    private func conversation() throws -> Conversation {
        let store = EphemeralStore()
        return try store.createConversation(
            title: "Trail notes", mode: .onDeviceOnly, config: ChatConfig(), isTemporary: true
        )
    }

    private func photo() -> ChatAttachment {
        ChatAttachment.image(payload: Self.bytes, name: "Photo 1", declaredType: "public.jpeg")
    }

    private func citation() -> SourceCitation {
        SourceCitation(
            number: 1, documentName: "notes.txt", chunkIndex: 0, startCharacter: 1600,
            excerpt: "The north face holds snow longer.", characterCount: 33, score: 4.2
        )
    }

    /// A user message carrying one photograph, and an answer grounded in a file.
    private func messages(in chat: Conversation) -> (asked: ChatNode, answered: ChatNode) {
        let appended = ChatTree.append(
            to: [], conversationID: chat.id, parentID: nil, role: .user, text: "what does the file say?"
        )
        var asked = appended.node
        asked.attachments = [photo()]
        let answer = ChatTree.append(
            to: appended.nodes, conversationID: chat.id, parentID: asked.id, role: .assistant,
            text: "It says the north face holds snow."
        )
        var answered = answer.node
        answered.citations = [citation()]
        return (asked, answered)
    }

    func testTheFileNamesTheAttachmentAndCarriesNotOneByteOfIt() throws {
        let chat = try conversation()
        let json = String(
            decoding: try ChatExport.data(conversations: [chat], nodes: [messages(in: chat).asked]),
            as: UTF8.self
        )

        XCTAssertTrue(json.contains("Photo 1"))
        XCTAssertTrue(json.contains("public.jpeg"))
        XCTAssertTrue(json.contains("6"), "the size travels, so a reader can tell what is missing")
        XCTAssertFalse(json.contains(Self.bytesInBase64), "no base64 blob of the photograph anywhere")
        XCTAssertFalse(json.contains("payload"), "and no field that could hold one")
    }

    func testAStoredRowThatCarriesNothingWritesWhatItAlwaysWrote() throws {
        let chat = try conversation()
        let plain = ChatTree.append(
            to: [], conversationID: chat.id, parentID: nil, role: .user, text: "no files here"
        ).node
        let json = String(
            decoding: try ChatExport.data(conversations: [chat], nodes: [plain]), as: UTF8.self
        )

        XCTAssertFalse(json.contains("attachments"), "an empty message writes no empty array")
        XCTAssertFalse(json.contains("citations"))
    }

    func testAnImportedAttachmentComesBackAsADescriptionWithNoBytes() throws {
        let chat = try conversation()
        let file = try ChatExport.data(conversations: [chat], nodes: [messages(in: chat).asked])

        let restored = try XCTUnwrap(ChatExport.decode(file).nodes.first?.toNode())
        let attachment = try XCTUnwrap(restored.attachments.first)
        XCTAssertEqual(attachment.kind, .image)
        XCTAssertEqual(attachment.name, "Photo 1")
        XCTAssertEqual(attachment.byteCount, Self.bytes.count)
        XCTAssertEqual(attachment.declaredType, "public.jpeg")
        XCTAssertTrue(attachment.payload.isEmpty, "the bytes were never in the file, so nothing invents them")
    }

    func testAnAttachmentOfAKindThisBuildDoesNotHaveIsRefusedRatherThanGuessed() throws {
        let chat = try conversation()
        var exported = ExportedNode(messages(in: chat).asked)
        var entry = try XCTUnwrap(exported.attachments?.first)
        entry.kind = "hologram"
        exported.attachments = [entry]

        // The nearest kind is never picked: image and document differ in what may leave the device, so
        // guessing would be a privacy decision the app made on the user's behalf.
        XCTAssertNil(exported.toNode())
        XCTAssertFalse(try XCTUnwrap(exported.attachments?.first).carriesBytes)
    }

    func testTheTranscriptSaysWhatWasAttachedAndThatThePixelsAreNotHere() throws {
        let chat = try conversation()
        let pair = messages(in: chat)
        let page = ChatTranscript.markdown(conversation: chat, nodes: [pair.asked, pair.answered])

        XCTAssertTrue(page.contains("**Attached:** Photo 1"))
        XCTAssertTrue(page.contains("The pixels of “Photo 1” are not in this transcript"))
        XCTAssertFalse(page.contains(Self.bytesInBase64))
    }

    func testTheTranscriptNamesWhereEachAnswerCameFrom() throws {
        let chat = try conversation()
        let page = ChatTranscript.markdown(conversation: chat, nodes: [messages(in: chat).answered])

        XCTAssertTrue(page.contains("**Sources**"))
        XCTAssertTrue(page.contains("[1] notes.txt, chunk 1, from character 1600, rank 4.20"))
        XCTAssertTrue(page.contains("The north face holds snow longer."))
        XCTAssertTrue(page.contains("a place in a file on this device"))
    }

    func testACitationWithNoScoreSaysNothingAboutRanking() {
        let unscored = SourceCitation(
            number: 2, documentName: "notes.txt", chunkIndex: 1, startCharacter: 40,
            excerpt: "south face", characterCount: 10
        )
        XCTAssertNil(unscored.scoreLabel)
        XCTAssertEqual(unscored.label, "[2] notes.txt, chunk 2, from character 40")
    }

    func testRetrievalCarriesTheRankingNumberIntoTheCitation() throws {
        let chat = try conversation()
        let text = "The north face holds snow longer than the south face does."
        let document = ChatAttachment.document(payload: Data(text.utf8), name: "notes.txt", text: text)
        var asked = ChatTree.append(
            to: [], conversationID: chat.id, parentID: nil, role: .user, text: "north face snow?"
        ).node
        asked.attachments = [document]

        let outcome = Grounding.ground(
            question: "north face snow", corpus: Grounding.corpus(from: [asked])
        )
        let passage = try XCTUnwrap(outcome.passages.first)
        XCTAssertNotNil(passage.score, "the number that ranked this passage is part of what it is")

        let citation = try XCTUnwrap(outcome.citations.first)
        XCTAssertEqual(citation.score, passage.score)
        XCTAssertTrue(citation.label.contains("rank"))
    }
}

