// AI-Author: Codex (OpenAI gpt-5.6-sol)
import Foundation

enum SourceLanguage: String, CaseIterable, Identifiable, Sendable {
    case english
    case korean
    case chinese

    var id: String { rawValue }

    var label: String {
        switch self {
        case .english: return "English"
        case .korean: return "한국어"
        case .chinese: return "中文"
        }
    }

    var liveLabel: String {
        switch self {
        case .english: return "ENGLISH · LIVE"
        case .korean: return "한국어 · LIVE"
        case .chinese: return "中文 · 实时转写"
        }
    }

    var speechLocaleIdentifier: String {
        switch self {
        case .english: return "en-US"
        case .korean: return "ko-KR"
        case .chinese: return "zh-CN"
        }
    }

    var translationLanguageIdentifier: String? {
        switch self {
        case .english: return "en"
        case .korean: return "ko"
        case .chinese: return nil
        }
    }

    var needsChineseTranslation: Bool { translationLanguageIdentifier != nil }
}
