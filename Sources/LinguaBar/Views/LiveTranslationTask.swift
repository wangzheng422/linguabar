import SwiftUI
import Translation

struct LiveTranslationTask: View {
    let store: SubtitleStore
    let language: SourceLanguage

    var body: some View {
        let sessionID = store.liveTranslationSessionID
        return Color.clear.frame(width: 0, height: 0)
            .translationTask(source: Locale.Language(identifier: language.translationLanguageIdentifier!),
                             target: Locale.Language(identifier: "zh-Hans")) { [weak store, language] session in
                guard store?.liveTranslationSessionID == sessionID,
                      let channel = store?.translationChannel(for: language) else { return }
                let clock = ContinuousClock()
                var progress = LiveTranslationProgress()
                let events = channel.connect()
                for await _ in events {
                    // Wait before taking the snapshot so new speech can replace it during cooldown.
                    while let next = store?.liveTranslationPacing.nextRequest, next > clock.now {
                        do { try await clock.sleep(until: next) } catch { return }
                    }
                    guard !Task.isCancelled, store?.liveTranslationSessionID == sessionID else { return }
                    guard let request = channel.takeLatest(),
                          store?.isCurrentTranslation(request, language: language) == true else { continue }
                    progress.update(request.text)
                    let batch = progress.nextBatch
                    do {
                        if !batch.isEmpty {
                            store?.liveTranslationPacing.started(at: clock.now)
                            let replies = try await session.translations(from: batch.map {
                                TranslationSession.Request(sourceText: $0)
                            })
                            try Task.checkCancellation()
                            guard store?.liveTranslationSessionID == sessionID else { return }
                            guard replies.count == batch.count else { throw TranslationError.internalError }
                            store?.liveTranslationPacing.succeeded()
                            guard store?.isCurrentTranslation(request, language: language) == true else { continue }
                            progress.record(batch, translations: replies.map(\.targetText))
                        }
                        guard store?.isCurrentTranslation(request, language: language) == true else { continue }
                        store?.acceptTranslation(progress.visibleTranslation, for: request.text, revision: request.revision)
                        if !progress.nextBatch.isEmpty { channel.restoreIfEmpty(request) }
                    } catch {
                        guard store?.liveTranslationSessionID == sessionID else { return }
                        if Task.isCancelled {
                            if store?.isCurrentTranslation(request, language: language) == true {
                                channel.restoreIfEmpty(request)
                            }
                            return
                        }
                        // Apple wraps rate-limit failures as internalError.
                        let retry = TranslationError.internalError ~= error
                        let retryAfter = retry ? store?.liveTranslationPacing.backOff(at: clock.now) : nil
                        store?.reportTranslationError(error, for: request, language: language,
                                                      retryAfter: retryAfter)
                        if retry, store?.isCurrentTranslation(request, language: language) == true {
                            channel.restoreIfEmpty(request)
                        }
                    }
                }
            }
    }
}
