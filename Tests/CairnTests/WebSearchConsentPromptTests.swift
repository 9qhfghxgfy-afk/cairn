import XCTest
import CairnChatDomain
import CairnAppUI

/// The words in front of the consent sheet, checked as values.
///
/// The sheet is the disclosure. Two failures are cheap and permanent: a line vague enough to be agreed to
/// without being understood ("something may be sent"), and two different questions reading the same, which
/// teaches a person that a grant given to a search provider also covers reading pages anywhere. Both are
/// checkable without a screen, and both are checked here rather than in prose.
@MainActor
final class WebSearchConsentPromptTests: XCTestCase {

    private func searchPrompt(_ profile: WebSearchProviderProfile = .builtIn)
        -> WebSearchConsentModel.Prompt {
        WebSearchConsentModel.Prompt(subject: .provider(profile))
    }

    private func readPrompt(host: String, secure: Bool) -> WebSearchConsentModel.Prompt {
        WebSearchConsentModel.Prompt(subject: .page(host: host, secure: secure))
    }

    /// The built-in row is a third party and the sheet names it, because "a search may be sent away" is not a
    /// fact anyone can act on. Only the words typed leave — the line says so, which is the promise the
    /// transport keeps and this copy must not overstate.
    func testTheSearchLineNamesTheProviderAndOnlyTheUsersWords() {
        let prompt = searchPrompt()
        XCTAssertEqual(prompt.subjectName, "DuckDuckGo")
        XCTAssertTrue(prompt.leavingLine.contains("Your search text"))
        XCTAssertTrue(prompt.leavingLine.contains("DuckDuckGo"))
        XCTAssertFalse(prompt.leavingLine.contains("transcript"))
        XCTAssertTrue(prompt.isSearch)
        XCTAssertNotNil(prompt.profile, "a search has a row to attribute the trip to")
    }

    func testANamedInstanceIsShownByTheNameTheUserGaveIt() {
        let nas = WebSearchProviderProfile(
            kind: .searxng, displayName: "Nas", baseURLString: "https://search.example.com"
        )
        XCTAssertEqual(searchPrompt(nas).subjectName, "Nas")
    }

    func testTheReadLineNamesTheHostAndNotThePath() {
        let prompt = readPrompt(host: "example.com", secure: true)
        XCTAssertEqual(prompt.subjectName, "example.com")
        XCTAssertTrue(prompt.leavingLine.contains("example.com"))
        XCTAssertTrue(prompt.leavingLine.contains("https"))
        XCTAssertFalse(prompt.isSearch, "a page read has no provider behind it")
        XCTAssertNil(prompt.profile)
    }

    /// The honest half of the plaintext rule: a sheet that promised https about a plain-http read would be
    /// lying in exactly the place a person is deciding whether to trust it. Private hosts are where a plain
    /// read legitimately happens, so the line has to be able to say so.
    func testAPlainReadSaysSoRatherThanClaimingEncryption() {
        let plain = readPrompt(host: "192.168.1.20", secure: false)
        XCTAssertTrue(plain.plaintextRead)
        XCTAssertTrue(plain.leavingLine.lowercased().contains("plain http"))

        let secure = readPrompt(host: "example.com", secure: true)
        XCTAssertFalse(secure.plaintextRead)
        XCTAssertFalse(secure.leavingLine.lowercased().contains("plain http"))
    }

    /// Two questions, two shapes. If they read alike, a grant given for search reads as permission to read
    /// pages anywhere — the drift the split records exist to prevent.
    func testTheTwoQuestionsDoNotReadAlike() {
        let search = searchPrompt()
        let read = readPrompt(host: "example.com", secure: true)
        XCTAssertNotEqual(search.leavingLine, read.leavingLine)
        XCTAssertNotEqual(search.isSearch, read.isSearch)
        XCTAssertFalse(read.leavingLine.contains("search text"))
    }
}
