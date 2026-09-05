// AI-Author: Codex (OpenAI gpt-5.6-sol)
import Foundation

struct TimedSpeechSegment: Equatable, Sendable {
    let utf16EndOffset: Int
    let timestamp: TimeInterval
    let duration: TimeInterval
}

enum LivePunctuationFormatter {
    private static let clausePause: TimeInterval = 0.45
    private static let sentencePause: TimeInterval = 0.90
    private static let punctuationCharacters = CharacterSet.punctuationCharacters
        .union(CharacterSet(charactersIn: "，。！？；：、…"))
    private static let punctuationCharacterSet = punctuationCharacters as NSCharacterSet
    private static let whitespaceCharacterSet = CharacterSet.whitespacesAndNewlines as NSCharacterSet

    static func format(
        _ text: String,
        segments: [TimedSpeechSegment],
        localeIdentifier: String,
        isFinal: Bool
    ) -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }

        let source = text as NSString
        var insertions: [(offset: Int, punctuation: String)] = []

        for index in segments.indices.dropLast() {
            let current = segments[index]
            let next = segments[index + 1]
            let pause = next.timestamp - (current.timestamp + current.duration)
            guard pause >= clausePause else { continue }

            let offset = min(max(0, current.utf16EndOffset), source.length)
            guard offset > 0,
                  !hasPunctuation(around: offset, in: source) else { continue }

            insertions.append((
                offset,
                punctuation(
                    for: pause,
                    localeIdentifier: localeIdentifier
                )
            ))
        }

        let punctuated = NSMutableString(string: text)
        for insertion in insertions.sorted(by: { $0.offset > $1.offset }) {
            punctuated.insert(insertion.punctuation, at: insertion.offset)
        }

        let result = (punctuated as String)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard isFinal, !endsWithPunctuation(result) else { return result }
        return result + sentenceMark(localeIdentifier: localeIdentifier)
    }

    private static func punctuation(
        for pause: TimeInterval,
        localeIdentifier: String
    ) -> String {
        let usesFullWidthPunctuation = localeIdentifier
            .lowercased()
            .hasPrefix("zh")
        if pause >= sentencePause {
            return usesFullWidthPunctuation ? "。" : "."
        }
        return usesFullWidthPunctuation ? "，" : ","
    }

    private static func sentenceMark(localeIdentifier: String) -> String {
        localeIdentifier.lowercased().hasPrefix("zh") ? "。" : "."
    }

    private static func hasPunctuation(around offset: Int, in text: NSString) -> Bool {
        if punctuationCharacterSet.characterIsMember(text.character(at: offset - 1)) {
            return true
        }

        var cursor = offset
        while cursor < text.length {
            let character = text.character(at: cursor)
            if !whitespaceCharacterSet.characterIsMember(character) {
                return punctuationCharacterSet.characterIsMember(character)
            }
            cursor += 1
        }
        return false
    }

    private static func endsWithPunctuation(_ text: String) -> Bool {
        guard let scalar = text.unicodeScalars.last else { return false }
        return punctuationCharacters.contains(scalar)
    }
}
