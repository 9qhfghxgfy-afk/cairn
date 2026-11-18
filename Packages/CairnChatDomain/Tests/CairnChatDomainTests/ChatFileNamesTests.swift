import XCTest
@testable import CairnChatDomain

/// A title turned into something a filesystem will accept.
///
/// A chat's title is often the model's first line, so it can hold a slash, a newline or a paragraph. The
/// name written on the way out has to be one segment, not a path, and has to say nothing about the device
/// or the person using it.
final class ChatFileNamesTests: XCTestCase {

    func testSeparatorsBecomeOneDashRatherThanAPartOfAPath() {
        XCTAssertEqual(ChatFileNames.safeSegment("Router/Firmware: keys"), "Router-Firmware-keys")
        XCTAssertEqual(ChatFileNames.safeSegment("a\\b"), "a-b")
        XCTAssertEqual(ChatFileNames.safeSegment("WireGuard\nfirmware"), "WireGuard-firmware")
        XCTAssertEqual(ChatFileNames.safeSegment("  hello   world  "), "hello-world")
    }

    func testADotThatWouldHideOrBreakTheFileIsNotLeftOnEitherEnd() {
        XCTAssertEqual(ChatFileNames.safeSegment(".hidden"), "hidden")
        XCTAssertEqual(ChatFileNames.safeSegment("trailing..."), "trailing")
        XCTAssertEqual(ChatFileNames.safeSegment("---"), ChatFileNames.fallback)
    }

    func testATitleWithNothingUsableInItStillGetsAName() {
        XCTAssertEqual(ChatFileNames.safeSegment(""), ChatFileNames.fallback)
        XCTAssertEqual(ChatFileNames.safeSegment("🐐🪨"), ChatFileNames.fallback)
    }

    func testAParagraphTitleIsCutAtAWordRatherThanMidCodepoint() {
        let long = String(repeating: "cairn ", count: 40)
        let stem = ChatFileNames.safeSegment(long)
        XCTAssertLessThanOrEqual(stem.count, 60)
        XCTAssertFalse(stem.hasSuffix("-"))
        XCTAssertTrue(stem.hasPrefix("cairn-cairn"))
    }

    func testTheExportNameCarriesTheChatsTitleAndTheRightSuffix() {
        let chat = Conversation(title: "Router keys")
        XCTAssertEqual(ChatFileNames.name(for: chat, markdown: true), "Router-keys.md")
        XCTAssertEqual(ChatFileNames.name(for: chat, markdown: false), "Router-keys.cairn")
    }

    func testAnUntitledChatIsNamedAsTheListShowsItPlusTheDateSoTwoDoNotCollide() {
        let name = ChatFileNames.name(
            for: Conversation(title: "   "), markdown: true, now: Date(timeIntervalSince1970: 1_800_000_000)
        )
        XCTAssertTrue(name.hasPrefix("Untitled-chat-"), "the export says what the list says")
        XCTAssertTrue(name.hasSuffix(".md"))
        XCTAssertTrue(name.contains("2027-01-15"), "the day it was made is in the name")
        XCTAssertFalse(name.contains(":"), "a colon is a path separator somewhere; a file name never has one")

        // The claim is "two do not collide", so the test says it: the same untitled chat exported an hour
        // later must be a different file, or the second export quietly replaces the first.
        let later = ChatFileNames.name(
            for: Conversation(title: "   "), markdown: true, now: Date(timeIntervalSince1970: 1_800_003_600)
        )
        XCTAssertNotEqual(name, later, "two untitled exports from the same day are two files")
    }

    func testTheAllChatsNameIsDateStampedAndSaysNothingAboutTheDevice() {
        let name = ChatFileNames.name(for: nil, markdown: false, now: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(name, "cairn-chats-2027-01-15T08-00-00Z.cairn")
        XCTAssertFalse(name.contains(":"))
    }
}
