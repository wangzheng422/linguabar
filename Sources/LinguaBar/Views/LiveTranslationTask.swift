import SwiftUI
import Translation

struct LiveTranslationTask: View {
    let store: SubtitleStore
    let language: SourceLanguage

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .translationTask(source: Locale.Language(identifier: language.translationLanguageIdentifier!),
                             target: Locale.Language(identifier: "zh-Hans")) { [weak store, language] session in
                guard let events = store?.translationChannel(for: language).connect() else { return }
                for await _ in events {
                    guard !Task.isCancelled else { return }
                    guard let request = store?.translationChannel(for: language).takeLatest(),
                          store?.isCurrentTranslation(request, language: language) == true else { continue }
                    do {
                        // Let the request finish naturally. New speech replaces only
                        // the pending item, never the TranslationSession configuration.
                        let response = try await session.translate(request.text)
                        guard !Task.isCancelled else {
                            if store?.isCurrentTranslation(request, language: language) == true {
                                store?.translationChannel(for: language).restoreIfEmpty(request)
                            }
                            return
                        }
                        store?.acceptTranslation(response.targetText, for: request.text, revision: request.revision)
                    } catch {
                        if Task.isCancelled {
                            if store?.isCurrentTranslation(request, language: language) == true {
                                store?.translationChannel(for: language).restoreIfEmpty(request)
                            }
                            return
                        }
                        store?.reportTranslationError(error, for: request, language: language)
                    }
                }
            }
    }
}
