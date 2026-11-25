import Foundation

/// Keeps only translations relevant to the current rolling subtitle snapshot.
struct LiveTranslationProgress {
    private var translated: [String: String] = [:]
    private var lines: [String] = []

    mutating func update(_ text: String) {
        lines = text.split(separator: "\n").map(String.init)
        let visible = Set(lines)
        translated = translated.filter { visible.contains($0.key) }
    }

    var nextBatch: [String] {
        var selected: Set<String> = []
        var batch: [String] = []
        for line in lines.reversed() where translated[line] == nil && selected.insert(line).inserted {
            batch.append(line)
            if batch.count == 4 { break }
        }
        return batch.reversed()
    }

    mutating func record(_ batch: [String], translations: [String]) {
        for (source, target) in zip(batch, translations) {
            translated[source] = target
        }
    }

    var visibleTranslation: String {
        lines.compactMap { translated[$0] }.joined(separator: "\n")
    }
}

/// Shared by live workers so starting a new listening session cannot reset backoff.
struct LiveTranslationPacing {
    private(set) var nextRequest: ContinuousClock.Instant?
    private var retryDelay = 15

    mutating func started(at now: ContinuousClock.Instant) {
        nextRequest = now + .seconds(3)
    }

    mutating func succeeded() {
        retryDelay = 15
    }

    mutating func backOff(at now: ContinuousClock.Instant) -> Int {
        let delay = retryDelay
        nextRequest = now + .seconds(delay)
        retryDelay = min(delay * 2, 60)
        return delay
    }
}
