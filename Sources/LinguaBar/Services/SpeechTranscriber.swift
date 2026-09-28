// AI-Author: Codex (OpenAI gpt-5.6-sol)
// AI-Author: Codex (OpenAI model not exposed by runtime)
import AVFoundation
import Foundation
import Speech

final class SpeechTranscriber: @unchecked Sendable {
    typealias ResultHandler = (_ text: String, _ isFinal: Bool, _ epoch: UInt64) -> Void
    typealias ErrorHandler = (_ message: String) -> Void

    private var recognizer: SFSpeechRecognizer?
    private let queue = DispatchQueue(label: "com.wzh.linguabar.speech")
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var restartTimer: DispatchSourceTimer?
    private var resultHandler: ResultHandler?
    private var errorHandler: ErrorHandler?
    private var running = false
    private var finishing = false
    private var finishCompletion: (() -> Void)?
    private var taskGeneration: UInt64 = 0
    private var transcriptEpoch: UInt64 = 0
    private var lastPartialText = ""
    private var localeIdentifier = "en-US"

    static func requestAuthorization() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .denied, .restricted: return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        @unknown default: return false
        }
    }

    func start(
        localeIdentifier: String,
        onResult: @escaping ResultHandler,
        onError: @escaping ErrorHandler
    ) throws -> UInt64 {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))
        guard let recognizer, recognizer.isAvailable else {
            throw NSError(
                domain: "LinguaBar.Speech",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "所选语言的语音识别服务当前不可用。"]
            )
        }
        resultHandler = onResult
        errorHandler = onError
        self.localeIdentifier = localeIdentifier
        running = true
        let epoch = queue.sync {
            finishing = false
            transcriptEpoch &+= 1
            lastPartialText = ""
            startRecognitionTask(flushingPartialResult: false)
            return transcriptEpoch
        }
        scheduleRestart()
        return epoch
    }

    /// Discard the recognizer's cumulative partial result without stopping the audio tap.
    func resetTranscript(preservingPartialResult: Bool = false) -> UInt64 {
        queue.sync {
            guard !finishing else { return transcriptEpoch }
            if preservingPartialResult { flushPartialResult() }
            transcriptEpoch &+= 1
            lastPartialText = ""
            startRecognitionTask(flushingPartialResult: false)
            return transcriptEpoch
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        queue.async { [weak self] in
            guard let self, self.running else { return }
            self.request?.append(buffer)
        }
    }

    func stop() {
        queue.sync { stopOnQueue() }
    }

    /// End audio without immediately cancelling the final recognition result.
    /// A bounded deadline keeps offline/service failures from trapping the UI.
    func finish() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard running else { continuation.resume(); return }
                finishing = true
                restartTimer?.cancel()
                restartTimer = nil
                finishCompletion = { continuation.resume() }
                let generation = taskGeneration
                request?.endAudio()
                queue.asyncAfter(deadline: .now() + 2) { [weak self] in
                    guard let self, self.finishing, self.taskGeneration == generation else { return }
                    self.stopOnQueue()
                }
            }
        }
    }

    private func stopOnQueue() {
        running = false
        finishing = false
        taskGeneration &+= 1
        lastPartialText = ""
        restartTimer?.cancel()
        restartTimer = nil
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        resultHandler = nil
        errorHandler = nil
        let completion = finishCompletion
        finishCompletion = nil
        completion?()
    }

    private func startRecognitionTask(flushingPartialResult: Bool) {
        guard running, !finishing, let recognizer else { return }
        if flushingPartialResult { flushPartialResult() }

        taskGeneration &+= 1
        let generation = taskGeneration
        task?.cancel()
        request?.endAudio()

        let newRequest = SFSpeechAudioBufferRecognitionRequest()
        newRequest.shouldReportPartialResults = true
        newRequest.addsPunctuation = true
        newRequest.taskHint = .dictation
        request = newRequest

        task = recognizer.recognitionTask(with: newRequest) { [weak self] result, error in
            self?.queue.async { [weak self] in
                self?.handle(result: result, error: error, generation: generation)
            }
        }
    }

    private func flushPartialResult() {
        guard !lastPartialText.isEmpty else { return }
        let finalizedText = LivePunctuationFormatter.format(
            lastPartialText, segments: [], localeIdentifier: localeIdentifier, isFinal: true)
        resultHandler?(finalizedText, true, transcriptEpoch)
        lastPartialText = ""
    }

    private func handle(
        result: SFSpeechRecognitionResult?,
        error: Error?,
        generation: UInt64
    ) {
        guard running, generation == taskGeneration else { return }

        if let result {
            let transcription = result.bestTranscription
            let segments = transcription.segments.map {
                TimedSpeechSegment(
                    utf16EndOffset: NSMaxRange($0.substringRange),
                    timestamp: $0.timestamp,
                    duration: $0.duration
                )
            }
            let text = LivePunctuationFormatter.format(
                transcription.formattedString,
                segments: segments,
                localeIdentifier: localeIdentifier,
                isFinal: result.isFinal
            )
            lastPartialText = text
            resultHandler?(text, result.isFinal, transcriptEpoch)
            if result.isFinal {
                lastPartialText = ""
                if finishing { stopOnQueue() }
                else { startRecognitionTask(flushingPartialResult: false) }
            }
            return
        }

        guard let error else { return }
        if finishing { stopOnQueue(); return }
        let nsError = error as NSError
        if SpeechRecognitionErrorPolicy.isNoSpeech(nsError) {
            scheduleTaskRestart(after: 0.25, generation: generation)
        } else {
            errorHandler?(error.localizedDescription)
            scheduleTaskRestart(after: 0.5, generation: generation)
        }
    }

    private func scheduleTaskRestart(
        after delay: TimeInterval,
        generation: UInt64
    ) {
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.running, self.taskGeneration == generation else { return }
            self.startRecognitionTask(flushingPartialResult: true)
        }
    }

    private func scheduleRestart() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 50, repeating: 50)
        timer.setEventHandler { [weak self] in
            self?.startRecognitionTask(flushingPartialResult: true)
        }
        timer.resume()
        restartTimer = timer
    }

    deinit { stop() }
}

enum SpeechRecognitionErrorPolicy {
    static func isNoSpeech(_ error: NSError) -> Bool {
        if error.domain == "kAFAssistantErrorDomain", error.code == 1110 {
            return true
        }
        return error.localizedDescription.localizedCaseInsensitiveContains("no speech detected")
    }
}
