import Foundation
import XCTest
@testable import LinguaBar

@MainActor
final class SessionArchiveStoreTests: XCTestCase {
    private let startedAt = Date(timeIntervalSince1970: 1_759_089_600)

    func testEnglishSavesFullOriginalBeforeRequestingAllChineseChunks() throws {
        let (store, root) = makeStore()
        defer { removeTestRoot(root) }
        let text = String(repeating: "The full session 🙂 has every detail. ", count: 180)
        let snapshot = makeSnapshot(language: .english, text: text)

        store.enqueue(snapshot)

        let request = try XCTUnwrap(store.request)
        XCTAssertEqual(request.sessionID, snapshot.id)
        XCTAssertEqual(request.purpose, .chinese)
        XCTAssertEqual(request.sourceIdentifier, "en")
        XCTAssertEqual(request.targetIdentifier, "zh-Hans")
        XCTAssertGreaterThan(request.chunks.count, 1)
        XCTAssertEqual(request.chunks.joined(), text)

        let originalURL = try XCTUnwrap(store.lastOriginalURL)
        XCTAssertEqual(try read(originalURL), text + "\n")
        XCTAssertTrue(store.hasUnfinishedExports)
        XCTAssertEqual(store.failureCount, 0)

        let translations = request.chunks.map { "中文：\($0)" }
        store.complete(request.id, translations: translations)

        XCTAssertEqual(try read(chineseURL(for: originalURL, root: root)), translations.joined(separator: "\n\n") + "\n")
        XCTAssertFalse(store.hasUnfinishedExports)
    }

    func testChineseSessionUsesOptionalEnglishTitleAndWritesOnlyOriginal() throws {
        let (store, root) = makeStore()
        defer { removeTestRoot(root) }
        let snapshot = makeSnapshot(language: .chinese, text: "中文完整原文🙂")

        store.enqueue(snapshot)

        let titleRequest = try XCTUnwrap(store.request)
        XCTAssertEqual(titleRequest.purpose, .title)
        XCTAssertEqual(titleRequest.sourceIdentifier, "zh-Hans")
        XCTAssertEqual(titleRequest.targetIdentifier, "en")
        XCTAssertEqual(titleRequest.chunks, [snapshot.text])
        let initiallySaved = try XCTUnwrap(store.lastOriginalURL)
        XCTAssertEqual(try read(initiallySaved), snapshot.text + "\n")

        store.complete(titleRequest.id, translations: ["Quarterly planning"])

        let finalURL = try XCTUnwrap(store.lastOriginalURL)
        XCTAssertNotEqual(finalURL, initiallySaved)
        XCTAssertTrue(finalURL.lastPathComponent.hasSuffix("-(quarterly-planning).txt"))
        XCTAssertEqual(try read(finalURL), snapshot.text + "\n")
        XCTAssertNil(store.request)
        XCTAssertFalse(store.hasUnfinishedExports)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Chinese").path))
    }

