// AI-Author: Codex (OpenAI gpt-5.6-sol)
import Foundation

enum TranscriptFormatter {
    static func paragraphized(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "" }

        return normalized
            .components(separatedBy: .newlines)
            .flatMap(sentenceLines)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    static func displayText(finalized: [String], current: String) -> String {
        (finalized + [current])
            .map(paragraphized)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    static func retainingLastLines(_ text: String, maximum: Int) -> String {
        guard maximum > 0 else { return "" }
        let lines = text.components(separatedBy: .newlines)
        guard lines.count > maximum else { return text }
        return lines.suffix(maximum).joined(separator: "\n")
    }

    private static func sentenceLines(_ paragraph: String) -> [String] {
        let paragraph = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !paragraph.isEmpty else { return [] }

        var sentences: [String] = []
        paragraph.enumerateSubstrings(
            in: paragraph.startIndex..<paragraph.endIndex,
            options: .bySentences
        ) { substring, _, _, _ in
            guard let sentence = substring?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !sentence.isEmpty else { return }
            sentences.append(sentence)
        }
        return sentences.isEmpty ? [paragraph] : sentences
    }
}
