import XCTest
@testable import CairnChatDomain

/// P2's reference layer: the rungs, ranges and reference values the configuration sheet is drawn from.
///
/// These are worth pinning because the sheet renders a control at a reference value while asserting
/// nothing, and the payload builder omits what is unset. If the reference and the ladder disagree, the
/// sheet shows a position that means something other than what the request will do — the exact class of
/// lie this milestone exists to remove.
final class SamplingReferenceTests: XCTestCase {

    // MARK: - The context ladder

    func testContextLadderSpansTwoKToTwoFiftySixK() {
        XCTAssertEqual(SamplingReference.contextWindowLadder.first, 2048)
        XCTAssertEqual(SamplingReference.contextWindowLadder.last, 262_144)
        XCTAssertEqual(SamplingReference.contextWindowLadder.count, 8)
        XCTAssertTrue(
            SamplingReference.contextWindowLadder.allSatisfy { $0 >= 2048 && $0 <= 262_144 },
            "no rung outside the range the slider can show"
        )
    }

    /// The default has to be a rung, or a chat that never touched the control would render between two
    /// rungs and the slider would have no position to sit at.
    func testContextDefaultIsARung() {
        XCTAssertTrue(
            SamplingReference.contextWindowLadder.contains(SamplingReference.contextWindow),
            "the reference must be selectable, not merely close"
        )
        XCTAssertEqual(SamplingReference.contextWindow, 8192)
    }

    func testSnapFindsTheNearestRung() {
        XCTAssertEqual(SamplingReference.snapContextWindow(8000), 8192)
        XCTAssertEqual(SamplingReference.snapContextWindow(12_000), 8192)
        XCTAssertEqual(SamplingReference.snapContextWindow(13_000), 16_384)
        // Off the ends clamp to the nearest rung rather than inventing one.
        XCTAssertEqual(SamplingReference.snapContextWindow(100), 2048)
        XCTAssertEqual(SamplingReference.snapContextWindow(400_000), 262_144)
    }

    func testRungIndexIsAlwaysInRange() {
        XCTAssertEqual(
            SamplingReference.rungIndex(8192, of: SamplingReference.contextWindowLadder), 2
        )
        XCTAssertEqual(
            SamplingReference.rungIndex(9000, of: SamplingReference.contextWindowLadder), 2,
            "an off-ladder value indexes to its snapped rung, so a slider cannot land between two"
        )
        for ladder in [
            SamplingReference.contextWindowLadder, SamplingReference.maxTokensLadder,
            SamplingReference.repeatLastNLadder
        ] {
            for value in [-5, 0, 777, 999_999] {
                let index = SamplingReference.rungIndex(value, of: ladder)
                XCTAssertTrue((0..<ladder.count).contains(index), "index out of ladder for \(value)")
            }
        }
    }

    func testContextLabels() {
        XCTAssertEqual(SamplingReference.contextLabel(2048), "2K")
        XCTAssertEqual(SamplingReference.contextLabel(262_144), "256K")
        XCTAssertEqual(SamplingReference.contextLabel(512), "512")
        XCTAssertEqual(SamplingReference.contextLabel(1536), "1.5K")
    }

    // MARK: - Every reference sits inside its own control

    /// A reference outside its range would draw a control pinned off the end of itself.
    func testReferenceValuesLieInsideTheirRanges() {
        XCTAssertTrue(SamplingReference.temperatureRange.contains(SamplingReference.temperature))
        XCTAssertTrue(SamplingReference.topPRange.contains(SamplingReference.topP))
        XCTAssertTrue(SamplingReference.minPRange.contains(SamplingReference.minP))
        XCTAssertTrue(SamplingReference.repeatPenaltyRange.contains(SamplingReference.repeatPenalty))
        XCTAssertTrue(SamplingReference.topKRange.contains(SamplingReference.topK))
    }

    func testPublishedReferencePointsMatchTheBrief() {
        XCTAssertEqual(SamplingReference.temperature, 0.80)
        XCTAssertEqual(SamplingReference.topP, 0.90)
        XCTAssertEqual(SamplingReference.minP, 0.00)
        XCTAssertEqual(SamplingReference.topK, 40)
        XCTAssertEqual(SamplingReference.repeatPenalty, 1.10)
        XCTAssertEqual(SamplingReference.repeatLastN, 64)
    }

