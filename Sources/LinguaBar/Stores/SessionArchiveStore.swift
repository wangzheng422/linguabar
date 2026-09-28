import Combine
import Foundation

/// Full-session exports are independent of the short, disposable on-screen history.
@MainActor
final class SessionArchiveStore: ObservableObject {
    struct TranslationRequest: Identifiable {
        enum Purpose { case title, chinese }
        let id = UUID()
        let sessionID: UUID
        let language: SourceLanguage
        let purpose: Purpose
        let chunks: [String]

        var targetIdentifier: String { purpose == .title ? "en" : "zh-Hans" }
        var sourceIdentifier: String {
            switch language {
            case .english: return "en"
            case .korean: return "ko"
            case .chinese: return "zh-Hans"
            }
        }
    }

    private struct Job {
        let snapshot: ListeningSessionSnapshot
        var destination: SessionArchiveDestination?
        var titleAttempted = false
        var failed = false
    }

    @Published private(set) var request: TranslationRequest?
    @Published private(set) var message = "停止监听后自动保存完整文本"
    @Published private(set) var failureCount = 0
    @Published private(set) var pendingCount = 0
    @Published private(set) var lastOriginalURL: URL?
    private let writer: SessionArchiveWriter
    private var jobs: [UUID: Job] = [:]
    private var queue: [UUID] = []
    private var acceptedSessions: Set<UUID> = []

    init(writer: SessionArchiveWriter = SessionArchiveWriter()) {
        self.writer = writer
    }

    var directory: URL { writer.rootDirectory }
    var hasUnfinishedExports: Bool { !jobs.isEmpty }

    func enqueue(_ snapshot: ListeningSessionSnapshot) {
        guard !snapshot.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if jobs.isEmpty { message = "本次没有识别到文字，未生成文件" }
            return
        }
        guard acceptedSessions.insert(snapshot.id).inserted else { return }
        jobs[snapshot.id] = Job(snapshot: snapshot)
        // Write original immediately. Translation/model-download failures must never
        // prevent already recognized words from reaching disk.
        if persistOriginal(for: snapshot.id) { queue.append(snapshot.id) }
        updateCounts()
        processNext()
    }

    func retryFailures() {
        let ids = jobs.values.filter(\.failed)
            .sorted { $0.snapshot.startedAt < $1.snapshot.startedAt }.map { $0.snapshot.id }
        for id in ids {
            jobs[id]?.failed = false
            if persistOriginal(for: id) { queue.append(id) }
        }
        updateCounts()
        processNext()
    }

    func complete(_ requestID: UUID, translations: [String]) {
        guard let current = request, current.id == requestID,
              var job = jobs[current.sessionID] else { return }
        guard translations.count == current.chunks.count,
              translations.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            fail(requestID, message: "翻译没有返回全部文本，请重试")
            return
        }
        request = nil
        switch current.purpose {
        case .title:
            job.titleAttempted = true
            if let destination = job.destination {
                // A title is optional; retain the safely saved original if renaming fails.
                if let renamed = try? writer.updateSummary(
                    for: destination, startedAt: job.snapshot.startedAt,
                    englishSummary: translations.joined(separator: " ")) {
                    job.destination = renamed
                    lastOriginalURL = renamed.originalURL
                }
            }
            jobs[current.sessionID] = job
            queue.insert(current.sessionID, at: 0)
        case .chinese:
            do {
                guard let destination = job.destination else { return }
                try writer.saveChinese(translations.joined(separator: "\n\n"), to: destination)
                finish(current.sessionID, originalURL: destination.originalURL, bilingual: true)
            } catch {
                recordFailure(current.sessionID, error.localizedDescription)
            }
        }
        updateCounts()
        processNext()
    }

    func fail(_ requestID: UUID, message error: String) {
        guard let current = request, current.id == requestID else { return }
        request = nil
        if current.purpose == .title {
            // English title generation is best-effort. Never block a Chinese-only
            // transcript or its full Chinese translation on an optional language pack.
            jobs[current.sessionID]?.titleAttempted = true
            queue.insert(current.sessionID, at: 0)
        } else {
            recordFailure(current.sessionID, error)
        }
        updateCounts()
        processNext()
    }

    private func persistOriginal(for id: UUID) -> Bool {
        guard var job = jobs[id] else { return false }
        if job.destination != nil { return true }
        do {
            let destination = try writer.saveOriginal(
                job.snapshot.text, startedAt: job.snapshot.startedAt,
                englishSummary: job.snapshot.language == .english ? job.snapshot.text : "meeting-notes",
                language: job.snapshot.language)
            job.destination = destination
            jobs[id] = job
            lastOriginalURL = destination.originalURL
            return true
        } catch {
            recordFailure(id, error.localizedDescription)
            return false
        }
    }

    private func processNext() {
        guard request == nil else { return }
        while !queue.isEmpty {
            let id = queue.removeFirst()
            guard let job = jobs[id], !job.failed, let destination = job.destination else { continue }
            if job.snapshot.language != .english, !job.titleAttempted {
                message = "原文已保存，正在生成英文文件名…"
                request = TranslationRequest(sessionID: id, language: job.snapshot.language,
                                             purpose: .title, chunks: [String(job.snapshot.text.prefix(600))])
                return
            }
            if job.snapshot.language.needsChineseTranslation {
                message = "原文已保存，正在翻译并保存全文…"
                request = TranslationRequest(sessionID: id, language: job.snapshot.language,
                                             purpose: .chinese, chunks: Self.chunks(job.snapshot.text))
                return
            }
            finish(id, originalURL: destination.originalURL, bilingual: false)
        }
        updateCounts()
    }

    private func finish(_ id: UUID, originalURL: URL, bilingual: Bool) {
        jobs.removeValue(forKey: id)
        lastOriginalURL = originalURL
        message = bilingual ? "已保存完整原文和中文译文" : "已保存完整中文原文"
    }

    private func recordFailure(_ id: UUID, _ reason: String) {
        jobs[id]?.failed = true
        message = jobs[id]?.destination == nil
            ? "保存失败（文字仍在内存，请重试）：\(reason)"
            : "原文已保存，中文译文未完成，请重试：\(reason)"
    }

    private func updateCounts() {
        failureCount = jobs.values.filter(\.failed).count
        pendingCount = jobs.count - failureCount
    }

    /// Bounded requests, with every character retained exactly once. Prefer a
    /// sentence/word boundary near the end, falling back for long unspaced text.
    static func chunks(_ text: String, maximum: Int = 1600) -> [String] {
        precondition(maximum > 0)
        var result: [String] = []
        var remaining = text[...]
        while !remaining.isEmpty {
            let end = remaining.index(remaining.startIndex, offsetBy: maximum, limitedBy: remaining.endIndex)
                ?? remaining.endIndex
            var split = end
            if end != remaining.endIndex {
                let lower = remaining.index(remaining.startIndex, offsetBy: maximum / 2)
                if let boundary = remaining[lower..<end].lastIndex(where: {
                    $0.isWhitespace || "。！？.!?".contains($0)
                }) { split = remaining.index(after: boundary) }
            }
            result.append(String(remaining[..<split]))
            remaining = remaining[split...]
        }
        return result
    }
}
