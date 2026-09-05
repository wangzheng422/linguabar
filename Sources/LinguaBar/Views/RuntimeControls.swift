// AI-Author: Codex (OpenAI gpt-5.6-sol)
import SwiftUI

struct AlwaysOnTopButton: View {
    @Binding var isOn: Bool
    @State private var isHovered = false

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Image(systemName: isOn ? "pin.fill" : "pin")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isOn ? Color.cyan : Color.white.opacity(0.86))
                .frame(width: 34, height: 30)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(
                            isOn
                                ? Color.cyan.opacity(isHovered ? 0.26 : 0.18)
                                : Color.white.opacity(isHovered ? 0.16 : 0.09)
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(
                            isOn
                                ? Color.cyan.opacity(0.78)
                                : Color.white.opacity(isHovered ? 0.38 : 0.24),
                            lineWidth: 1
                        )
                }
                .shadow(
                    color: isOn ? Color.cyan.opacity(0.22) : .clear,
                    radius: 5
                )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .help(isOn ? "取消置顶" : "保持字幕置顶")
        .accessibilityLabel("置顶")
        .accessibilityValue(isOn ? "已开启" : "已关闭")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

struct LanguageSelector: View {
    @Binding var selection: SourceLanguage
    let isDisabled: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text("源语言")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))
                .padding(.trailing, 2)

            ForEach(SourceLanguage.allCases) { language in
                Button {
                    selection = language
                } label: {
                    Text(language.label)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(
                            selection == language ? Color.white : Color.white.opacity(0.78)
                        )
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(
                                    selection == language
                                        ? Color.cyan.opacity(0.30)
                                        : Color.white.opacity(0.09)
                                )
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(
                                    selection == language
                                        ? Color.cyan.opacity(0.85)
                                        : Color.white.opacity(0.18),
                                    lineWidth: 1
                                )
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("源语言：\(language.label)")
                .accessibilityAddTraits(selection == language ? .isSelected : [])
            }
        }
        .opacity(isDisabled ? 0.55 : 1)
        .disabled(isDisabled)
    }
}

struct FontSizeControl: View {
    @Binding var size: Double

    var body: some View {
        HStack(spacing: 3) {
            Button("A−") { size = max(18, size - 2) }
                .disabled(size <= 18)
                .help("缩小字幕")
            Text("\(Int(size))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.72))
                .frame(width: 24)
            Button("A+") { size = min(56, size + 2) }
                .disabled(size >= 56)
                .help("放大字幕")
        }
        .buttonStyle(CompactControlButtonStyle())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("字幕字号")
    }
}

struct OpacityControl: View {
    @Binding var opacity: Double

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "circle.lefthalf.filled")
                .foregroundStyle(.white.opacity(0.72))
                .accessibilityHidden(true)
            Slider(value: $opacity, in: 0.30...0.96, step: 0.02)
                .tint(.cyan)
                .frame(width: 88)
            Text("\(Int((opacity * 100).rounded()))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.72))
                .frame(width: 34, alignment: .trailing)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("窗口背景透明度")
    }
}

struct HistoryLimitControl: View {
    @Binding var limit: Int

    var body: some View {
        HStack(spacing: 3) {
            Button("−") { limit = max(25, limit - 25) }
                .disabled(limit <= 25)
                .help("减少保留的字幕行数")
            Text("\(limit)行")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.72))
                .frame(width: 44)
            Button("+") { limit = min(500, limit + 25) }
                .disabled(limit >= 500)
                .help("增加保留的字幕行数")
        }
        .buttonStyle(CompactControlButtonStyle())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("字幕历史上限")
    }
}

private struct CompactControlButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.bold))
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.65 : 0.90))
            .padding(.horizontal, 7)
            .frame(height: 27)
            .background(Color.white.opacity(configuration.isPressed ? 0.16 : 0.09))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
