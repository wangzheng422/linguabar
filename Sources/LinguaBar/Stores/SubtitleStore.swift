// AI-Author: Codex (OpenAI gpt-5.6-sol)
// AI-Author: Codex (OpenAI model not exposed by runtime)
import Combine
import Foundation
import Translation

@MainActor
final class SubtitleStore: ObservableObject {
    static let transcriptRetention: TimeInterval = 10 * 60

    private struct TimedTranscript {
        var text: String
        let firstHeardAt: Date
    }
    private enum PreferenceKey {
        static let sourceLanguage = "sourceLanguage"
        static let audioSource = "audioSource"
        static let maximumTranscriptLines = "maximumTranscriptLines"
    }

    @Published private(set) var sources: [AudioSource] = [.system]
    @Published var selectedSourceID: String {
        didSet {
            guard !isApplyingAutomaticSourceSelection,
                  let source = sources.first(where: { $0.id == selectedSourceID }) else { return }
            defaults.set(source.persistenceIdentifier, forKey: PreferenceKey.audioSource)
        }
    }
    @Published private(set) var status: SubtitleStatus = .idle
    @Published private(set) var englishText = "Waiting for meeting audio…"
    @Published private(set) var chineseText = "正在等待会议音频…"
    @Published private(set) var translationError: String?
    @Published private(set) var translationInput = ""
    @Published private(set) var translationRevision = UUID()
    @Published private(set) var liveTranslationSessionID = UUID()
    var liveTranslationPacing = LiveTranslationPacing()
    @Published var alwaysOnTop = true
    @Published var sourceLanguage: SourceLanguage {
        didSet {
            defaults.set(sourceLanguage.rawValue, forKey: PreferenceKey.sourceLanguage)
            translationDebounce?.cancel()
            translationInput = ""
            resetTranscriptHistory()
            englishText = sourceLanguage == .chinese ? "正在等待会议音频…" : "Waiting for meeting audio…"
            chineseText = "正在等待会议音频…"
        }
    }

    @Published var maximumTranscriptLines: Int {
        didSet {
            let clamped = min(500, max(25, maximumTranscriptLines))
            if maximumTranscriptLines != clamped {
                maximumTranscriptLines = clamped
                return
            }
            defaults.set(maximumTranscriptLines, forKey: PreferenceKey.maximumTranscriptLines)
            applyTranscriptLineLimit()
        }
    }

    private let defaults: UserDefaults
    private let sourceProvider: () -> [AudioSource]
    private let now: () -> Date
    private let audioTap = CoreAudioProcessTap()
    private let transcriber = SpeechTranscriber()
    let archive: SessionArchiveStore
    private var listeningSession: ListeningSession?
    private var captureGeneration = UUID()
    private var isFinishingCapture = false
    private var translationDebounce: Task<Void, Never>?
    private let englishTranslation = LiveTranslationChannel()
    private let koreanTranslation = LiveTranslationChannel()
    private var finalizedTranscriptSegments: [TimedTranscript] = []
    private var currentTranscript: TimedTranscript?
    private var expirationTimer: AnyCancellable?
    private(set) var recognitionEpoch: UInt64 = 0
    private var isApplyingAutomaticSourceSelection = false

    init(
        defaults: UserDefaults = .standard,
        sourceProvider: @escaping () -> [AudioSource] = CoreAudioProcessTap.availableSources,
        now: @escaping () -> Date = Date.init,
        automaticallyPrune: Bool = true,
        archive: SessionArchiveStore? = nil
    ) {
        self.defaults = defaults
        self.sourceProvider = sourceProvider
        self.now = now
        self.archive = archive ?? SessionArchiveStore()
        selectedSourceID = AudioSource.system.id
        sourceLanguage = defaults.string(forKey: PreferenceKey.sourceLanguage)
            .flatMap(SourceLanguage.init(rawValue:)) ?? .english
        let storedLineLimit = defaults.integer(forKey: PreferenceKey.maximumTranscriptLines)
        maximumTranscriptLines = storedLineLimit == 0
            ? 100
            : min(500, max(25, storedLineLimit))
        if defaults.object(forKey: PreferenceKey.sourceLanguage) == nil {
            defaults.set(sourceLanguage.rawValue, forKey: PreferenceKey.sourceLanguage)
        }
        if defaults.object(forKey: PreferenceKey.maximumTranscriptLines) == nil {
            defaults.set(maximumTranscriptLines, forKey: PreferenceKey.maximumTranscriptLines)
        }
        refreshSources()
        if automaticallyPrune {
            expirationTimer = Timer.publish(every: 1, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in self?.removeExpiredTranscripts() }
        }
    }

    var selectedSource: AudioSource {
        sources.first(where: { $0.id == selectedSourceID }) ?? .system
    }