    func testChineseSessionStillFinishesWhenOptionalTitleFails() throws {
        let (store, root) = makeStore()
        defer { removeTestRoot(root) }
        let snapshot = makeSnapshot(language: .chinese, text: "仅保存这份中文原文")

        store.enqueue(snapshot)
        let titleRequest = try XCTUnwrap(store.request)
        let originalURL = try XCTUnwrap(store.lastOriginalURL)

        store.fail(titleRequest.id, message: "English language pack unavailable")

        XCTAssertNil(store.request)
        XCTAssertFalse(store.hasUnfinishedExports)
        XCTAssertEqual(store.failureCount, 0)
        XCTAssertEqual(store.lastOriginalURL, originalURL)
        XCTAssertEqual(try read(originalURL), snapshot.text + "\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Chinese").path))
    }

    func testKoreanSessionRenamesOriginalThenSavesChineseTranslation() throws {
        let (store, root) = makeStore()
        defer { removeTestRoot(root) }
        let snapshot = makeSnapshot(language: .korean, text: "전체 한국어 원문🙂\n다음 줄")

        store.enqueue(snapshot)

        let titleRequest = try XCTUnwrap(store.request)
        XCTAssertEqual(titleRequest.purpose, .title)
        XCTAssertEqual(titleRequest.sourceIdentifier, "ko")
        XCTAssertEqual(titleRequest.targetIdentifier, "en")
        let originalBeforeRename = try XCTUnwrap(store.lastOriginalURL)

        store.complete(titleRequest.id, translations: ["Planning discussion"])

        let chineseRequest = try XCTUnwrap(store.request)
        XCTAssertEqual(chineseRequest.purpose, .chinese)
        XCTAssertEqual(chineseRequest.sourceIdentifier, "ko")
        XCTAssertEqual(chineseRequest.targetIdentifier, "zh-Hans")
        XCTAssertEqual(chineseRequest.chunks.joined(), snapshot.text)
        let renamedOriginal = try XCTUnwrap(store.lastOriginalURL)
        XCTAssertNotEqual(renamedOriginal, originalBeforeRename)
        XCTAssertTrue(renamedOriginal.lastPathComponent.hasSuffix("-(planning-discussion).txt"))
        XCTAssertEqual(try read(renamedOriginal), snapshot.text + "\n")

        let translations = chineseRequest.chunks.map { "中文：\($0)" }
        store.complete(chineseRequest.id, translations: translations)

        let chineseURL = renamedOriginal.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Chinese", isDirectory: true)
            .appendingPathComponent(renamedOriginal.lastPathComponent)
        XCTAssertEqual(try read(chineseURL), translations.joined(separator: "\n\n") + "\n")
        XCTAssertNil(store.request)
        XCTAssertFalse(store.hasUnfinishedExports)
    }

    func testFailedChineseTranslationKeepsOriginalAndRetryReusesItsFile() throws {
        let (store, root) = makeStore()
        defer { removeTestRoot(root) }
        let snapshot = makeSnapshot(language: .english, text: "Original session text stays intact.")
        store.enqueue(snapshot)
        let firstRequest = try XCTUnwrap(store.request)
        let originalURL = try XCTUnwrap(store.lastOriginalURL)

        store.fail(firstRequest.id, message: "translation failed")

        XCTAssertEqual(store.failureCount, 1)
        XCTAssertEqual(store.pendingCount, 0)
        XCTAssertEqual(try read(originalURL), snapshot.text + "\n")
        XCTAssertEqual(originalFiles(in: root).count, 1)

        store.retryFailures()

        let retryRequest = try XCTUnwrap(store.request)
        XCTAssertEqual(retryRequest.sessionID, snapshot.id)
        XCTAssertNotEqual(retryRequest.id, firstRequest.id)
        XCTAssertEqual(store.lastOriginalURL, originalURL)
        XCTAssertEqual(try read(originalURL), snapshot.text + "\n")
        XCTAssertEqual(originalFiles(in: root).count, 1)

        store.complete(retryRequest.id, translations: ["翻译完成"])
        XCTAssertEqual(store.failureCount, 0)
        XCTAssertFalse(store.hasUnfinishedExports)
    }

    func testInvalidOriginalRootCanBeRepairedAndRetrySavesWholeSnapshot() throws {
        let root = testRoot()
        try Data("blocks directory creation".utf8).write(to: root)
        let store = makeStore(root: root).0
        let text = String(repeating: "完整原文🙂\n", count: 1200)
        let snapshot = makeSnapshot(language: .english, text: text)
        defer { removeTestRoot(root) }

        store.enqueue(snapshot)

        XCTAssertEqual(store.failureCount, 1)
        XCTAssertNil(store.request)
        XCTAssertTrue(store.hasUnfinishedExports)
        XCTAssertNil(store.lastOriginalURL)

        try FileManager.default.removeItem(at: root)
        store.retryFailures()

        let originalURL = try XCTUnwrap(store.lastOriginalURL)
        XCTAssertEqual(try read(originalURL), text + "\n")
        XCTAssertEqual(store.request?.sessionID, snapshot.id)
        XCTAssertEqual(store.failureCount, 0)
        XCTAssertEqual(store.request?.chunks.joined(), text)
    }

    func testTwoQueuedSessionsSerializeRequestsWithoutMixingTheirFiles() throws {
        let (store, root) = makeStore()
        defer { removeTestRoot(root) }
        let first = makeSnapshot(language: .english, text: "First session text", titleSeed: "First session")
        let second = makeSnapshot(language: .english, text: "Second session text", titleSeed: "Second session")

        store.enqueue(first)
        let firstRequest = try XCTUnwrap(store.request)
        let firstURL = try XCTUnwrap(store.lastOriginalURL)
        store.enqueue(second)
        let secondURL = try XCTUnwrap(store.lastOriginalURL)

        XCTAssertEqual(store.request?.id, firstRequest.id)
        XCTAssertEqual(store.request?.sessionID, first.id)
        XCTAssertNotEqual(firstURL, secondURL)
        XCTAssertEqual(try read(firstURL), first.text + "\n")
        XCTAssertEqual(try read(secondURL), second.text + "\n")

        store.complete(firstRequest.id, translations: ["第一场翻译"])

        let secondRequest = try XCTUnwrap(store.request)
        XCTAssertEqual(secondRequest.sessionID, second.id)
        XCTAssertEqual(secondRequest.chunks.joined(), second.text)
        let firstChineseURL = chineseURL(for: firstURL, root: root)
        XCTAssertEqual(try read(firstChineseURL), "第一场翻译\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: chineseURL(for: secondURL, root: root).path))

        store.complete(secondRequest.id, translations: ["第二场翻译"])

        XCTAssertEqual(try read(chineseURL(for: firstURL, root: root)), "第一场翻译\n")
        XCTAssertEqual(try read(chineseURL(for: secondURL, root: root)), "第二场翻译\n")
        XCTAssertFalse(store.hasUnfinishedExports)
    }

    func testStaleTranslationResponseDoesNotChangeCurrentRequest() throws {
        let (store, root) = makeStore()
        defer { removeTestRoot(root) }
        let snapshot = makeSnapshot(language: .english, text: "Current request")
        store.enqueue(snapshot)
        let current = try XCTUnwrap(store.request)

        store.complete(UUID(), translations: ["stale result"])
        store.fail(UUID(), message: "stale failure")

        XCTAssertEqual(store.request?.id, current.id)
        XCTAssertEqual(store.request?.sessionID, snapshot.id)
        XCTAssertEqual(store.failureCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: chineseURL(for: try XCTUnwrap(store.lastOriginalURL), root: root).path))

        store.complete(current.id, translations: ["current result"])
        XCTAssertFalse(store.hasUnfinishedExports)
    }

    func testEmptySnapshotCreatesNoFilesOrRequests() {
        let (store, root) = makeStore()
        defer { removeTestRoot(root) }

        store.enqueue(makeSnapshot(language: .english, text: " \n\t "))

        XCTAssertNil(store.request)
        XCTAssertFalse(store.hasUnfinishedExports)
        XCTAssertEqual(store.failureCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testChunkingPreservesTenThousandUnicodeCharactersAndBoundsChunks() {
        let text = "🙂\n" + String(repeating: "界🙂", count: 4_999) + "\n終わり"

        let chunks = SessionArchiveStore.chunks(text)

        XCTAssertEqual(text.count, 10_004)
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertTrue(chunks.allSatisfy { !$0.isEmpty && $0.count <= 1600 })
        XCTAssertEqual(chunks.joined(), text)
    }

    func testDuplicateSnapshotAndResponseDoNotDuplicateArchive() throws {
        let (store, root) = makeStore()
        defer { removeTestRoot(root) }
        let snapshot = makeSnapshot(language: .english, text: "One session only")
        store.enqueue(snapshot)
        let request = try XCTUnwrap(store.request)
        let originalURL = try XCTUnwrap(store.lastOriginalURL)

        store.enqueue(snapshot)
        XCTAssertEqual(store.request?.id, request.id)
        XCTAssertEqual(originalFiles(in: root).count, 1)

        store.complete(request.id, translations: ["一次翻译"])
        store.complete(request.id, translations: ["duplicate translation"])
        store.enqueue(snapshot)

        XCTAssertNil(store.request)
        XCTAssertFalse(store.hasUnfinishedExports)
        XCTAssertEqual(originalFiles(in: root).count, 1)
        XCTAssertEqual(try read(originalURL), snapshot.text + "\n")
        XCTAssertEqual(try read(chineseURL(for: originalURL, root: root)), "一次翻译\n")
    }

    private func makeStore(root: URL? = nil) -> (SessionArchiveStore, URL) {
        let root = root ?? testRoot()
        let writer = SessionArchiveWriter(rootDirectory: root, timeZone: TimeZone(secondsFromGMT: 0)!)
        return (SessionArchiveStore(writer: writer), root)
    }

    private func makeSnapshot(
        language: SourceLanguage,
        text: String,
        titleSeed: String? = nil
    ) -> ListeningSessionSnapshot {
        ListeningSessionSnapshot(
            id: UUID(),
            startedAt: startedAt.addingTimeInterval(TimeInterval(titleSeed?.count ?? 0)),
            language: language,
            text: text
        )
    }

    private func testRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("LinguaBarSessionArchiveStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func originalFiles(in root: URL) -> [URL] {
        let directory = root.appendingPathComponent("Original", isDirectory: true)
        return (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
    }

    private func chineseURL(for originalURL: URL, root: URL) -> URL {
        root.appendingPathComponent("Chinese", isDirectory: true)
            .appendingPathComponent(originalURL.lastPathComponent)
    }

    private func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    private func removeTestRoot(_ root: URL) {
        try? FileManager.default.removeItem(at: root)
    }
}
