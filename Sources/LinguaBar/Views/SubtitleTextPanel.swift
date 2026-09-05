// AI-Author: Codex (OpenAI gpt-5.6-sol)
import SwiftUI

struct SubtitleTextPanel: View {
    let language: String
    let text: String
    let color: Color
    let fontSize: Double
    let weight: Font.Weight

    private let bottomAnchor = "subtitle-bottom"
    @State private var followsLive = true

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(language)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(color.opacity(0.52))

            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(text)
                            .font(.system(size: fontSize, weight: weight, design: .rounded))
                            .foregroundStyle(color)
                            .lineSpacing(3)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Color.clear
                            .frame(height: 1)
                            .id(bottomAnchor)
                    }
                }
                .background(ScrollViewAppearanceConfigurator())
                .scrollIndicators(.automatic)
                .defaultScrollAnchor(.bottom)
                .onScrollGeometryChange(for: SubtitleScrollMetrics.self) { geometry in
                    SubtitleScrollMetrics(
                        visibleMinY: geometry.visibleRect.minY,
                        visibleMaxY: geometry.visibleRect.maxY,
                        contentHeight: geometry.contentSize.height,
                        containerHeight: geometry.containerSize.height
                    )
                } action: { previous, current in
                    followsLive = LiveScrollPolicy.shouldFollow(
                        wasFollowing: followsLive,
                        previous: previous,
                        current: current
                    )
                }
                .onAppear {
                    scrollToBottom(using: proxy)
                }
                .onChange(of: text) { _, _ in
                    guard followsLive else { return }
                    scrollToBottom(using: proxy)
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func scrollToBottom(using proxy: ScrollViewProxy) {
        Task { @MainActor in
            await Task.yield()
            proxy.scrollTo(bottomAnchor, anchor: .bottom)
        }
    }
}
