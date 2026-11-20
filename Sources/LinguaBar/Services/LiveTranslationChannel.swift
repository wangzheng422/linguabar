import Foundation

/// A latest-only mailbox. Updating subtitles never cancels an in-flight translation.
@MainActor
final class LiveTranslationChannel {
    struct Request: Equatable {
        let text: String
        let revision: UUID
    }

    private var pending: Request?
    private var continuation: AsyncStream<Void>.Continuation?

    func send(_ request: Request) {
        pending = request
        continuation?.yield(())
    }

    func clear() {
        pending = nil
    }

    func restoreIfEmpty(_ request: Request) {
        guard pending == nil else { return }
        send(request)
    }

    func takeLatest() -> Request? {
        defer { pending = nil }
        return pending
    }

    /// A view can reconnect after disappearing; cancellation must not permanently
    /// close the mailbox. Notifications carry no transcript payload.
    func connect() -> AsyncStream<Void> {
        continuation?.finish()
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.continuation = continuation
        if pending != nil { continuation.yield(()) }
        return stream
    }

    deinit { continuation?.finish() }
}
