// AI-Author: Codex (OpenAI gpt-5.6-sol)
// AI-Author: Codex (OpenAI model not exposed by runtime)
import AppKit
import SwiftUI
import Translation

struct ContentView: View {
    @ObservedObject var store: SubtitleStore
    @State private var splitFraction = 0.48
    @State private var isDividerHovered = false
    @State private var isDividerDragging = false
    @AppStorage("subtitleFontSize") private var subtitleFontSize = 30.0
    @AppStorage("subtitleBackgroundOpacity") private var backgroundOpacity = 0.86

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(backgroundOpacity)
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(backgroundOpacity * 0.82))
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)

            VStack(spacing: 0) {
                titleBar
                Divider().overlay(Color.white.opacity(0.12))
                subtitles
                Divider().overlay(Color.white.opacity(0.12))
                controlBar
                SessionArchiveView(archive: store.archive)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(8)
        .background(WindowConfigurator(alwaysOnTop: store.alwaysOnTop))
        .background {
            // Stable, independent language lanes avoid cancelling framework requests
            // even on language changes. Each lane has one active and one latest item.
            LiveTranslationTask(store: store, language: .english)
            LiveTranslationTask(store: store, language: .korean)
        }
    }

    private var titleBar: some View {
        HStack(spacing: 12) {
            Image(nsImage: bundledAppIcon)
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text("LinguaBar")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Google Meet / Teams 实时双语字幕")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
            }

            Spacer(minLength: 16)

            Button {
                store.clearTranscript()
            } label: {
                Label("清空", systemImage: "trash")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .fixedSize()
            .keyboardShortcut("k", modifiers: [.command, .shift])
            .help("仅清空屏幕上的字幕；本场完整文字仍会在停止时自动保存")

            AudioSourcePopUp(
                selection: $store.selectedSourceID,
                sources: store.sources,
                canSelectSources: !store.status.isCapturing,
                onWillOpen: store.refreshSources
            )
            .frame(width: 235, height: 26)

            Button {
                store.refreshSources()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("刷新 Google Meet、Chrome 和 Teams 音频源")
            .disabled(store.status.isCapturing)

            AlwaysOnTopButton(isOn: $store.alwaysOnTop)
        }
        .padding(.horizontal, 22)
        .frame(height: 66)
        .background(Color.black.opacity(0.18))
    }

    private var subtitles: some View {
        GeometryReader { proxy in
            if store.sourceLanguage.needsChineseTranslation {
                let dividerHeight: CGFloat = 30
                let availableHeight = max(1, proxy.size.height - dividerHeight)

                VStack(alignment: .leading, spacing: 0) {
                    SubtitleTextPanel(
                        language: store.sourceLanguage.liveLabel,
                        text: store.englishText,
                        color: .white,
                        fontSize: subtitleFontSize,
                        weight: .medium
                    )
                    .frame(height: availableHeight * splitFraction, alignment: .topLeading)

                    draggableDivider(totalHeight: availableHeight)
                        .frame(height: dividerHeight)

                    SubtitleTextPanel(
                        language: "简体中文 · 实时翻译",
                        text: store.translationError ?? store.chineseText,
                        color: Color(red: 0.43, green: 0.88, blue: 1),
                        fontSize: subtitleFontSize,
                        weight: .semibold
                    )
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                }
            } else {
                SubtitleTextPanel(
                    language: store.sourceLanguage.liveLabel,
                    text: store.englishText,
                    color: .white,
                    fontSize: subtitleFontSize,
                    weight: .medium
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private func draggableDivider(totalHeight: CGFloat) -> some View {
        ZStack {
            DividerDragSurface(
                fraction: $splitFraction,
                isHovered: $isDividerHovered,
                isDragging: $isDividerDragging,
                totalHeight: totalHeight
            )

            ZStack {
                Rectangle()
                    .fill(
                        Color.cyan.opacity(
                            isDividerDragging ? 0.16 : (isDividerHovered ? 0.08 : 0.001)
                        )
                    )
                Rectangle()
                    .fill(
                        isDividerHovered || isDividerDragging
                            ? Color.cyan.opacity(0.60)
                            : Color.white.opacity(0.12)
                    )
                    .frame(height: isDividerHovered || isDividerDragging ? 2 : 1)
                HStack(spacing: 7) {
                    Image(systemName: "chevron.up")
                    Capsule().frame(width: 58, height: 5)
                    Image(systemName: "chevron.down")
                }
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(
                    isDividerHovered || isDividerDragging
                        ? Color.cyan
                        : Color.white.opacity(0.52)
                )
            }
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .accessibilityElement()
        .accessibilityLabel("调整中英文字幕高度")
        .accessibilityValue("英文区域 \(Int((splitFraction * 100).rounded()))%")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: splitFraction = min(0.72, splitFraction + 0.05)
            case .decrement: splitFraction = max(0.28, splitFraction - 0.05)
            @unknown default: break
            }
        }
        .help("上下拖动，调整中英文字幕区域高度")
    }

    private var controlBar: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .shadow(color: statusColor.opacity(0.65), radius: 5)
            Text(store.status.label)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(2)

            Spacer()

            FontSizeControl(size: $subtitleFontSize)

            HistoryLimitControl(limit: $store.maximumTranscriptLines)

            OpacityControl(opacity: $backgroundOpacity)

            LanguageSelector(
                selection: $store.sourceLanguage,
                isDisabled: store.status.isCapturing
            )

            Button {
                Task { await store.toggleCapture() }
            } label: {
                Label(
                    store.status.isCapturing ? "停止字幕" : "开始字幕",
                    systemImage: store.status.isCapturing ? "stop.fill" : "waveform.and.mic"
                )
                .frame(minWidth: 92)
            }
            .buttonStyle(.borderedProminent)
            .tint(store.status.isCapturing ? .red : .cyan)
            .disabled(store.status == .finishing || store.status == .requestingPermission)
            .keyboardShortcut(.return, modifiers: [])
        }
        .padding(.horizontal, 22)
        .frame(minHeight: 64)
        .background(Color.black.opacity(0.22))
    }

    private var statusColor: Color {
        switch store.status {
        case .idle: return .gray
        case .requestingPermission, .finishing: return .yellow
        case .listening: return .green
        case .warning: return .orange
        case .failed: return .red
        }
    }

    private var bundledAppIcon: NSImage {
        guard let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let image = NSImage(contentsOf: url) else {
            return NSApplication.shared.applicationIconImage
        }
        return image
    }
}
