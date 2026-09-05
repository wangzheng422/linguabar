// AI-Author: Codex (OpenAI gpt-5.6-sol)
import XCTest
@testable import LinguaBar

final class LivePunctuationFormatterTests: XCTestCase {
    func testAddsCommaAtNaturalPauseInLiveEnglish() {
        XCTAssertEqual(
            format(
                "hello world again",
                ranges: [(5, 0.0, 0.3), (11, 0.4, 0.3), (17, 1.3, 0.3)]
            ),
            "hello world, again"
        )
    }

    func testAddsPeriodAtLongPauseInLiveEnglish() {
        XCTAssertEqual(
            format(
                "first thought next thought",
                ranges: [(5, 0.0, 0.3), (13, 0.4, 0.3), (18, 1.8, 0.3), (26, 2.2, 0.3)]
            ),
            "first thought. next thought"
        )
    }

    func testPreservesExistingPunctuation() {
        XCTAssertEqual(
            format(
                "hello, world",
                ranges: [(5, 0.0, 0.3), (12, 1.1, 0.3)]
            ),
            "hello, world"
        )
    }

    func testUsesFullWidthPunctuationForChinese() {
        XCTAssertEqual(
            format(
                "你好世界",
                ranges: [(2, 0.0, 0.3), (4, 0.9, 0.3)],
                localeIdentifier: "zh-CN"
            ),
            "你好，世界"
        )
    }

    func testKoreanUsesHalfWidthPunctuation() {
        XCTAssertEqual(
            format(
                "안녕 세계",
                ranges: [(2, 0.0, 0.3), (5, 0.9, 0.3)],
                localeIdentifier: "ko-KR"
            ),
            "안녕, 세계"
        )
    }

    func testSegmentOffsetsRemainAlignedWhenTextHasLeadingWhitespace() {
        XCTAssertEqual(
            format(
                " hello world",
                ranges: [(6, 0.0, 0.3), (12, 0.9, 0.3)]
            ),
            "hello, world"
        )
    }

    func testFinalResultGetsTerminalPunctuation() {
        XCTAssertEqual(
            format(
                "the sentence is complete",
                ranges: [(3, 0.0, 0.2), (12, 0.3, 0.2), (15, 0.6, 0.2), (24, 0.9, 0.2)],
                isFinal: true
            ),
            "the sentence is complete."
        )
    }

    private func format(
        _ text: String,
        ranges: [(end: Int, timestamp: TimeInterval, duration: TimeInterval)],
        localeIdentifier: String = "en-US",
        isFinal: Bool = false
    ) -> String {
        LivePunctuationFormatter.format(
            text,
            segments: ranges.map {
                TimedSpeechSegment(
                    utf16EndOffset: $0.end,
                    timestamp: $0.timestamp,
                    duration: $0.duration
                )
            },
            localeIdentifier: localeIdentifier,
            isFinal: isFinal
        )
    }
}
