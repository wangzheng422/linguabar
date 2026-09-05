// AI-Author: Codex (OpenAI gpt-5.6-sol)
import XCTest
@testable import LinguaBar

final class SpeechRecognitionErrorPolicyTests: XCTestCase {
    func testNoSpeechErrorCodeIsTreatedAsNormalSilence() {
        let error = NSError(
            domain: "kAFAssistantErrorDomain",
            code: 1110,
            userInfo: [NSLocalizedDescriptionKey: "No speech detected"]
        )

        XCTAssertTrue(SpeechRecognitionErrorPolicy.isNoSpeech(error))
    }

    func testNoSpeechMessageFallbackIsCaseInsensitive() {
        let error = NSError(
            domain: "LinguaBarTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "NO SPEECH DETECTED"]
        )

        XCTAssertTrue(SpeechRecognitionErrorPolicy.isNoSpeech(error))
    }

    func testRealRecognitionFailureStillSurfaces() {
        let error = NSError(
            domain: "LinguaBarTests",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Network connection was lost"]
        )

        XCTAssertFalse(SpeechRecognitionErrorPolicy.isNoSpeech(error))
    }
}
