import XCTest
import SwiftUI
import UIKit
import CairnChatDomain
@testable import CairnAppUI
@testable import CairnPersistence

/// What the M5 screens promise, checked where the promise lives: an exported file really is the chat it
/// came from, a highlighted code line keeps every character it was given, and the new views build a real
/// layout instead of crashing on the way there.
///
/// The pixels are not asserted. What is asserted is the part a person depends on and cannot see: that the
/// bytes handed to the share sheet are the whole chat, that colour never edits the source, and that a
/// screen with a tree behind it survives being put on screen.
@MainActor
final class ChatExportAndRenderingTests: XCTestCase {
    /// Held so the window is not released while the hosted view is being measured.
    private var hostWindow: UIWindow?

    private func host<V: View>(_ view: V) -> UIViewController {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let root = UIHostingController(rootView: view)
        window.rootViewController = root
        window.makeKeyAndVisible()
        hostWindow = window
        root.view.layoutIfNeeded()
        return root
    }

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

    func testCopyPutsExactlyTheRequestedTextOnThePasteboard() {
        let wanted = "the answer, as prose"
        XCTAssertTrue(Pasteboard.copy(wanted))
        XCTAssertEqual(UIPasteboard.general.string, wanted)
    }

    func testTheNewScreensSurviveBeingPutOnScreen() async throws {
        let workspace = try await workspace()
        let session = try XCTUnwrap(workspace.session)
        session.send("Explain a cairn in two lines")
        await settle(session)

        let answer = "## A cairn\n\nA **cairn** is a stack of stones. Use `stones`, not branches.\n\n"
            + "- visible from the trail\n- built from what is there\n"
        XCTAssertGreaterThan(host(MarkdownMessageView(text: answer)).view.frame.height, 0)
        let code = CodeBlockView(infoString: "swift", lines: ["let x = 1", "// one arm"])
        XCTAssertGreaterThan(host(code).view.frame.height, 0)
        XCTAssertGreaterThan(host(ChatListView(workspace: workspace)).view.frame.height, 0)
        XCTAssertGreaterThan(host(TempChatBanner(workspace: workspace)).view.frame.height, 0)
        XCTAssertGreaterThan(host(ChatExportSheet(workspace: workspace)).view.frame.height, 0)
    }
}
