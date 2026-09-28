// AI-Author: Codex (OpenAI model not exposed by runtime)
import XCTest
@testable import LinguaBar

@MainActor
final class TranscriptRetentionTests: XCTestCase {
    private var instant = Date(timeIntervalSince1970: 10_000)
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        suite = "LinguaBarRetentionTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    private func makeStore(automatic: Bool = false) -> SubtitleStore {
        SubtitleStore(defaults: defaults, sourceProvider: { [.system] },
                      now: { [unowned self] in self.instant }, automaticallyPrune: automatic)
    }

    private func hear(_ text: String, in store: SubtitleStore, final: Bool = true) {
        store.acceptTranscript(text, isFinal: final, epoch: store.recognitionEpoch)
    }

    private func translated(_ text: String, in store: SubtitleStore) async throws {
        for _ in 0..<100 where store.translationInput.isEmpty {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertFalse(store.translationInput.isEmpty)
        store.acceptTranslation(text, for: store.translationInput, revision: store.translationRevision)
    }

    func testClearRemovesBothPanesAndRejectsOldRecognitionWithoutChangingSettings() async throws {
        let store = makeStore()
        store.maximumTranscriptLines = 200
        hear("Old words.", in: store)
        try await translated("旧文字。", in: store)
        let epoch = store.recognitionEpoch
        let status = store.status
        store.clearTranscript()
        XCTAssertEqual(store.englishText, "")
        XCTAssertEqual(store.chineseText, "")
        XCTAssertEqual(store.translationInput, "")
        XCTAssertEqual(store.status, status)
        XCTAssertEqual(store.maximumTranscriptLines, 200)
        store.acceptTranscript("Old words return.", isFinal: true, epoch: epoch)
        XCTAssertEqual(store.englishText, "")
        hear("New words.", in: store)
        XCTAssertEqual(store.englishText, "New words.")
    }

    func testClearRejectsOldTranslationEvenWhenIdenticalWordsAreSpokenAgain() async throws {
        let store = makeStore()
        hear("Hello.", in: store)
        try await translated("你好。", in: store)
        let oldSource = store.translationInput
        let oldRevision = store.translationRevision
        store.clearTranscript()
        hear("Hello.", in: store)
        try await translated("新你好。", in: store)
        store.acceptTranslation("旧翻译回填", for: oldSource, revision: oldRevision)
        XCTAssertEqual(store.chineseText, "新你好。")
    }

    func testClearCancelsPendingDebounce() async throws {
        let store = makeStore()
        hear("Pending translation.", in: store)
        store.clearTranscript()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(store.translationInput, "")
        XCTAssertEqual(store.englishText, "")
    }

    func testTenMinuteBoundaryRemovesOldSourceAndItsTranslationButKeepsNewSource() async throws {
        let store = makeStore()
        hear("Old sentence.", in: store)
        instant.addTimeInterval(300)
        hear("Recent sentence.", in: store)
        try await translated("旧句子。新句子。", in: store)
        let source = store.translationInput
        let revision = store.translationRevision
        instant.addTimeInterval(299)
        store.removeExpiredTranscripts()
        XCTAssertTrue(store.englishText.contains("Old sentence."))
        instant.addTimeInterval(1)
        store.removeExpiredTranscripts()
        XCTAssertEqual(store.englishText, "Recent sentence.")
        XCTAssertEqual(store.chineseText, "")
        store.acceptTranslation("旧句子。新句子。", for: source, revision: revision)
        XCTAssertEqual(store.chineseText, "")
        try await translated("新句子。", in: store)
        instant.addTimeInterval(300)
        store.removeExpiredTranscripts()
        XCTAssertEqual(store.englishText, "")
        XCTAssertEqual(store.chineseText, "")
    }

    func testPartialFinalizationDoesNotRefreshOriginalTimestamp() {
        let store = makeStore()
        store.sourceLanguage = .chinese
        hear("最早的文字", in: store, final: false)
        instant.addTimeInterval(40)
        hear("最早的文字，继续更新。", in: store)
        instant.addTimeInterval(560)
        store.removeExpiredTranscripts()
        XCTAssertEqual(store.englishText, "")
    }

    func testExpiredPartialCannotBeReintroducedBySameRecognitionEpoch() {
        let store = makeStore()
        hear("Old partial", in: store, final: false)
        let epoch = store.recognitionEpoch
        instant.addTimeInterval(600)
        store.removeExpiredTranscripts()
        store.acceptTranscript("Old partial updated", isFinal: true, epoch: epoch)
        XCTAssertEqual(store.englishText, "")
        hear("Fresh.", in: store)
        XCTAssertEqual(store.englishText, "Fresh.")
    }

    func testLineLimitDoesNotRenewAgeOrResurrectDiscardedLines() {
        let store = makeStore()
        store.sourceLanguage = .chinese
        store.maximumTranscriptLines = 25
        for number in 0..<30 { hear("旧内容\(number)。", in: store) }
        XCTAssertEqual(store.englishText.components(separatedBy: .newlines).count, 25)
        instant.addTimeInterval(599)
        store.maximumTranscriptLines = 100
        XCTAssertEqual(store.englishText.components(separatedBy: .newlines).count, 25)
        instant.addTimeInterval(1)
        store.removeExpiredTranscripts()
        XCTAssertEqual(store.englishText, "")
    }

    func testTimerPrunesWithoutAnyNewSpeech() async throws {
        let store = makeStore(automatic: true)
        hear("A silent meeting.", in: store)
        instant.addTimeInterval(601)
        for _ in 0..<40 where !store.englishText.isEmpty {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertEqual(store.englishText, "")
    }
}
