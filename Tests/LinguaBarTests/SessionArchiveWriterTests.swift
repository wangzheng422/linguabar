import Foundation
import XCTest
@testable import LinguaBar

final class SessionArchiveWriterTests: XCTestCase {
    private let startedAt = Date(timeIntervalSince1970: 1_759_089_600)

    func testSummarySlugRemovesUnsafeUnicodeSeparatorsAndControlCharacters() {
        let slug = SessionArchiveWriter.summarySlug(fromEnglish: "Café / Q4 — Launch\u{0007}")

        XCTAssertEqual(slug, "cafe-q4-launch")
        XCTAssertLessThanOrEqual(slug.count, 60)
        XCTAssertTrue(slug.unicodeScalars.allSatisfy {
            ($0.value >= 97 && $0.value <= 122) || ($0.value >= 48 && $0.value <= 57) || $0.value == 45
        })
    }

    func testSlugFallsBackAndStaysWithinSixtyASCIICharacters() {
        XCTAssertEqual(SessionArchiveWriter.summarySlug(fromEnglish: "The and of to"), "meeting-notes")

        let slug = SessionArchiveWriter.summarySlug(fromEnglish: String(repeating: "extraordinary", count: 12))
        XCTAssertEqual(slug.count, 60)
        XCTAssertTrue(slug.unicodeScalars.allSatisfy { $0.isASCII })
    }

    func testSaveOriginalUsesPrivateFoldersAndPreservesEntireUTF8Transcript() throws {
        let (writer, root) = makeWriter()
        defer { removeTestRoot(root) }
        let transcript = String(repeating: "会议讨论了下一季度的计划。", count: 25_000)

        let destination = try writer.saveOriginal(
            transcript,
            startedAt: startedAt,
            englishSummary: "The Q4 roadmap launch",
            language: .english
        )

        XCTAssertEqual(destination.originalURL.deletingLastPathComponent().lastPathComponent, "Original")
        XCTAssertEqual(destination.chineseURL?.deletingLastPathComponent().lastPathComponent, "Chinese")
        XCTAssertTrue(destination.originalURL.lastPathComponent.hasSuffix("-(q4-roadmap-launch).txt"))
        XCTAssertEqual(try String(contentsOf: destination.originalURL, encoding: .utf8), transcript + "\n")
        XCTAssertEqual(try permissions(at: destination.originalURL), 0o600)
        XCTAssertEqual(try permissions(at: destination.originalURL.deletingLastPathComponent()), 0o700)
        XCTAssertEqual(try permissions(at: root), 0o700)
    }

    func testMinuteCollisionsAddSuffixInsideParentheses() throws {
        let (writer, root) = makeWriter()
        defer { removeTestRoot(root) }

        let first = try writer.saveOriginal("first", startedAt: startedAt, englishSummary: "Project plan", language: .english)
        let second = try writer.saveOriginal("second", startedAt: startedAt, englishSummary: "Project plan", language: .english)

        XCTAssertTrue(first.originalURL.lastPathComponent.hasSuffix("-(project-plan).txt"))
        XCTAssertTrue(second.originalURL.lastPathComponent.hasSuffix("-(project-plan-2).txt"))
        XCTAssertEqual(second.chineseURL?.lastPathComponent, second.originalURL.lastPathComponent)
        XCTAssertEqual(try String(contentsOf: first.originalURL, encoding: .utf8), "first\n")
        XCTAssertEqual(try String(contentsOf: second.originalURL, encoding: .utf8), "second\n")
    }

    func testExistingChineseNameBlocksOriginalNameReservation() throws {
        let (writer, root) = makeWriter()
        defer { removeTestRoot(root) }
        let chineseDirectory = root.appendingPathComponent("Chinese", isDirectory: true)
        try FileManager.default.createDirectory(at: chineseDirectory, withIntermediateDirectories: true)
        let blockedName = "\(datePrefix())-(project-plan).txt"
        let blockedURL = chineseDirectory.appendingPathComponent(blockedName)
        try Data("keep me".utf8).write(to: blockedURL)

        let destination = try writer.saveOriginal(
            "new session",
            startedAt: startedAt,
            englishSummary: "Project plan",
            language: .english
        )

        XCTAssertTrue(destination.originalURL.lastPathComponent.hasSuffix("-(project-plan-2).txt"))
        XCTAssertEqual(try String(contentsOf: blockedURL, encoding: .utf8), "keep me")
    }

