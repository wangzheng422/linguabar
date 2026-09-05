// AI-Author: Codex (OpenAI gpt-5.6-sol)
import XCTest
@testable import LinguaBar

final class TranscriptFormatterTests: XCTestCase {
    func testAddsNewlineBetweenRecognizedSentences() {
        XCTAssertEqual(
            TranscriptFormatter.paragraphized("First sentence. Second sentence? Third sentence!"),
            "First sentence.\nSecond sentence?\nThird sentence!"
        )
    }

    func testLeavesLongUnpunctuatedChineseForResponsiveViewWrapping() {
        let input = String(repeating: "实时字幕", count: 12)
        let output = TranscriptFormatter.paragraphized(input)

        XCTAssertEqual(output, input)
    }

    func testLeavesLongEnglishForResponsiveViewWrapping() {
        let input = Array(repeating: "recognition", count: 12).joined(separator: " ")
        let output = TranscriptFormatter.paragraphized(input)

        XCTAssertEqual(output, input)
    }

    func testFinalizedSpeechTaskAndCurrentPartialUseSeparateLines() {
        XCTAssertEqual(
            TranscriptFormatter.displayText(
                finalized: ["The first recognition task finished."],
                current: "The next task is still listening"
            ),
            "The first recognition task finished.\nThe next task is still listening"
        )
    }

    func testRetainsOnlyTheNewestConfiguredLines() {
        let input = (1...105).map { "line \($0)" }.joined(separator: "\n")
        let output = TranscriptFormatter.retainingLastLines(input, maximum: 100)
        let lines = output.components(separatedBy: "\n")

        XCTAssertEqual(lines.count, 100)
        XCTAssertEqual(lines.first, "line 6")
        XCTAssertEqual(lines.last, "line 105")
    }
}
