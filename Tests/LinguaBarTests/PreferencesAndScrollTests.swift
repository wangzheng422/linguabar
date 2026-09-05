// AI-Author: Codex (OpenAI gpt-5.6-sol)
import AppKit
import XCTest
@testable import LinguaBar

@MainActor
final class PreferencesAndScrollTests: XCTestCase {
    func testStoreRestoresLanguageLineLimitAndStableAudioSource() {
        let suiteName = "LinguaBarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(SourceLanguage.korean.rawValue, forKey: "sourceLanguage")
        defaults.set(200, forKey: "maximumTranscriptLines")
        defaults.set("bundle:com.microsoft.teams2", forKey: "audioSource")
        let teams = source(
            id: "pid:2468",
            label: "Microsoft Teams",
            bundle: "com.microsoft.teams2"
        )

        let store = SubtitleStore(defaults: defaults, sourceProvider: { [.system, teams] })

        XCTAssertEqual(store.sourceLanguage, .korean)
        XCTAssertEqual(store.maximumTranscriptLines, 200)
        XCTAssertEqual(store.selectedSourceID, teams.id)

        store.sourceLanguage = .chinese
        store.maximumTranscriptLines = 125
        store.selectedSourceID = AudioSource.system.id

        XCTAssertEqual(defaults.string(forKey: "sourceLanguage"), SourceLanguage.chinese.rawValue)
        XCTAssertEqual(defaults.integer(forKey: "maximumTranscriptLines"), 125)
        XCTAssertEqual(defaults.string(forKey: "audioSource"), AudioSource.system.id)
    }

    func testStoreUsesMeetFirstDefaultWhenNoAudioPreferenceExists() {
        let suiteName = "LinguaBarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let meet = source(
            id: "pid:1357",
            label: "Google Meet",
            bundle: "com.google.Chrome.app.kjgfgldnnfoeklkmfkjfagphfepbbdan"
        )

        let store = SubtitleStore(defaults: defaults, sourceProvider: { [.system, meet] })

        XCTAssertEqual(store.selectedSourceID, meet.id)
        XCTAssertEqual(defaults.string(forKey: "audioSource"), meet.persistenceIdentifier)
        XCTAssertEqual(defaults.string(forKey: "sourceLanguage"), SourceLanguage.english.rawValue)
        XCTAssertEqual(defaults.integer(forKey: "maximumTranscriptLines"), 100)
    }

    func testScrollFollowingPausesUpwardAndResumesAtBottom() {
        let bottom = metrics(minY: 400, maxY: 500)
        let scrolledUp = metrics(minY: 250, maxY: 350)

        XCTAssertFalse(
            LiveScrollPolicy.shouldFollow(
                wasFollowing: true,
                previous: bottom,
                current: scrolledUp
            )
        )
        XCTAssertTrue(
            LiveScrollPolicy.shouldFollow(
                wasFollowing: false,
                previous: scrolledUp,
                current: bottom
            )
        )
    }

    func testScrollerUsesTransparentOverlayAppearance() {
        let scrollView = NSScrollView()
        scrollView.verticalScroller = NSScroller()

        ScrollViewAppearanceConfigurator.configure(scrollView)

        XCTAssertFalse(scrollView.drawsBackground)
        XCTAssertEqual(scrollView.backgroundColor, .clear)
        XCTAssertEqual(scrollView.scrollerStyle, .overlay)
        XCTAssertTrue(scrollView.autohidesScrollers)
        XCTAssertEqual(scrollView.verticalScroller?.knobStyle, .light)
    }

    private func metrics(minY: CGFloat, maxY: CGFloat) -> SubtitleScrollMetrics {
        SubtitleScrollMetrics(
            visibleMinY: minY,
            visibleMaxY: maxY,
            contentHeight: 500,
            containerHeight: 100
        )
    }

    private func source(id: String, label: String, bundle: String?) -> AudioSource {
        AudioSource(
            id: id,
            label: label,
            bundleIdentifier: bundle,
            isActive: false,
            target: .process(2468)
        )
    }
}