    @discardableResult
    func refreshSources() -> [AudioSource] {
        let refreshed = sourceProvider()
        sources = refreshed
        if status.isCapturing, refreshed.contains(where: { $0.id == selectedSourceID }) {
            return refreshed
        }

        let rememberedIdentifier = defaults.string(forKey: PreferenceKey.audioSource)
        let remembered = rememberedIdentifier.flatMap {
            AudioSource.restoredSource(matching: $0, in: refreshed)
        }
        let selected = remembered ?? AudioSource.preferredDefault(in: refreshed)
        applyAutomaticSourceSelection(selected.id)
        if rememberedIdentifier == nil {
            defaults.set(selected.persistenceIdentifier, forKey: PreferenceKey.audioSource)
        }
        return refreshed
    }

    func toggleCapture() async {
        if status.isCapturing {
            stopCapture()
        } else {
            await startCapture()
        }
    }

    func startCapture() async {
        guard !status.isCapturing, status != .requestingPermission else { return }
        let generation = UUID()
        captureGeneration = generation
        status = .requestingPermission
        guard await SpeechTranscriber.requestAuthorization() else {
            status = .failed("请在系统设置中允许 LinguaBar 使用语音识别。")
            return
        }
        guard captureGeneration == generation else { return }

        do {
            let session = beginListeningSession()
            recognitionEpoch = try transcriber.start(
                localeIdentifier: sourceLanguage.speechLocaleIdentifier,
                onResult: { [weak self] text, isFinal, epoch in
                    // This runs on the recognizer's serial queue BEFORE enqueueing UI
                    // work. stop() drains that queue, so the export includes every
                    // delivered result even when its UI update has not run yet.
                    session.record(text, isFinal: isFinal)
                    Task { @MainActor in
                        guard self?.captureGeneration == generation, self?.isFinishingCapture == false else { return }
                        self?.acceptTranscript(text, isFinal: isFinal, epoch: epoch)
                    }
                },
                onError: { [weak self] message in
                    Task { @MainActor in
                        guard self?.captureGeneration == generation, self?.isFinishingCapture == false else { return }
                        self?.status = .warning("语音识别正在重连：\(message)")
                    }
                }
            )
            try audioTap.start(
                source: selectedSource,
                onAudio: { [weak self] buffer in self?.transcriber.append(buffer) },
                onWarning: { [weak self] message in
                    Task { @MainActor in
                        guard self?.captureGeneration == generation, self?.isFinishingCapture == false else { return }
                        self?.status = .warning(message)
                    }
                }
            )
            englishText = sourceLanguage == .chinese
                ? "正在监听 \(selectedSource.label)…"
                : "Listening to \(selectedSource.label)…"
            if sourceLanguage.needsChineseTranslation {
                chineseText = "正在监听 \(selectedSource.label)…"
            }
            status = .listening
        } catch {
            transcriber.stop()
            audioTap.stop()
            captureGeneration = UUID()
            saveListeningSession()
            status = .failed(error.localizedDescription)
        }
    }

    func stopCapture() {
        guard !isFinishingCapture else { return }
        // End queued live retries before starting the full-session archive.
        invalidateTranslation()
        audioTap.stop()
        guard listeningSession != nil else {
            transcriber.stop()
            captureGeneration = UUID()
            status = .idle
            return
        }
        isFinishingCapture = true
        status = .finishing
        Task { [self] in
            await transcriber.finish()
            captureGeneration = UUID()
            saveListeningSession()
            isFinishingCapture = false
            status = .idle
        }
    }

    private func saveListeningSession() {
        guard let session = listeningSession else { return }
        listeningSession = nil
        archive.enqueue(session.seal())
    }

    @discardableResult
    func beginListeningSession() -> ListeningSession {
        resetTranscriptHistory()
        liveTranslationSessionID = UUID()
        let session = ListeningSession(startedAt: now(), language: sourceLanguage)
        listeningSession = session
        return session
    }

    func acceptTranslation(_ translation: String, for source: String, revision: UUID) {
        removeExpiredTranscripts()
        guard revision == translationRevision, !source.isEmpty else { return }
        translationError = nil
        chineseText = TranscriptFormatter.retainingLastLines(
            TranscriptFormatter.paragraphized(translation),
            maximum: maximumTranscriptLines
        )
    }

    func translationChannel(for language: SourceLanguage) -> LiveTranslationChannel {
        precondition(language.needsChineseTranslation)
        return language == .english ? englishTranslation : koreanTranslation
    }

    func isCurrentTranslation(_ request: LiveTranslationChannel.Request, language: SourceLanguage) -> Bool {
        sourceLanguage == language && request.revision == translationRevision
    }

