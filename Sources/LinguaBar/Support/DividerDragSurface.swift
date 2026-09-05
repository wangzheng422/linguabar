// AI-Author: Codex (OpenAI gpt-5.6-sol)
import AppKit
import SwiftUI

struct DividerDragSurface: NSViewRepresentable {
    @Binding var fraction: Double
    @Binding var isHovered: Bool
    @Binding var isDragging: Bool
    let totalHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(
            fraction: $fraction,
            isHovered: $isHovered,
            isDragging: $isDragging
        )
    }

    func makeNSView(context: Context) -> DividerDragNSView {
        let view = DividerDragNSView()
        view.delegate = context.coordinator
        return view
    }

    func updateNSView(_ nsView: DividerDragNSView, context: Context) {
        context.coordinator.fraction = $fraction
        context.coordinator.isHovered = $isHovered
        context.coordinator.isDragging = $isDragging
        nsView.totalHeight = max(1, totalHeight)
        nsView.currentFraction = fraction
    }

    final class Coordinator: DividerDragNSViewDelegate {
        var fraction: Binding<Double>
        var isHovered: Binding<Bool>
        var isDragging: Binding<Bool>

        init(
            fraction: Binding<Double>,
            isHovered: Binding<Bool>,
            isDragging: Binding<Bool>
        ) {
            self.fraction = fraction
            self.isHovered = isHovered
            self.isDragging = isDragging
        }

        func dividerDidHover(_ isHovered: Bool) {
            self.isHovered.wrappedValue = isHovered
        }

        func dividerDidBeginDragging() {
            isDragging.wrappedValue = true
        }

        func dividerDidDrag(to fraction: Double) {
            self.fraction.wrappedValue = fraction
        }

        func dividerDidEndDragging() {
            isDragging.wrappedValue = false
        }
    }
}

protocol DividerDragNSViewDelegate: AnyObject {
    func dividerDidHover(_ isHovered: Bool)
    func dividerDidBeginDragging()
    func dividerDidDrag(to fraction: Double)
    func dividerDidEndDragging()
}

final class DividerDragNSView: NSView {
    weak var delegate: DividerDragNSViewDelegate?
    var totalHeight: CGFloat = 1
    var currentFraction = 0.48

    private var startWindowY: CGFloat?
    private var startFraction = 0.48
    private var trackingAreaReference: NSTrackingArea?

    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        startWindowY = event.locationInWindow.y
        startFraction = currentFraction
        delegate?.dividerDidBeginDragging()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startWindowY else { return }
        let downwardTranslation = startWindowY - event.locationInWindow.y
        let nextFraction = min(0.72, max(0.28, startFraction + downwardTranslation / totalHeight))
        currentFraction = nextFraction
        delegate?.dividerDidDrag(to: nextFraction)
    }

    override func mouseUp(with event: NSEvent) {
        startWindowY = nil
        delegate?.dividerDidEndDragging()
    }

    override func mouseEntered(with event: NSEvent) {
        delegate?.dividerDidHover(true)
    }

    override func mouseExited(with event: NSEvent) {
        delegate?.dividerDidHover(false)
    }

    override func updateTrackingAreas() {
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(trackingArea)
        trackingAreaReference = trackingArea
        super.updateTrackingAreas()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeUpDown)
    }
}
