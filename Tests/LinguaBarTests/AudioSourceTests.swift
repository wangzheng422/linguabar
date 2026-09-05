// AI-Author: Codex (OpenAI gpt-5.6-sol)
import XCTest
@testable import LinguaBar

final class AudioSourceTests: XCTestCase {
    func testMeetingAppFilterIncludesRequestedApps() {
        XCTAssertTrue(AudioSource.isMeetingApp(label: "Google Meet", bundleIdentifier: nil))
        XCTAssertTrue(AudioSource.isMeetingApp(label: "Google Chrome", bundleIdentifier: "com.google.Chrome"))
        XCTAssertTrue(AudioSource.isMeetingApp(label: "Microsoft Teams", bundleIdentifier: "com.microsoft.teams2"))
        XCTAssertFalse(AudioSource.isMeetingApp(label: "Music", bundleIdentifier: "com.apple.Music"))
    }

    func testDefaultPrefersGoogleMeetOverChromeAndSystem() {
        let chrome = source(id: "chrome", label: "Google Chrome", bundle: "com.google.Chrome")
        let meet = source(
            id: "meet",
            label: "Google Meet",
            bundle: "com.google.Chrome.app.kjgfgldnnfoeklkmfkjfagphfepbbdan"
        )

        XCTAssertEqual(
            AudioSource.preferredDefault(in: [.system, chrome, meet]).id,
            meet.id
        )
    }

    func testDefaultFallsBackToChromeThenSystem() {
        let chrome = source(id: "chrome", label: "Google Chrome", bundle: "com.google.Chrome")
        XCTAssertEqual(AudioSource.preferredDefault(in: [.system, chrome]).id, chrome.id)
        XCTAssertEqual(AudioSource.preferredDefault(in: [.system]).id, AudioSource.system.id)
    }

    func testLanguageModesOnlyTranslateEnglishAndKorean() {
        XCTAssertEqual(SourceLanguage.english.speechLocaleIdentifier, "en-US")
        XCTAssertEqual(SourceLanguage.korean.speechLocaleIdentifier, "ko-KR")
        XCTAssertEqual(SourceLanguage.chinese.speechLocaleIdentifier, "zh-CN")
        XCTAssertTrue(SourceLanguage.english.needsChineseTranslation)
        XCTAssertTrue(SourceLanguage.korean.needsChineseTranslation)
        XCTAssertFalse(SourceLanguage.chinese.needsChineseTranslation)
        XCTAssertNil(SourceLanguage.chinese.translationLanguageIdentifier)
    }

    func testAudioSourcePersistenceDoesNotDependOnProcessID() {
        let oldProcess = source(id: "pid:123", label: "Google Chrome", bundle: "com.google.Chrome")
        let relaunched = source(id: "pid:987", label: "Google Chrome", bundle: "com.google.Chrome")

        XCTAssertEqual(oldProcess.persistenceIdentifier, "bundle:com.google.Chrome")
        XCTAssertEqual(
            AudioSource.restoredSource(
                matching: oldProcess.persistenceIdentifier,
                in: [.system, relaunched]
            )?.id,
            relaunched.id
        )
    }

    func testCandidateMenuAlwaysContainsRequestedApplications() {
        let candidates = AudioSource.menuCandidates(from: [.system])

        XCTAssertEqual(
            Array(candidates.prefix(3).map(\.label)),
            ["Google Chrome", "Google Meet", "Microsoft Teams"]
        )
        XCTAssertTrue(candidates.prefix(3).allSatisfy { !$0.isAvailable })
        XCTAssertEqual(candidates.last, .system)
    }

    func testGoogleMeetCandidateUsesChromeProcessWhenMeetRunsInBrowser() {
        let chrome = source(id: "pid:987", label: "Google Chrome", bundle: "com.google.Chrome")
        let candidates = AudioSource.menuCandidates(from: [.system, chrome])
        let menuChrome = candidates.first { $0.id == AudioSource.googleChromeID }
        let menuMeet = candidates.first { $0.id == AudioSource.googleMeetID }

        XCTAssertEqual(menuChrome?.target, chrome.target)
        XCTAssertEqual(menuMeet?.target, chrome.target)
        XCTAssertTrue(menuChrome?.isAvailable == true)
        XCTAssertTrue(menuMeet?.isAvailable == true)
    }

    func testUnavailableFixedCandidatesDoNotOverrideSystemDefault() {
        let candidates = AudioSource.menuCandidates(from: [.system])

        XCTAssertEqual(AudioSource.preferredDefault(in: candidates), .system)
    }

    private func source(id: String, label: String, bundle: String?) -> AudioSource {
        AudioSource(
            id: id,
            label: label,
            bundleIdentifier: bundle,
            isActive: false,
            target: .process(123)
        )
    }
}
