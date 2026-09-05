// AI-Author: Codex (OpenAI gpt-5.6-sol)
import AppKit
import SwiftUI

struct AudioSourcePopUp: NSViewRepresentable {
    @Binding var selection: String
    let sources: [AudioSource]
    let canSelectSources: Bool
    let onWillOpen: () -> [AudioSource]

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectionChanged(_:))
        button.menu?.delegate = context.coordinator
        button.setAccessibilityLabel("音频源")
        context.coordinator.button = button
        context.coordinator.configure(using: sources)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        context.coordinator.button = button
        button.menu?.delegate = context.coordinator
        context.coordinator.configure(using: sources)
    }

    @MainActor
    final class Coordinator: NSObject, NSMenuDelegate {
        var parent: AudioSourcePopUp
        weak var button: NSPopUpButton?
        private var displayedSources: [AudioSource] = []

        init(parent: AudioSourcePopUp) {
            self.parent = parent
        }

        func menuWillOpen(_ menu: NSMenu) {
            configure(using: parent.onWillOpen())
        }

        @objc func selectionChanged(_ sender: NSPopUpButton) {
            guard parent.canSelectSources,
                  let identifier = sender.selectedItem?.representedObject as? String,
                  let source = displayedSources.first(where: { $0.id == identifier }),
                  source.isAvailable else {
                configure(using: parent.sources)
                return
            }
            parent.selection = identifier
        }

        func configure(using sources: [AudioSource]) {
            guard let button else { return }
            displayedSources = sources
            button.removeAllItems()

            for source in sources {
                let status: String
                if !source.isAvailable {
                    status = "（未运行）"
                } else if source.isActive && source.id != AudioSource.system.id {
                    status = "（正在播放）"
                } else {
                    status = ""
                }

                button.addItem(withTitle: source.label + status)
                guard let item = button.lastItem else { continue }
                item.representedObject = source.id
                item.isEnabled = parent.canSelectSources && source.isAvailable
                item.state = source.id == parent.selection ? .on : .off
            }

            if let selectedItem = button.itemArray.first(where: {
                ($0.representedObject as? String) == parent.selection
            }) {
                button.select(selectedItem)
            } else {
                button.select(nil)
            }
        }
    }
}
