import XCTest
@testable import CairnChatDomain

/// The one line the Servers screen shows for what this phone can run by itself.
///
/// The bug these tests hold shut is the row that said `0 models installed` on a phone holding three
/// downloaded folders. The count was never supplied, so the line reported a number nobody had looked at —
/// and it did so whether or not the MLX runtime had been linked, which made a build problem read as an
/// empty phone. Zero now has its own wording, and a non-zero count rides along even when no engine can run,
/// because "weights are here, the runtime is not" is a different fact from "nothing is installed".
final class OnDeviceEngineReportTests: XCTestCase {

    private let notLinked = "The MLX runtime is not in this build"
    private let noApple = "Apple Intelligence is not available on this device"

    private func report(
        apple: Bool = false,
        mlx: Bool = false,
        models: Int = 0
    ) -> OnDeviceEngineReport {
        OnDeviceEngineReport(
            appleModel: OnDeviceEngineState(name: "Apple model", status: noApple, isUsable: apple),
            mlx: OnDeviceEngineState(name: "MLX", status: notLinked, isUsable: mlx),
            installedModelCount: models
        )
    }

    func testNothingInstalledAndNothingUsableIsTheRuntimesOwnSentence() {
        let line = report().summary
        XCTAssertEqual(line, notLinked, "with nothing on disk there is no count to add to the runtime's words")
        XCTAssertFalse(line.contains("0 models"), "a count nobody read is not a fact about this phone")
    }

    func testModelsAreCountedEvenWhenNoEngineCanRunThem() {
        let line = report(models: 3).summary
        XCTAssertTrue(line.contains("3 models installed"), "got: \(line)")
        XCTAssertTrue(line.contains(notLinked), "got: \(line)")
    }

    func testOneModelIsPhrasedAsOneModel() {
        XCTAssertTrue(report(models: 1).summary.contains("1 model installed"))
    }

    func testAReadyEngineSaysWhichEngineAndWhatItHasToRun() {
        let mlxOnly = report(mlx: true, models: 2).summary
        XCTAssertEqual(mlxOnly, "MLX ready · 2 models installed")

        let both = report(apple: true, mlx: true, models: 1).summary
        XCTAssertEqual(both, "Apple model + MLX ready · 1 model installed")
    }

    func testTheStartingReportClaimsNothing() {
        let line = OnDeviceEngineReport.unavailable
        XCTAssertFalse(line.canRunSomething)
        XCTAssertEqual(line.installedModelCount, 0)
        XCTAssertEqual(line.summary, "Not checked yet", "an unread report never reads as ready")
    }
}
