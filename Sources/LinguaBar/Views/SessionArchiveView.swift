import AppKit
import SwiftUI
import Translation

struct SessionArchiveView: View {
    @ObservedObject var archive: SessionArchiveStore

    var body: some View {
        HStack(spacing: 8) {
            if archive.pendingCount > 0 {
                ProgressView().controlSize(.small)
            }
            Text(archive.failureCount > 0
                 ? "\(archive.failureCount) 场保存未完成 · \(archive.message)"
                 : archive.message)
                .font(.caption)
                .lineLimit(1)
                .help(archive.message)
            Spacer(minLength: 8)
            if archive.failureCount > 0 {
                Button("重试保存") { archive.retryFailures() }
            }
            Button {
                if let file = archive.lastOriginalURL {
                    NSWorkspace.shared.activateFileViewerSelecting([file])
                } else {
                    NSWorkspace.shared.open(archive.directory)
                }
            } label: {
                Label("保存目录", systemImage: "folder")
            }
            .disabled(archive.lastOriginalURL == nil)
            .help("文稿/LinguaBar；清空按钮仅清屏，不删除本场归档")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(archive.failureCount > 0 ? Color.orange : Color.white.opacity(0.7))
        .padding(.horizontal, 22)
        .padding(.vertical, 7)
        .background(Color.black.opacity(0.18))
        .background {
            if let request = archive.request {
                ArchiveTranslationTask(request: request, archive: archive).id(request.id)
            }
        }
    }
}

private struct ArchiveTranslationTask: View {
    let request: SessionArchiveStore.TranslationRequest
    let archive: SessionArchiveStore

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .translationTask(source: Locale.Language(identifier: request.sourceIdentifier),
                             target: Locale.Language(identifier: request.targetIdentifier)) { session in
                do {
                    var translations: [String] = []
                    for chunk in request.chunks {
                        try Task.checkCancellation()
                        let result = try await session.translate(chunk)
                        translations.append(result.targetText)
                    }
                    archive.complete(request.id, translations: translations)
                } catch {
                    archive.fail(request.id, message: error.localizedDescription)
                }
            }
    }
}