    func reportTranslationError(_ error: Error, for request: LiveTranslationChannel.Request,
                                language: SourceLanguage, retryAfter: Int? = nil) {
        guard isCurrentTranslation(request, language: language) else { return }
        translationError = retryAfter.map { "翻译暂缓，\($0) 秒后自动重试" }
            ?? "翻译暂不可用：\(error.localizedDescription)"
    }

    func acceptTranscript(_ text: String, isFinal: Bool, epoch: UInt64) {
        guard epoch == recognitionEpoch else { return }
        removeExpiredTranscripts()
        guard epoch == recognitionEpoch else { return }
        let transcript = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return }

        if isFinal {
            finalizedTranscriptSegments.append(TimedTranscript(
                text: transcript,
                firstHeardAt: currentTranscript?.firstHeardAt ?? now()
            ))
            trimFinalizedTranscriptHistory()
            currentTranscript = nil
        } else {
            currentTranscript = TimedTranscript(
                text: TranscriptFormatter.retainingLastLines(
                    TranscriptFormatter.paragraphized(transcript), maximum: maximumTranscriptLines
                ),
                firstHeardAt: currentTranscript?.firstHeardAt ?? now()
            )
        }

        let displayText = currentLimitedDisplayText()
        englishText = displayText
        if case .warning = status { status = .listening }
        let delay: UInt64 = isFinal ? 50_000_000 : 380_000_000
        scheduleTranslation(delay: delay)
    }

    private func scheduleTranslation(delay: UInt64) {
        guard sourceLanguage.needsChineseTranslation, !englishText.isEmpty else { return }
        // Keep the first deadline during a burst of partial speech results.
        guard translationDebounce == nil else { return }
        translationDebounce = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            self.translationInput = self.englishText
            self.translationChannel(for: self.sourceLanguage).send(.init(
                text: self.translationInput, revision: self.translationRevision
            ))
            self.translationDebounce = nil
        }
    }

    private func resetTranscriptHistory() {
        finalizedTranscriptSegments = []
        currentTranscript = nil
        invalidateTranslation()
    }

    private func invalidateTranslation() {
        translationDebounce?.cancel()
        translationDebounce = nil
        translationInput = ""
        translationRevision = UUID()
        translationError = nil
        englishTranslation.clear()
        koreanTranslation.clear()
    }

    func clearTranscript() {
        // A fresh recognition epoch also rejects results already queued for the main actor.
        recognitionEpoch = transcriber.resetTranscript(preservingPartialResult: true)
        resetTranscriptHistory()
        englishText = ""
        chineseText = ""
    }

    func removeExpiredTranscripts() {
        let cutoff = now().addingTimeInterval(-Self.transcriptRetention)
        let originalCount = finalizedTranscriptSegments.count
        finalizedTranscriptSegments.removeAll { $0.firstHeardAt <= cutoff }
        let partialExpired = currentTranscript.map { $0.firstHeardAt <= cutoff } ?? false
        if partialExpired {
            currentTranscript = nil
            recognitionEpoch = transcriber.resetTranscript(preservingPartialResult: true)
        }
        guard originalCount != finalizedTranscriptSegments.count || partialExpired else { return }
        englishText = currentLimitedDisplayText()
        // Translation is a snapshot of the whole retained source. Clear it immediately
        // rather than leave expired words visible while the replacement is translated.
        chineseText = ""
        invalidateTranslation()
        scheduleTranslation(delay: 0)
    }

    private func applyAutomaticSourceSelection(_ identifier: String) {
        isApplyingAutomaticSourceSelection = true
        selectedSourceID = identifier
        isApplyingAutomaticSourceSelection = false
    }

    private func currentLimitedDisplayText() -> String {
        TranscriptFormatter.retainingLastLines(
            TranscriptFormatter.displayText(
                finalized: finalizedTranscriptSegments.map(\.text),
                current: currentTranscript?.text ?? ""
            ),
            maximum: maximumTranscriptLines
        )
    }

    private func trimFinalizedTranscriptHistory() {
        finalizedTranscriptSegments = Array(finalizedTranscriptSegments.flatMap { segment in
            TranscriptFormatter.paragraphized(segment.text).components(separatedBy: .newlines)
                .filter { !$0.isEmpty }
                .map { TimedTranscript(text: $0, firstHeardAt: segment.firstHeardAt) }
        }.suffix(maximumTranscriptLines))
    }

    private func applyTranscriptLineLimit() {
        trimFinalizedTranscriptHistory()
        removeExpiredTranscripts()
        guard !finalizedTranscriptSegments.isEmpty || currentTranscript != nil else { return }
        let limitedDisplay = currentLimitedDisplayText()
        englishText = limitedDisplay
        chineseText = ""
        invalidateTranslation()
        scheduleTranslation(delay: 0)
    }

    deinit {
        audioTap.stop()
        transcriber.stop()
    }
}
