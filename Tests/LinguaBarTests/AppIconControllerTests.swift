import AppKit
import XCTest
@testable import LinguaBar

@MainActor
final class AppIconControllerTests: XCTestCase {
    func testStatusMappingUsesNeutralPermissionAndDistinctFailureMarkers() {
        XCTAssertEqual(AppIconController.marker(for: .idle), .none)
        XCTAssertEqual(AppIconController.marker(for: .finishing), .none)
        XCTAssertEqual(AppIconController.marker(for: .requestingPermission), .permission)
        XCTAssertEqual(AppIconController.marker(for: .listening), .listening)
        XCTAssertEqual(AppIconController.marker(for: .warning("reconnecting")), .warning)
        XCTAssertEqual(AppIconController.marker(for: .failed("permission denied")), .failed)
    }

    func testRendererPreservesBaseForIdleAndAddsDeterministicStatusPixels() throws {
        let base = makeBaseIcon()
        let idle = AppIconController.render(baseIcon: base, for: .idle)
        let listening = AppIconController.render(baseIcon: base, for: .listening)
        let warning = AppIconController.render(baseIcon: base, for: .warning("reconnecting"))
        let failed = AppIconController.render(baseIcon: base, for: .failed("capture failed"))

        XCTAssertEqual(idle.size, base.size)
        XCTAssertEqual(listening.size, base.size)
        XCTAssertEqual(warning.size, base.size)
        XCTAssertEqual(failed.size, base.size)
        XCTAssertEqual(try imageData(idle), try imageData(base))
        XCTAssertNotEqual(try imageData(listening), try imageData(idle))
        XCTAssertNotEqual(try imageData(warning), try imageData(listening))
        XCTAssertNotEqual(try imageData(failed), try imageData(warning))
        XCTAssertEqual(
            try imageData(AppIconController.render(baseIcon: base, for: .warning("different message"))),
            try imageData(warning)
        )
    }

    func testControllerAlwaysStartsWithBaseInsteadOfCompoundingOverlays() throws {
        let base = makeBaseIcon()
        let application = NSApplication.shared
        let originalIcon = application.applicationIconImage
        defer {
            application.applicationIconImage = originalIcon
            application.dockTile.badgeLabel = nil
        }

        let controller = AppIconController(application: application)
        controller.install(baseIcon: base)
        controller.apply(.listening)
        let listening = try XCTUnwrap(controller.currentIcon)
        controller.apply(.warning("second"))
        let warning = try XCTUnwrap(controller.currentIcon)
        controller.apply(.idle)
        let idle = try XCTUnwrap(controller.currentIcon)

        XCTAssertNotEqual(try imageData(listening), try imageData(warning))
        XCTAssertEqual(
            try imageData(warning),
            try imageData(AppIconController.render(baseIcon: base, for: .warning("second")))
        )
        XCTAssertEqual(try imageData(idle), try imageData(base))
    }

    private func makeBaseIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 128, height: 128))
        image.lockFocus()
        NSColor(calibratedRed: 0.12, green: 0.18, blue: 0.30, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 128, height: 128)).fill()
        image.unlockFocus()
        return image
    }

    private func imageData(_ image: NSImage) throws -> Data {
        guard let data = image.tiffRepresentation else {
            throw NSError(domain: "AppIconControllerTests", code: 1)
        }
        return data
    }
}
