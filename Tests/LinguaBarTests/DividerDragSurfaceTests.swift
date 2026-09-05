// AI-Author: Codex (OpenAI gpt-5.6-sol)
import XCTest
@testable import LinguaBar

final class DividerDragSurfaceTests: XCTestCase {
    func testDividerExplicitlyRejectsWindowBackgroundDragging() {
        XCTAssertFalse(DividerDragNSView().mouseDownCanMoveWindow)
    }
}
