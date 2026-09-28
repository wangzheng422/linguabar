// AI-Author: Codex (OpenAI gpt-5.6-sol)
import AppKit
import Combine
import SwiftUI

@main
struct LinguaBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup(id: "subtitles") {
            ContentView(store: appDelegate.store)
                .frame(minWidth: 980, idealWidth: 1120, minHeight: 340, idealHeight: 430)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1120, height: 430)
        .commands {
            CommandGroup(after: .appInfo) {
                Button(appDelegate.status.isCapturing ? "停止字幕" : "开始字幕") {
                    Task { await appDelegate.store.toggleCapture() }
                }
                .keyboardShortcut(.space, modifiers: [.command, .shift])
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let store: SubtitleStore
    @Published private(set) var status: SubtitleStatus = .idle

    private let appIconController: AppIconController
    private var statusSubscription: AnyCancellable?

    override init() {
        store = SubtitleStore()
        appIconController = AppIconController()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let bundledIcon = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
            .flatMap(NSImage.init(contentsOf:))
        appIconController.install(baseIcon: bundledIcon)
        statusSubscription = store.$status
            .removeDuplicates()
            .sink { [weak self] status in
                self?.status = status
                self?.appIconController.apply(status)
            }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if store.status.isCapturing { store.stopCapture() }
        guard store.status == .finishing || store.archive.hasUnfinishedExports else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "还有监听记录尚未保存完成"
        alert.informativeText = "请等待翻译完成，或在窗口中重试失败的保存。现在退出可能丢失尚未保存的文字或中文译文；已保存的原文不受影响。"
        alert.addButton(withTitle: "继续等待")
        alert.addButton(withTitle: "仍然退出")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
}
