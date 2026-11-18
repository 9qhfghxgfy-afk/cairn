import XCTest
import SwiftUI
import UIKit
import CairnChatDomain
@testable import CairnAppUI
@testable import CairnPersistence

/// What the M5 screens promise, checked where the promise lives: an exported file really is the chat it
/// came from, and a highlighted code line keeps every character it was given.
///
/// The pixels are not asserted, and no view is put on screen here. Two claims were taken out of this file,
/// and both left for the same reason: they asked a system service to answer to a process that is not a
/// running app, and the lane paid for it. The first hosted the new screens in a `UIWindow` with no window
/// scene to measure that they built a layout (removed in `011c1b8`). The second wrote text to
/// `UIPasteboard.general` and read it back — the only call in this whole suite that reaches a system daemon,
/// and a pasteboard read from a test process with no app in the foreground is a call that can wait forever
/// for an answer that will not come. Both runs that carried it, `44379381555` and `44384383553`, ended with
/// the simulator lane killed by its own job timeout with the build green and not one test finished. Whether
/// the pasteboard was the blocker is not proven from this machine — it is the only candidate left standing,
/// and it is the only thing here that is not pure computation or plain file writing.
///
/// Neither claim is dropped without a home: what a copy hands back is checked here as far as the code that
/// decides it goes (`testCopyingProseGivesWhatWasReadRatherThanWhatWasMarkedUp`), and that the text really
/// reaches the pasteboard and reads back on a phone is line 6 of the M5 device checklist in `ROADMAP.md`.
/// What is proved here is the part a person depends on and cannot see: the bytes handed to the share sheet
/// are the whole chat, and colour never edits the source.
@MainActor
final class ChatExportAndRenderingTests: XCTestCase {
    /// The mock streams on its own clock, so a turn is waited for rather than assumed. The helper lives
    /// here because the domain's harness is inside the domain's test target and is not shared.
    private func settle(_ session: ChatSessionModel) async {
        for _ in 0..<500 where session.isBusy {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTAssertFalse(session.isBusy, "the mock never finished the turn")
    }

    private func workspace() async throws -> ChatWorkspace {
        let store = try SwiftDataStore(inMemory: true)
        let workspace = ChatWorkspace(
            persistentStore: store,
            providers: [MockStreamingProvider.instant],
            mode: .onDeviceOnly,
            temporaryChat: false
        )
        await workspace.start()
        return workspace
    }

    func testTheExportedFileIsTheChatItCameFromAndIsCalledWhatTheChatIsCalled() async throws {
        let workspace = try await workspace()
        let session = try XCTUnwrap(workspace.session)
        session.send("What makes a good trail mark?")
        await settle(session)
        workspace.rename(conversationID: session.conversation.id, to: "Trail marks / cairns")

        let data = try XCTUnwrap(workspace.exportFileData(conversationID: session.conversation.id))
        let chat = try XCTUnwrap(workspace.chats().first { $0.id == session.conversation.id })
        let name = ChatFileNames.name(for: chat, markdown: false)
        XCTAssertEqual(name, "Trail-marks-cairns.cairn", "a slash becomes a dash rather than a folder")

        let file = try XCTUnwrap(ExportedChatFile.write(name: name, data: data))
        XCTAssertEqual(try Data(contentsOf: file.url), data, "the file on disk is the export, byte for byte")
        XCTAssertEqual(try ChatExport.decode(data).nodes.count, 2, "ask and answer, both kept")
        XCTAssertEqual(file.url.lastPathComponent, name, "the share sheet carries the name, not a UUID")
    }

    func testTheMarkdownExportIsReadableTextAndTheFileExportIsTheTree() async throws {
        let workspace = try await workspace()
        let session = try XCTUnwrap(workspace.session)
        session.send("Give me a list")
        await settle(session)

        let markdown = try XCTUnwrap(workspace.transcriptMarkdown(conversationID: session.conversation.id))
        XCTAssertTrue(markdown.contains("Give me a list"), "a readable file starts with what was asked")
        XCTAssertTrue(markdown.hasPrefix("#"), "and it is titled, so a folder of them can be told apart")
    }

    /// Highlighting is paint, not editing. The copy button hands back the block's own lines, and a
    /// highlighter that dropped or reordered a character would mean the screen and the clipboard disagree
    /// about code the user never touched — so the rebuilt line must equal the line that went in.
    func testHighlightingLeavesEveryCharacterWhereItWas() {
        let line = "let feet: Int = 12 // one arm"
        var state = CodeHighlighter.ScanState()
        let spans = CodeHighlighter.spans(in: line, language: .swift, state: &state)
        XCTAssertTrue(spans.contains { $0.kind == .keyword }, "the keyword really is found")
        XCTAssertEqual(
            spans.cairnHighlighted(in: .trailheadDark).characters.map(String.init).joined(),
            line,
            "colour added nothing, removed nothing, moved nothing"
        )
    }

    /// Copying the prose of an answer must not hand back markup, and must not lose text either. That is a
    /// claim about the renderer's own file, so it is checked here rather than only in the domain suite.
    ///
    /// This is as much of the copy claim as can be proved without a phone. `Pasteboard.copy` is one line that
    /// hands a string to `UIPasteboard.general`, and asking that pasteboard for text from a test process with
    /// no running app is what held up two simulator lanes; the write-and-read-back round-trip is line 6 of the
    /// device checklist, where there is a foreground app and a real pasteboard to ask.
    func testCopyingProseGivesWhatWasReadRatherThanWhatWasMarkedUp() {
        let answer = "## Cairns\n\nA **cairn** is a stack of stones. Use `stones`.\n"
        let blocks = MarkdownParser.blocks(from: answer)
        let prose = blocks.isEmpty ? answer : blocks.plainText
        XCTAssertFalse(prose.contains("## "), "a heading marker is punctuation the model typed, not prose")
        XCTAssertFalse(prose.contains("**"), "so is a bold marker")
        XCTAssertFalse(prose.contains("`"), "and so is an inline-code marker")
        XCTAssertTrue(prose.contains("cairn"), "and the words the user read are still there")
    }
}