    func testIndependentWriterInstancesReserveUniqueNamesConcurrently() throws {
        let (_, root) = makeWriter()
        defer { removeTestRoot(root) }
        let resultLock = NSLock()
        var savedURLs: [URL] = []
        var failures: [Error] = []

        DispatchQueue.concurrentPerform(iterations: 16) { _ in
            let writer = SessionArchiveWriter(rootDirectory: root, timeZone: utcTimeZone())
            do {
                let destination = try writer.saveOriginal(
                    "parallel session",
                    startedAt: startedAt,
                    englishSummary: "Parallel planning",
                    language: .korean
                )
                resultLock.lock()
                savedURLs.append(destination.originalURL)
                resultLock.unlock()
            } catch {
                resultLock.lock()
                failures.append(error)
                resultLock.unlock()
            }
        }

        XCTAssertTrue(failures.isEmpty, "Unexpected save failure: \(failures)")
        XCTAssertEqual(Set(savedURLs).count, 16)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Original").path).count, 16)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Chinese").path).count, 0)
    }

    func testChineseOriginalHasNoChineseCompanion() throws {
        let (writer, root) = makeWriter()
        defer { removeTestRoot(root) }

        let destination = try writer.saveOriginal(
            "中文原文",
            startedAt: startedAt,
            englishSummary: "Meeting notes",
            language: .chinese
        )

        XCTAssertNil(destination.chineseURL)
        XCTAssertThrowsError(try writer.saveChinese("翻译", to: destination))
        XCTAssertEqual(try String(contentsOf: destination.originalURL, encoding: .utf8), "中文原文\n")
    }

    func testChineseWriteFailureDoesNotAlterOriginalOrExistingTranslation() throws {
        let (writer, root) = makeWriter()
        defer { removeTestRoot(root) }
        let destination = try writer.saveOriginal(
            "original transcript",
            startedAt: startedAt,
            englishSummary: "Meeting notes",
            language: .english
        )
        let chineseURL = try XCTUnwrap(destination.chineseURL)
        try FileManager.default.createDirectory(at: chineseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("existing translation\n".utf8).write(to: chineseURL)

        XCTAssertThrowsError(try writer.saveChinese("replacement translation", to: destination))
        XCTAssertEqual(try String(contentsOf: destination.originalURL, encoding: .utf8), "original transcript\n")
        XCTAssertEqual(try String(contentsOf: chineseURL, encoding: .utf8), "existing translation\n")
    }

    func testSummaryUpdateRenamesOriginalAndReturnsMatchingChineseURL() throws {
        let (writer, root) = makeWriter()
        defer { removeTestRoot(root) }
        let initial = try writer.saveOriginal(
            "complete transcript",
            startedAt: startedAt,
            englishSummary: "the and of",
            language: .korean
        )

        let updated = try writer.updateSummary(
            for: initial,
            startedAt: startedAt,
            englishSummary: "Quarterly roadmap decisions"
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: initial.originalURL.path))
        XCTAssertTrue(updated.originalURL.lastPathComponent.hasSuffix("-(quarterly-roadmap-decisions).txt"))
        XCTAssertEqual(updated.chineseURL?.lastPathComponent, updated.originalURL.lastPathComponent)
        XCTAssertEqual(try String(contentsOf: updated.originalURL, encoding: .utf8), "complete transcript\n")
    }

    func testSummaryUpdateSkipsExistingChineseNameAndKeepsItUntouched() throws {
        let (writer, root) = makeWriter()
        defer { removeTestRoot(root) }
        let initial = try writer.saveOriginal(
            "transcript",
            startedAt: startedAt,
            englishSummary: "meeting notes",
            language: .english
        )
        let chineseDirectory = root.appendingPathComponent("Chinese", isDirectory: true)
        try FileManager.default.createDirectory(at: chineseDirectory, withIntermediateDirectories: true)
        let blockedURL = chineseDirectory.appendingPathComponent("\(datePrefix())-(quarterly-roadmap).txt")
        try Data("unrelated translation".utf8).write(to: blockedURL)

        let updated = try writer.updateSummary(
            for: initial,
            startedAt: startedAt,
            englishSummary: "Quarterly roadmap"
        )

        XCTAssertTrue(updated.originalURL.lastPathComponent.hasSuffix("-(quarterly-roadmap-2).txt"))
        XCTAssertEqual(try String(contentsOf: blockedURL, encoding: .utf8), "unrelated translation")
        XCTAssertEqual(try String(contentsOf: updated.originalURL, encoding: .utf8), "transcript\n")
    }

    func testSummaryUpdateIsUnchangedForSameNameAndRefusesAfterChineseSave() throws {
        let (writer, root) = makeWriter()
        defer { removeTestRoot(root) }
        let initial = try writer.saveOriginal(
            "transcript",
            startedAt: startedAt,
            englishSummary: "Roadmap decisions",
            language: .english
        )
        let unchanged = try writer.updateSummary(
            for: initial,
            startedAt: startedAt,
            englishSummary: "Roadmap decisions"
        )
        XCTAssertEqual(unchanged.originalURL, initial.originalURL)

        try writer.saveChinese("翻译", to: unchanged)
        XCTAssertThrowsError(try writer.updateSummary(
            for: unchanged,
            startedAt: startedAt,
            englishSummary: "Renamed session"
        ))
        XCTAssertEqual(try String(contentsOf: initial.originalURL, encoding: .utf8), "transcript\n")
        XCTAssertEqual(try String(contentsOf: try XCTUnwrap(initial.chineseURL), encoding: .utf8), "翻译\n")
    }

    private func makeWriter() -> (SessionArchiveWriter, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LinguaBarSessionArchiveTests-\(UUID().uuidString)", isDirectory: true)
        return (SessionArchiveWriter(rootDirectory: root, timeZone: utcTimeZone()), root)
    }

    private func datePrefix() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = utcTimeZone()
        formatter.dateFormat = "yyyy-MM-dd-HH-mm"
        return formatter.string(from: startedAt)
    }

    private func utcTimeZone() -> TimeZone {
        TimeZone(secondsFromGMT: 0)!
    }

    private func permissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }

    private func removeTestRoot(_ root: URL) {
        try? FileManager.default.removeItem(at: root)
    }
}
