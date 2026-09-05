// AI-Author: Codex (OpenAI gpt-5.6-sol)
import Combine
import Foundation
import Translation

@MainActor
final class SubtitleStore: ObservableObject {
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
    @Published private(set) var translationInput = ""
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
    private let audioTap = CoreAudioProcessTap()
    private let transcriber = SpeechTranscriber()
    private var translationDebounce: Task<Void, Never>?
    private var finalizedTranscriptSegments: [String] = []
    private var currentTranscript = ""
    private var isApplyingAutomaticSourceSelection = false

    init(
        defaults: UserDefaults = .standard,
        sourceProvider: @escaping () -> [AudioSource] = CoreAudioProcessTap.availableSources
    ) {
        self.defaults = defaults
        self.sourceProvider = sourceProvider
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
        status = .requestingPermission
        guard await SpeechTranscriber.requestAuthorization() else {
            status = .failed("请在系统设置中允许 LinguaBar 使用语音识别。")
            return
        }

        do {
            resetTranscriptHistory()
            try transcriber.start(
                localeIdentifier: sourceLanguage.speechLocaleIdentifier,
                onResult: { [weak self] text, isFinal in
                    Task { @MainActor in self?.acceptTranscript(text, isFinal: isFinal) }
                },
                onError: { [weak self] message in
                    Task { @MainActor in
                        self?.status = .warning("语音识别正在重连：\(message)")
                    }
                }
            )
            try audioTap.start(
                source: selectedSource,
                onAudio: { [weak self] buffer in self?.transcriber.append(buffer) },
                onWarning: { [weak self] message in
                    Task { @MainActor in self?.status = .warning(message) }
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
            status = .failed(error.localizedDescription)
        }
    }

    func stopCapture() {
        translationDebounce?.cancel()
        translationDebounce = nil
        audioTap.stop()
        transcriber.stop()
        status = .idle
    }

    func acceptTranslation(_ translation: String, for source: String) {
        guard source == translationInput else { return }
        chineseText = TranscriptFormatter.retainingLastLines(
            TranscriptFormatter.paragraphized(translation),
            maximum: maximumTranscriptLines
        )
    }

    private func acceptTranscript(_ text: String, isFinal: Bool) {
        let transcript = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return }

        if isFinal {
            if finalizedTranscriptSegments.last != transcript {
                finalizedTranscriptSegments.append(transcript)
                trimFinalizedTranscriptHistory()
            }
            currentTranscript = ""
        } else {
            currentTranscript = transcript
        }

        let displayText = currentLimitedDisplayText()
        englishText = displayText
        if case .warning = status { status = .listening }
        guard sourceLanguage.needsChineseTranslation else { return }
        translationDebounce?.cancel()
        let delay: UInt64 = isFinal ? 50_000_000 : 380_000_000
        translationDebounce = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            self?.translationInput = displayText
        }
    }

    private func resetTranscriptHistory() {
        finalizedTranscriptSegments = []
        currentTranscript = ""
    }

    private func applyAutomaticSourceSelection(_ identifier: String) {
        isApplyingAutomaticSourceSelection = true
        selectedSourceID = identifier
        isApplyingAutomaticSourceSelection = false
    }

    private func currentLimitedDisplayText() -> String {
        TranscriptFormatter.retainingLastLines(
            TranscriptFormatter.displayText(
                finalized: finalizedTranscriptSegments,
                current: currentTranscript
            ),
            maximum: maximumTranscriptLines
        )
    }

    private func trimFinalizedTranscriptHistory() {
        let finalized = TranscriptFormatter.retainingLastLines(
            TranscriptFormatter.displayText(finalized: finalizedTranscriptSegments, current: ""),
            maximum: maximumTranscriptLines
        )
        finalizedTranscriptSegments = finalized.isEmpty
            ? []
            : finalized.components(separatedBy: .newlines)
    }

    private func applyTranscriptLineLimit() {
        trimFinalizedTranscriptHistory()
        guard !finalizedTranscriptSegments.isEmpty || !currentTranscript.isEmpty else { return }
        let limitedDisplay = currentLimitedDisplayText()
        englishText = limitedDisplay
        chineseText = TranscriptFormatter.retainingLastLines(
            chineseText,
            maximum: maximumTranscriptLines
        )
        if sourceLanguage.needsChineseTranslation {
            translationInput = limitedDisplay
        }
    }

    deinit {
        audioTap.stop()
        transcriber.stop()
    }
}
