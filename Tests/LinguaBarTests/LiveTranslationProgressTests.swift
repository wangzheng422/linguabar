import XCTest
@testable import LinguaBar

final class LiveTranslationProgressTests: XCTestCase {
    func testReusesUnchangedLinesAndRendersInSourceOrder() {
        var progress = LiveTranslationProgress()
        progress.update("one\ntwo\nthree\nfour\nfive\nfive")
        XCTAssertEqual(progress.nextBatch, ["two", "three", "four", "five"])
        progress.record(progress.nextBatch, translations: ["二", "三", "四", "五"])
        XCTAssertEqual(progress.nextBatch, ["one"])
        XCTAssertEqual(progress.visibleTranslation, "二\n三\n四\n五\n五")
        progress.update("three\nfour\nfive updated")
        XCTAssertEqual(progress.nextBatch, ["five updated"])
        progress.record(progress.nextBatch, translations: ["新五"])
        XCTAssertEqual(progress.visibleTranslation, "三\n四\n新五")
        XCTAssertTrue(progress.nextBatch.isEmpty)
        progress.update("two")
        XCTAssertEqual(progress.nextBatch, ["two"])
    }

    func testMonotonicSpacingAndBoundedBackoffResetAfterSuccess() {
        var pacing = LiveTranslationPacing()
        let now = ContinuousClock().now
        pacing.started(at: now)
        XCTAssertEqual(pacing.nextRequest, now + .seconds(3))
        for delay in [15, 30, 60, 60] {
            XCTAssertEqual(pacing.backOff(at: now), delay)
            XCTAssertEqual(pacing.nextRequest, now + .seconds(delay))
        }
        pacing.succeeded()
        XCTAssertEqual(pacing.backOff(at: now), 15)
    }
}
