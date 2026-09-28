import Foundation

struct ListeningSessionSnapshot: Equatable, Sendable {
    let id: UUID
    let startedAt: Date
    let language: SourceLanguage
    let text: String
}

final class ListeningSession: @unchecked Sendable {
    let id = UUID()
    let startedAt: Date
    let language: SourceLanguage

    private let lock = NSLock()
    private var finalizedSegments: [String] = []
    private var currentPartial = ""
    private var isClosed = false

    init(startedAt: Date, language: SourceLanguage) {
        self.startedAt = startedAt
        self.language = language
    }

    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return finalizedSegments.isEmpty && currentPartial.isEmpty
    }

    func record(_ text: String, isFinal: Bool) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        lock.lock()
        defer { lock.unlock() }
        guard !isClosed else { return }

        if isFinal {
            let finalText = trimmedText.isEmpty ? currentPartial : trimmedText
            if !finalText.isEmpty {
                finalizedSegments.append(finalText)
            }
            currentPartial = ""
        } else if !trimmedText.isEmpty {
            currentPartial = trimmedText
        }
    }

    func snapshot() -> ListeningSessionSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return makeSnapshot()
    }

    func seal() -> ListeningSessionSnapshot {
        lock.lock()
        defer { lock.unlock() }
        isClosed = true
        return makeSnapshot()
    }

    private func makeSnapshot() -> ListeningSessionSnapshot {
        var segments = finalizedSegments
        if !currentPartial.isEmpty {
            segments.append(currentPartial)
        }

        return ListeningSessionSnapshot(
            id: id,
            startedAt: startedAt,
            language: language,
            text: segments.joined(separator: "\n\n")
        )
    }
}
