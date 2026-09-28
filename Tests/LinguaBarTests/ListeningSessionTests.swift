import XCTest
@testable import LinguaBar

final class ListeningSessionTests: XCTestCase {
    private let startedAt = Date(timeIntervalSince1970: 10_000)

    func testEmptyRecognizerUpdatesCannotEraseLastRecognizedWords() {
        let session = ListeningSession(startedAt: startedAt, language: .english)
        session.record("Still keep these words", isFinal: false)
        session.record("", isFinal: false)
        session.record("\n", isFinal: true)
        session.record("Next task", isFinal: false)
        XCTAssertEqual(session.seal().text, "Still keep these words\n\nNext task")
    }

    func testPartialUpdatesAreReplacedAndFinalIsAppendedOnce() {
        let session = ListeningSession(startedAt: startedAt, language: .english)

        session.record("First draft", isFinal: false)
        session.record("First revised draft.", isFinal: false)
        XCTAssertEqual(session.snapshot().text, "First revised draft.")

        session.record("  First revised draft.  \n", isFinal: true)
        XCTAssertEqual(session.snapshot().text, "First revised draft.")
        XCTAssertFalse(session.isEmpty)
    }

    func testIdenticalFinalTextFromDifferentUtterancesIsKeptTwice() {
        let session = ListeningSession(startedAt: startedAt, language: .korean)

        session.record("같은 문장.", isFinal: true)
        session.record("같은 문장.", isFinal: true)

        XCTAssertEqual(session.snapshot().text, "같은 문장.\n\n같은 문장.")
    }

    func testSealKeepsPendingPartialAndIgnoresStaleCallbacks() {
        let session = ListeningSession(startedAt: startedAt, language: .chinese)
        session.record(" 已识别内容 ", isFinal: true)
        session.record("尚未结束的内容", isFinal: false)

        let sealed = session.seal()
        session.record("过期的最终回调", isFinal: true)
        session.record("过期的部分回调", isFinal: false)

        XCTAssertEqual(sealed.text, "已识别内容\n\n尚未结束的内容")
        XCTAssertEqual(session.snapshot(), sealed)
        XCTAssertEqual(session.seal(), sealed)
    }

    func testLongSessionTranscriptIsNotTruncated() {
        let session = ListeningSession(startedAt: startedAt, language: .english)
        let twoHourText = String(repeating: "word ", count: 18_000)
        let expected = twoHourText.trimmingCharacters(in: .whitespacesAndNewlines)

        session.record(twoHourText, isFinal: true)

        XCTAssertEqual(session.snapshot().text, expected)
        XCTAssertGreaterThan(session.snapshot().text.count, 80_000)
    }

    func testConcurrentRecordsAndSnapshotsRemainConsistent() {
        let session = ListeningSession(startedAt: startedAt, language: .english)
        let finalCount = 1_000

        DispatchQueue.concurrentPerform(iterations: finalCount) { index in
            session.record("Draft \(index)", isFinal: false)
            _ = session.snapshot()
            session.record("Final \(index).", isFinal: true)
            _ = session.snapshot()
            _ = session.isEmpty
        }

        let snapshot = session.snapshot()
        let recordedFinals = Set(snapshot.text.components(separatedBy: "\n\n"))
        XCTAssertEqual(recordedFinals.count, finalCount)
        for index in 0..<finalCount {
            XCTAssertTrue(recordedFinals.contains("Final \(index)."))
        }
    }
}