    func testAdvancedLaddersAreAscendingAndHoldTheirReference() {
        func isAscending(_ ladder: [Int]) -> Bool {
            zip(ladder, ladder.dropFirst()).allSatisfy { $0 < $1 }
        }
        XCTAssertTrue(isAscending(SamplingReference.maxTokensLadder))
        XCTAssertTrue(isAscending(SamplingReference.repeatLastNLadder))
        XCTAssertTrue(SamplingReference.repeatLastNLadder.contains(SamplingReference.repeatLastN))
        // Repeat Last N 0 means "look at everything", which has to be reachable.
        XCTAssertEqual(SamplingReference.repeatLastNLadder.first, 0)
    }

    // MARK: - Configured versus unset

    func testEveryKnobCountsOnceAndNoneCountWhenUnset() {
        XCTAssertEqual(SamplingConfig.unset.configuredOptionCount, 0)
        XCTAssertFalse(SamplingConfig.unset.hasOverrides)

        var config = SamplingConfig(
            temperature: 0.4, topP: 0.7, minP: 0.1, topK: 20, maxTokens: 1024,
            repeatPenalty: 1.2, repeatLastN: 32, seed: .fixed(7), contextWindow: 16_384
        )
        XCTAssertEqual(config.configuredOptionCount, SamplingKey.allCases.count)

        for key in SamplingKey.allCases {
            key.clear(in: &config)
            XCTAssertFalse(config.isConfigured(key), "\(key) still reads as configured")
        }
        XCTAssertEqual(config.configuredOptionCount, 0)
    }

    /// Clearing one knob must not disturb its neighbours — the badge the sheet shows is only
    /// trustworthy if it moves by exactly one.
    func testClearingOneKnobMovesTheCountByOne() {
        var config = SamplingConfig(temperature: 0.5, topP: 0.5, seed: .random(from: 3))
        let before = config.configuredOptionCount
        config.clear(.topP)
        XCTAssertEqual(config.configuredOptionCount, before - 1)
        XCTAssertEqual(config.temperature, 0.5)
        XCTAssertEqual(config.seed, .random(from: 3))
    }

    func testResetToDefaultsIsAWholesaleCopyNotABlend() {
        var chat = ChatConfig(sampling: SamplingConfig(temperature: 1.7, topK: 300))
        chat.reset(to: .default)
        XCTAssertEqual(chat.sampling, .unset, "a knob the baseline leaves unset must not survive")
        XCTAssertEqual(chat.configuredOptionCount, 0)
    }

    // MARK: - Seed ownership

    func testRandomizeKeepsOwnershipAndChangesTheNumber() {
        let owned = SeedSetting.random(from: 11)
        XCTAssertEqual(owned.replacingSeed(with: 42), SeedSetting.random(from: 42))
        XCTAssertEqual(owned.replacingSeed(with: 42).mode, .random)
        XCTAssertEqual(SeedSetting.fixed(9).mode, .fixed)
    }

    func testSeedModeNotesTellApartWhoOwnsTheNumber() {
        XCTAssertNotEqual(SeedSetting.Mode.random.note, SeedSetting.Mode.fixed.note)
        XCTAssertTrue(SeedSetting.Mode.fixed.note.contains("You typed"))
    }

    // MARK: - Unsupported knobs are named, not silenced

    func testOpenAIStyleServerDropsTheKeysItCannotRead() {
        let support = ServerProfileKind.openAICompatible.samplingSupport
        var config = SamplingConfig(temperature: 0.5, minP: 0.2, topK: 40, repeatPenalty: 1.3)
        XCTAssertEqual(
            support.droppedKeys(from: config),
            [.minP, .topK, .repeatPenalty],
            "the sheet must warn about exactly the keys the encoder will strip"
        )
        config.clear(.minP)
        config.clear(.topK)
        config.clear(.repeatPenalty)
        XCTAssertEqual(support.droppedKeys(from: config), [])
    }

    func testOllamaReadsEveryKnob() {
        let config = SamplingConfig(
            temperature: 0.4, topP: 0.7, minP: 0.1, topK: 20, maxTokens: 1024,
            repeatPenalty: 1.2, repeatLastN: 32, seed: .fixed(7), contextWindow: 16_384
        )
        XCTAssertEqual(ServerProfileKind.ollama.samplingSupport.droppedKeys(from: config), [])
    }
}
