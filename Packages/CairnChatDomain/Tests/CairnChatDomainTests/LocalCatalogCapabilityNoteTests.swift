import XCTest
@testable import CairnChatDomain

/// What a library entry is allowed to say where its capability badges would go, decided in the row and
/// not in the view.
///
/// The screen used to print one flat line — "No capabilities published for this entry" — over an entry
/// that stated its parameter count, its quantisation and a context ceiling. The line was true and it read
/// as a broken app, because a person cannot tell "the publisher said nothing about capabilities" apart
/// from "this screen failed to load". So the line now names what **is** published, and only an entry that
/// publishes nothing at all says so, in the words that fit the kind of entry it is.
///
/// The rule under the wording is the one that matters: nothing is inferred. A capability Cairn has not
/// been told about is never shown as a badge, because a badge is something a person acts on — they pick a
/// model with tools on it expecting tools — and a guess from a model's name is not a fact.
final class LocalCatalogCapabilityNoteTests: XCTestCase {

    func testAnEntryThatPublishesBadgesNeedsNoNoteAtAll() {
        let row = LocalCatalogRow(
            repoID: "Qwen/Qwen3.5-8B", displayName: "Qwen 3.5 8B",
            parameterSize: "8B", capabilityLabels: ["Tools", "Vision"]
        )
        XCTAssertEqual(row.capabilityNote, "", "badges are drawn; a note beside them is a second claim")
    }

    func testAnEntryWithoutBadgesNamesTheFactsItDoesPublish() {
        let row = LocalCatalogRow(
            repoID: "Qwen/Qwen3.5-8B", displayName: "Qwen 3.5 8B",
            parameterSize: "8B", quantization: "Q4_K_M", contextLength: 32_768
        )
        XCTAssertEqual(
            row.capabilityNote,
            "No capability badges published · 8B · Q4_K_M · 32768 token context",
            "the stated facts are the answer to 'what does this entry tell me'"
        )
    }

    func testAFactThatIsNotACapabilityIsNeverPromotedToABadge() {
        // A context length is not "Long context" and a quantisation is not "fast". The note may name what
        // a publisher stated; only a publisher may name a capability.
        let row = LocalCatalogRow(repoID: "mlx-community/Some-Model", displayName: "Some Model",
                                  contextLength: 131_072)
        XCTAssertEqual(row.capabilityLabels, [])
        XCTAssertTrue(row.capabilityNote.contains("131072 token context"))
        XCTAssertFalse(row.capabilityNote.contains("Long context"))
    }

    func testAnEntryPublishingNothingSaysSoInItsOwnKindOfWords() {
        let repository = LocalCatalogRow(repoID: "mlx-community/Undescribed",
                                         displayName: "Undescribed", origin: .onDevice)
        XCTAssertEqual(repository.capabilityNote,
                       "The repository publishes nothing about this build, so nothing is claimed here.")

        let tag = LocalCatalogRow(repoID: "llama3:latest", displayName: "Llama 3",
                                  origin: .ollamaLibrary)
        XCTAssertEqual(tag.capabilityNote,
                       "The server publishes nothing about this tag, so nothing is claimed here.")

        let typed = LocalCatalogRow(repoID: "my-own-model", displayName: "my-own-model", origin: .custom)
        XCTAssertEqual(typed.capabilityNote,
                       "That name is not in Cairn's library, so nothing is claimed about it here.")
    }

    func testTheNoteNeverClaimsACapabilityThePublisherDidNotPublish() {
        // The one line all four cases share: no note, however it is worded, may contain a capability word
        // that `capabilityLabels` does not carry. That is the whole privacy-adjacent promise of this
        // screen — Cairn states what a publisher stated, and stops.
        let forbidden = ["Tools", "Vision", "Embedding", "Audio", "Reasoning"]
        let rows = [
            LocalCatalogRow(repoID: "a", displayName: "A"),
            LocalCatalogRow(repoID: "b", displayName: "B", quantization: "Q8_0"),
            LocalCatalogRow(repoID: "c", displayName: "C", parameterSize: "4B", contextLength: 8_192),
            LocalCatalogRow(repoID: "d", displayName: "D", origin: .ollamaLibrary),
            LocalCatalogRow(repoID: "e", displayName: "E", origin: .custom),
        ]
        for row in rows {
            for word in forbidden where !row.capabilityLabels.contains(word) {
                XCTAssertFalse(row.capabilityNote.contains(word),
                               "\(row.repoID) states no \(word); the note must not name one")
            }
        }
    }
}
