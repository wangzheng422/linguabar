// AI-Author: Codex (OpenAI gpt-5.6-sol)
import AppKit
import SwiftUI

@main
struct LinguaBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = SubtitleStore()

    var body: some Scene {
        WindowGroup(id: "subtitles") {
            ContentView(store: store)
                .frame(minWidth: 980, idealWidth: 1120, minHeight: 340, idealHeight: 430)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1120, height: 430)
        .commands {
            CommandGroup(after: .appInfo) {
                Button(store.status.isCapturing ? "停止字幕" : "开始字幕") {
                    Task { await store.toggleCapture() }
                }
                .keyboardShortcut(.space, modifiers: [.command, .shift])
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}
