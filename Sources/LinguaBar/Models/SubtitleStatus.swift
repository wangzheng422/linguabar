// AI-Author: Codex (OpenAI gpt-5.6-sol)
import Foundation

enum SubtitleStatus: Equatable {
    case idle
    case requestingPermission
    case listening
    case finishing
    case warning(String)
    case failed(String)

    var label: String {
        switch self {
        case .idle: return "准备就绪"
        case .requestingPermission: return "正在请求语音识别权限…"
        case .listening: return "正在监听会议音频"
        case .finishing: return "正在完成最后一句并保存…"
        case .warning(let message), .failed(let message): return message
        }
    }

    var isCapturing: Bool {
        if case .listening = self { return true }
        if case .warning = self { return true }
        if case .finishing = self { return true }
        return false
    }
}
