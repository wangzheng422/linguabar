import Foundation

struct SessionArchiveDestination: Sendable {
    let originalURL: URL
    let chineseURL: URL?
}

struct SessionArchiveWriter: Sendable {
    let rootDirectory: URL
    private let timeZone: TimeZone

    init(
        rootDirectory: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LinguaBar", isDirectory: true),
        timeZone: TimeZone = .current
    ) {
        self.rootDirectory = rootDirectory
        self.timeZone = timeZone
    }

    func saveOriginal(
        _ text: String,
        startedAt: Date,
        englishSummary: String,
        language: SourceLanguage
    ) throws -> SessionArchiveDestination {
        let originalDirectory = rootDirectory.appendingPathComponent("Original", isDirectory: true)
        try ensureDirectory(originalDirectory)
        let chineseDirectory = language.needsChineseTranslation
            ? rootDirectory.appendingPathComponent("Chinese", isDirectory: true)
            : nil
        if let chineseDirectory {
            try ensureDirectory(chineseDirectory)
        }

        let baseSlug = Self.summarySlug(fromEnglish: englishSummary)
        let formatter = Self.makeDateFormatter(timeZone: timeZone)

        for ordinal in 1...10_000 {
            let slug = Self.collisionSlug(baseSlug, ordinal: ordinal)
            let filename = "\(formatter.string(from: startedAt))-(\(slug)).txt"
            let originalURL = originalDirectory.appendingPathComponent(filename)
            let chineseURL = chineseDirectory?.appendingPathComponent(filename)

            guard !fileExists(at: originalURL), chineseURL.map({ !fileExists(at: $0) }) ?? true else {
                continue
            }

            do {
                try writeExclusive(Self.archiveData(for: text), to: originalURL)
                return SessionArchiveDestination(originalURL: originalURL, chineseURL: chineseURL)
            } catch {
                // A concurrent writer may have claimed this minute/summary after the preflight.
                guard fileExists(at: originalURL) || chineseURL.map({ fileExists(at: $0) }) == true else {
                    throw error
                }
            }
        }

        throw SessionArchiveWriterError.tooManyNameCollisions
    }

    func saveChinese(_ text: String, to destination: SessionArchiveDestination) throws {
        guard let chineseURL = destination.chineseURL else {
            throw SessionArchiveWriterError.chineseTranslationNotExpected
        }

        try ensureDirectory(chineseURL.deletingLastPathComponent())
        try writeExclusive(Self.archiveData(for: text), to: chineseURL)
    }

    /// Renames an original transcript before its Chinese translation has been saved.
    /// The destination is returned because a name collision can add a numeric suffix.
    func updateSummary(
        for destination: SessionArchiveDestination,
        startedAt: Date,
        englishSummary: String
    ) throws -> SessionArchiveDestination {
        guard fileExists(at: destination.originalURL) else {
            throw SessionArchiveWriterError.originalTranscriptMissing
        }
        if let chineseURL = destination.chineseURL, fileExists(at: chineseURL) {
            throw SessionArchiveWriterError.chineseTranslationAlreadySaved
        }

        let originalDirectory = destination.originalURL.deletingLastPathComponent()
        let baseSlug = Self.summarySlug(fromEnglish: englishSummary)
        let formatter = Self.makeDateFormatter(timeZone: timeZone)

        for ordinal in 1...10_000 {
            let slug = Self.collisionSlug(baseSlug, ordinal: ordinal)
            let filename = "\(formatter.string(from: startedAt))-(\(slug)).txt"
            let targetOriginalURL = originalDirectory.appendingPathComponent(filename)
            let targetChineseURL = destination.chineseURL.map {
                $0.deletingLastPathComponent().appendingPathComponent(filename)
            }

            if targetOriginalURL.standardizedFileURL == destination.originalURL.standardizedFileURL {
                return destination
            }
            guard !fileExists(at: targetOriginalURL),
                  targetChineseURL.map({ !fileExists(at: $0) }) ?? true else {
                continue
            }

            do {
                // Publish the new name exclusively before dropping our previous name.
                // A hard-link cannot replace a concurrently created destination.
                try FileManager.default.linkItem(at: destination.originalURL, to: targetOriginalURL)
            } catch {
                guard fileExists(at: targetOriginalURL) || targetChineseURL.map({ fileExists(at: $0) }) == true else {
                    throw error
                }
                continue
            }
            do {
                try FileManager.default.removeItem(at: destination.originalURL)
            } catch {
                try? FileManager.default.removeItem(at: targetOriginalURL)
                throw error
            }
            return SessionArchiveDestination(originalURL: targetOriginalURL, chineseURL: targetChineseURL)
        }

        throw SessionArchiveWriterError.tooManyNameCollisions
    }

