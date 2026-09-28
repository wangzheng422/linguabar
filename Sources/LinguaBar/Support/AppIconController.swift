import AppKit

@MainActor
final class AppIconController {
    enum Marker: Equatable {
        case none
        case permission
        case listening
        case warning
        case failed

        var accessibilityDescription: String {
            switch self {
            case .none:
                return "LinguaBar ready"
            case .permission:
                return "LinguaBar requesting permission"
            case .listening:
                return "LinguaBar listening"
            case .warning:
                return "LinguaBar warning"
            case .failed:
                return "LinguaBar failed"
            }
        }
    }

    private let application: NSApplication
    private(set) var baseIcon: NSImage?
    private(set) var currentIcon: NSImage?

    init(application: NSApplication? = nil) {
        self.application = application ?? .shared
    }

    /// Captures the unadorned icon once. All later states are rendered from this
    /// copy so a transition can never draw a badge over a previous badge.
    func install(baseIcon: NSImage?) {
        guard let source = baseIcon ?? application.applicationIconImage else {
            self.baseIcon = nil
            self.currentIcon = nil
            return
        }

        let copy = Self.copy(source)
        self.baseIcon = copy
        currentIcon = Self.copy(copy)
        application.applicationIconImage = currentIcon
        apply(.idle)
    }

    func apply(_ status: SubtitleStatus) {
        // The dynamic icon is the status affordance. Clear any stale system badge
        // so it cannot be mistaken for a count or duplicate the marker.
        application.dockTile.badgeLabel = nil

        guard let baseIcon else {
            currentIcon = nil
            return
        }
        let marker = Self.marker(for: status)
        let rendered = Self.render(baseIcon: baseIcon, marker: marker)
        rendered.accessibilityDescription = marker.accessibilityDescription
        currentIcon = rendered
        application.applicationIconImage = rendered
    }

    static func marker(for status: SubtitleStatus) -> Marker {
        switch status {
        case .idle, .finishing:
            return .none
        case .requestingPermission:
            return .permission
        case .listening:
            return .listening
        case .warning:
            return .warning
        case .failed:
            return .failed
        }
    }

    static func render(baseIcon: NSImage, for status: SubtitleStatus) -> NSImage {
        render(baseIcon: baseIcon, marker: marker(for: status))
    }

    static func render(baseIcon: NSImage, marker: Marker) -> NSImage {
        guard marker != .none,
              baseIcon.size.width > 0,
              baseIcon.size.height > 0 else {
            let copy = Self.copy(baseIcon)
            copy.accessibilityDescription = marker.accessibilityDescription
            return copy
        }

        let rendered = NSImage(size: baseIcon.size)
        rendered.isTemplate = false
        rendered.lockFocus()
        defer { rendered.unlockFocus() }

        let bounds = NSRect(origin: .zero, size: baseIcon.size)
        baseIcon.draw(
            in: bounds,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: false,
            hints: nil
        )
        draw(marker: marker, in: bounds)
        rendered.accessibilityDescription = marker.accessibilityDescription
        return rendered
    }

    private static func copy(_ image: NSImage) -> NSImage {
        guard let copy = image.copy() as? NSImage else { return image }
        copy.size = image.size
        return copy
    }

    private static func draw(marker: Marker, in bounds: NSRect) {
        guard marker != .none else { return }

        let minimumDimension = min(bounds.width, bounds.height)
        let diameter = min(
            minimumDimension * 0.44,
            max(4, minimumDimension * 0.34)
        )
        let margin = max(1, minimumDimension * 0.035)
        let badge = NSRect(
            x: bounds.maxX - margin - diameter,
            y: bounds.minY + margin,
            width: diameter,
            height: diameter
        )

        let circle = NSBezierPath(ovalIn: badge)
        fillColor(for: marker).setFill()
        circle.fill()

        // A slim white keyline keeps the badge legible against both light and
        // dark portions of the bundled icon without obscuring the base image.
        NSColor(calibratedWhite: 1, alpha: 0.92).setStroke()
        circle.lineWidth = max(1, diameter * 0.045)
        circle.stroke()

        switch marker {
        case .none:
            break
        case .permission:
            drawPermissionSymbol(in: badge)
        case .listening:
            drawPlaySymbol(in: badge)
        case .warning:
            drawWarningSymbol(in: badge)
        case .failed:
            drawFailureSymbol(in: badge)
        }
    }

