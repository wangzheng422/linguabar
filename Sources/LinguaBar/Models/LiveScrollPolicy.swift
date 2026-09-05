// AI-Author: Codex (OpenAI gpt-5.6-sol)
import CoreGraphics

struct SubtitleScrollMetrics: Equatable {
    let visibleMinY: CGFloat
    let visibleMaxY: CGFloat
    let contentHeight: CGFloat
    let containerHeight: CGFloat

    static let zero = SubtitleScrollMetrics(
        visibleMinY: 0,
        visibleMaxY: 0,
        contentHeight: 0,
        containerHeight: 0
    )

    var isScrollable: Bool { contentHeight > containerHeight + 1 }
    var isAtBottom: Bool { !isScrollable || visibleMaxY >= contentHeight - 10 }
}

enum LiveScrollPolicy {
    static func shouldFollow(
        wasFollowing: Bool,
        previous: SubtitleScrollMetrics,
        current: SubtitleScrollMetrics
    ) -> Bool {
        if current.isAtBottom { return true }
        if current.visibleMinY < previous.visibleMinY - 1 { return false }
        return wasFollowing
    }
}