    static func summarySlug(fromEnglish summary: String) -> String {
        let folded = summary
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        let stopWords: Set<String> = [
            "a", "about", "an", "and", "are", "as", "at", "be", "been", "being", "but", "by",
            "can", "could", "did", "do", "does", "for", "from", "had", "has", "have", "how",
            "i", "in", "into", "is", "it", "its", "may", "might", "of", "on", "or", "our",
            "shall", "should", "so", "that", "the", "their", "them", "there", "these", "they",
            "this", "those", "to", "us", "was", "we", "were", "what", "when", "where", "which",
            "who", "will", "with", "would", "you", "your", "s", "t", "re", "ve", "ll", "d", "m",
            "hello", "hi", "okay", "ok", "welcome", "today", "going", "yeah", "yes", "no", "thanks",
            "thank", "everyone", "everybody", "joining", "join", "meeting", "notes", "um", "uh", "hmm",
            "well", "like", "actually", "basically", "anyway", "right", "sure", "let", "know", "just",
            "really", "talk", "talking", "discuss", "discussing", "want", "wanted"
        ]

        var words: [String] = []
        var current = String.UnicodeScalarView()
        func flushCurrent() {
            guard !current.isEmpty else { return }
            let word = String(current)
            if !stopWords.contains(word) { words.append(word) }
            current = String.UnicodeScalarView()
        }

        for scalar in folded.unicodeScalars {
            let value = scalar.value
            if (value >= 97 && value <= 122) || (value >= 48 && value <= 57) {
                current.append(scalar)
            } else {
                flushCurrent()
            }
        }
        flushCurrent()

        guard !words.isEmpty else { return "meeting-notes" }

        var selected: [String] = []
        var length = 0
        for word in words {
            let separatorLength = selected.isEmpty ? 0 : 1
            let available = 60 - length - separatorLength
            guard available > 0 else { break }
            let piece = word.count <= available ? word : String(word.prefix(available))
            guard !piece.isEmpty else { break }
            selected.append(piece)
            length += separatorLength + piece.count
            if selected.count == 8 || piece.count < word.count { break }
        }

        return selected.isEmpty ? "meeting-notes" : selected.joined(separator: "-")
    }

    private static func archiveData(for text: String) -> Data {
        Data((text + "\n").utf8)
    }

    private static func makeDateFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd-HH-mm"
        return formatter
    }

    private static func collisionSlug(_ slug: String, ordinal: Int) -> String {
        guard ordinal > 1 else { return slug }
        let suffix = "-\(ordinal)"
        let prefix = String(slug.prefix(max(1, 60 - suffix.count)))
        return prefix + suffix
    }

    private func ensureDirectory(_ url: URL) throws {
        do {
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: 0o700)]
            )
        } catch {
            guard isDirectory(at: url) else { throw error }
        }
    }

    private func isDirectory(at url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let type = attributes[.type] as? FileAttributeType else {
            return false
        }
        return type == .typeDirectory
    }

    private func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private func writeExclusive(_ data: Data, to url: URL) throws {
        let manager = FileManager.default
        var temporaryURL: URL?

        for _ in 0..<10 {
            let candidate = url.deletingLastPathComponent()
                .appendingPathComponent(".linguabar-\(UUID().uuidString).tmp")
            if manager.createFile(
                atPath: candidate.path,
                contents: Data(),
                attributes: [.posixPermissions: NSNumber(value: 0o600)]
            ) {
                temporaryURL = candidate
                break
            }
            if !manager.fileExists(atPath: candidate.path) {
                throw SessionArchiveWriterError.unableToReserveTemporaryFile
            }
        }

        guard let temporaryURL else { throw SessionArchiveWriterError.unableToReserveTemporaryFile }
        defer { try? manager.removeItem(at: temporaryURL) }

        // Write a private temporary file, then hard-link it to the final name. Linking is an
        // atomic, exclusive creation: readers see the complete bytes and an existing session
        // can never be replaced by a racing writer.
        try data.write(to: temporaryURL, options: .atomic)
        try manager.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: temporaryURL.path)
        try manager.linkItem(at: temporaryURL, to: url)
    }
}

enum SessionArchiveWriterError: Error {
    case chineseTranslationNotExpected
    case chineseTranslationAlreadySaved
    case originalTranscriptMissing
    case tooManyNameCollisions
    case unableToReserveTemporaryFile
}
