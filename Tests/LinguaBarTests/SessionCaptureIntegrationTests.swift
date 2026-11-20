import XCTest
@testable import LinguaBar

@MainActor
final class SessionCaptureIntegrationTests: XCTestCase {
    func testNextListeningSessionReplacesTranslationWorkerAndRejectsPreviousOutput() async throws {
        let suite = "SessionTranslationTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SubtitleStore(defaults: defaults, sourceProvider: { [.system] }, automaticallyPrune: false)
        store.beginListeningSession()
        let firstWorker = store.liveTranslationSessionID
        store.clearTranscript()
        XCTAssertEqual(store.liveTranslationSessionID, firstWorker)
        let firstRevision = store.translationRevision
        store.stopCapture()
        for _ in 0..<100 where store.status != .idle { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(store.status, .idle)
        store.beginListeningSession()
        XCTAssertNotEqual(store.liveTranslationSessionID, firstWorker)
        let previousText = store.chineseText
        store.acceptTranslation("上一场的译文", for: "Previous session", revision: firstRevision)
        XCTAssertEqual(store.chineseText, previousText)
        store.acceptTranscript("Second session", isFinal: true, epoch: store.recognitionEpoch)
        for _ in 0..<100 where store.translationInput.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        let request = try XCTUnwrap(store.translationChannel(for: .english).takeLatest())
        XCTAssertEqual(request.text, "Second session")
        store.acceptTranslation("第二段", for: request.text, revision: request.revision)
        XCTAssertEqual(store.chineseText, "第二段")
    }

    func testFinalCorrectionArrivingDuringStopIsIncluded() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "SessionStopTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            try? FileManager.default.removeItem(at: folder)
            defaults.removePersistentDomain(forName: suite)
        }
        let archive = SessionArchiveStore(writer: SessionArchiveWriter(rootDirectory: folder))
        let store = SubtitleStore(defaults: defaults, sourceProvider: { [.system] },
                                  automaticallyPrune: false, archive: archive)
        let session = store.beginListeningSession()
        session.record("The budget is", isFinal: false)
        store.stopCapture()
        session.record("The budget is approved.", isFinal: true)
        for _ in 0..<100 where archive.lastOriginalURL == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(try String(contentsOf: XCTUnwrap(archive.lastOriginalURL), encoding: .utf8),
                       "The budget is approved.\n")
        session.record("Late duplicate", isFinal: true)
        XCTAssertEqual(session.snapshot().text, "The budget is approved.")
    }

    func testStopArchivesWholeSessionDespiteClearExpiryAndLineLimit() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "SessionCaptureIntegrationTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            try? FileManager.default.removeItem(at: folder)
            defaults.removePersistentDomain(forName: suite)
        }
        var instant = Date(timeIntervalSince1970: 10_000)
        let archive = SessionArchiveStore(writer: SessionArchiveWriter(rootDirectory: folder))
        let store = SubtitleStore(defaults: defaults, sourceProvider: { [.system] },
                                  now: { instant }, automaticallyPrune: false, archive: archive)
        store.sourceLanguage = .chinese
        store.maximumTranscriptLines = 25
        let session = store.beginListeningSession()
        for index in 0..<150 {
            let text = "第\(index)段重要会议内容。"
            session.record(text, isFinal: true)
            store.acceptTranscript(text, isFinal: true, epoch: store.recognitionEpoch)
        }
        XCTAssertFalse(store.englishText.contains("第0段"))
        instant.addTimeInterval(7200)
        store.removeExpiredTranscripts()
        XCTAssertEqual(store.englishText, "")
        store.clearTranscript()
        session.record("最终一句还没定稿", isFinal: false)
        store.stopCapture()
        XCTAssertEqual(store.status, .finishing)
        store.stopCapture() // repeated stop must not queue a second export
        for _ in 0..<100 where archive.lastOriginalURL == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let file = try XCTUnwrap(archive.lastOriginalURL)
        XCTAssertEqual(store.status, .idle)
        let saved = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(saved.contains("第0段"))
        XCTAssertTrue(saved.contains("第149段"))
        XCTAssertTrue(saved.contains("最终一句还没定稿"))
        XCTAssertEqual(saved, session.snapshot().text + "\n")
        let title = try XCTUnwrap(archive.request)
        archive.fail(title.id, message: "Title unavailable")
        XCTAssertEqual(archive.pendingCount, 0)
        XCTAssertEqual(archive.failureCount, 0)
        store.stopCapture()
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path).count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Chinese").path))
    }
}
