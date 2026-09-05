// AI-Author: Codex (OpenAI gpt-5.6-sol)
import AppKit
import SwiftUI

struct ScrollViewAppearanceConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> ConfiguringView {
        ConfiguringView()
    }

    func updateNSView(_ nsView: ConfiguringView, context: Context) {
        nsView.applyAppearanceWhenAttached()
    }

    final class ConfiguringView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyAppearanceWhenAttached()
        }

        func applyAppearanceWhenAttached() {
            DispatchQueue.main.async { [weak self] in
                guard let scrollView = self?.enclosingScrollView else { return }
                ScrollViewAppearanceConfigurator.configure(scrollView)
            }
        }
    }

    static func configure(_ scrollView: NSScrollView) {
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.verticalScroller?.knobStyle = .light
    }
}
