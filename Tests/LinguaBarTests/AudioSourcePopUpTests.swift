// AI-Author: Codex (OpenAI gpt-5.6-sol)
import AppKit
import SwiftUI
import XCTest
@testable import LinguaBar

@MainActor
final class AudioSourcePopUpTests: XCTestCase {
    func testOpeningMenuRefreshesCandidatesBeforeDisplay() {
        var refreshCount = 0
        var selection = AudioSource.googleChromeID
        let stale = AudioSource.menuCandidates(from: [.system])
        let runningChrome = source(
            id: "pid:314",
            label: "Google Chrome",
            bundle: "com.google.Chrome"
        )
        let refreshed = AudioSource.menuCandidates(from: [.system, runningChrome])
        let popUp = AudioSourcePopUp(
            selection: Binding(
                get: { selection },
                set: { selection = $0 }
            ),
            sources: stale,
            canSelectSources: true,
            onWillOpen: {
                refreshCount += 1
                return refreshed
            }
        )
        let coordinator = popUp.makeCoordinator()
        let button = NSPopUpButton()
        coordinator.button = button
        coordinator.configure(using: stale)

        coordinator.menuWillOpen(button.menu!)

        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(
            Array(button.itemTitles.prefix(3)),
            ["Google Chrome", "Google Meet", "Microsoft Teams（未运行）"]
        )
        XCTAssertTrue(button.item(at: 0)?.isEnabled == true)
        XCTAssertTrue(button.item(at: 1)?.isEnabled == true)
        XCTAssertTrue(button.item(at: 2)?.isEnabled == false)
    }

    func testCapturingKeepsMenuOpenableButDisablesSourceChanges() {
        var selection = AudioSource.googleChromeID
        let runningChrome = source(
            id: "pid:2718",
            label: "Google Chrome",
            bundle: "com.google.Chrome"
        )
        let sources = AudioSource.menuCandidates(from: [.system, runningChrome])
        let popUp = AudioSourcePopUp(
            selection: Binding(
                get: { selection },
                set: { selection = $0 }
            ),
            sources: sources,
            canSelectSources: false,
            onWillOpen: { sources }
        )
        let coordinator = popUp.makeCoordinator()
        let button = NSPopUpButton()
        coordinator.button = button

        coordinator.configure(using: sources)

        XCTAssertTrue(button.isEnabled)
        XCTAssertTrue(button.itemArray.allSatisfy { !$0.isEnabled })
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