    private static func fillColor(for marker: Marker) -> NSColor {
        switch marker {
        case .none:
            return .clear
        case .permission:
            return NSColor(calibratedWhite: 0.64, alpha: 0.96)
        case .listening:
            return NSColor(calibratedRed: 0.18, green: 0.78, blue: 0.32, alpha: 0.98)
        case .warning:
            return NSColor(calibratedRed: 0.98, green: 0.65, blue: 0.10, alpha: 0.98)
        case .failed:
            return NSColor(calibratedRed: 0.90, green: 0.17, blue: 0.16, alpha: 0.98)
        }
    }

    private static func drawPermissionSymbol(in badge: NSRect) {
        let symbolColor = NSColor(calibratedWhite: 0.18, alpha: 0.92)
        symbolColor.setFill()

        let centerX = badge.midX
        let keyholeRadius = badge.width * 0.13
        NSBezierPath(
            ovalIn: NSRect(
                x: centerX - keyholeRadius,
                y: badge.midY + badge.height * 0.03,
                width: keyholeRadius * 2,
                height: keyholeRadius * 2
            )
        ).fill()

        let stemWidth = badge.width * 0.13
        let stemHeight = badge.height * 0.24
        NSBezierPath(
            roundedRect: NSRect(
                x: centerX - stemWidth / 2,
                y: badge.midY - badge.height * 0.23,
                width: stemWidth,
                height: stemHeight
            ),
            xRadius: stemWidth / 2,
            yRadius: stemWidth / 2
        ).fill()
    }

    private static func drawPlaySymbol(in badge: NSRect) {
        let symbol = NSBezierPath()
        symbol.move(to: NSPoint(x: badge.minX + badge.width * 0.37, y: badge.minY + badge.height * 0.24))
        symbol.line(to: NSPoint(x: badge.minX + badge.width * 0.37, y: badge.maxY - badge.height * 0.24))
        symbol.line(to: NSPoint(x: badge.maxX - badge.width * 0.24, y: badge.midY))
        symbol.close()
        NSColor(calibratedWhite: 1, alpha: 0.98).setFill()
        symbol.fill()
    }

    private static func drawWarningSymbol(in badge: NSRect) {
        let symbolColor = NSColor(calibratedWhite: 0.15, alpha: 0.94)
        symbolColor.setFill()

        let lineWidth = max(1, badge.width * 0.095)
        let lineHeight = badge.height * 0.33
        NSBezierPath(
            roundedRect: NSRect(
                x: badge.midX - lineWidth / 2,
                y: badge.midY - lineHeight * 0.06,
                width: lineWidth,
                height: lineHeight
            ),
            xRadius: lineWidth / 2,
            yRadius: lineWidth / 2
        ).fill()

        let dotDiameter = max(1, badge.width * 0.10)
        NSBezierPath(
            ovalIn: NSRect(
                x: badge.midX - dotDiameter / 2,
                y: badge.minY + badge.height * 0.22,
                width: dotDiameter,
                height: dotDiameter
            )
        ).fill()
    }

    private static func drawFailureSymbol(in badge: NSRect) {
        let symbol = NSBezierPath()
        let inset = badge.width * 0.30
        symbol.move(to: NSPoint(x: badge.minX + inset, y: badge.minY + inset))
        symbol.line(to: NSPoint(x: badge.maxX - inset, y: badge.maxY - inset))
        symbol.move(to: NSPoint(x: badge.minX + inset, y: badge.maxY - inset))
        symbol.line(to: NSPoint(x: badge.maxX - inset, y: badge.minY + inset))
        symbol.lineWidth = max(1, badge.width * 0.11)
        symbol.lineCapStyle = .round
        NSColor(calibratedWhite: 1, alpha: 0.98).setStroke()
        symbol.stroke()
    }
}
