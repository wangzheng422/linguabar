import XCTest
@testable import LinguaBar

@MainActor
final class LiveTranslationChannelTests: XCTestCase {
    func testTenThousandUpdatesRetainOnlyLatestPendingRequest() async {
        let channel = LiveTranslationChannel()
        var events = channel.connect().makeAsyncIterator()
        for index in 0..<10_000 {
            channel.send(.init(text: "Synthetic \(index)", revision: UUID()))
        }
        _ = await events.next()
        XCTAssertEqual(channel.takeLatest()?.text, "Synthetic 9999")
        XCTAssertNil(channel.takeLatest())
    }

    func testClearDiscardsQueuedTextWithoutClosingConsumer() async {
        let channel = LiveTranslationChannel()
        var events = channel.connect().makeAsyncIterator()
        channel.send(.init(text: "old", revision: UUID()))
        channel.clear()
        _ = await events.next()
        XCTAssertNil(channel.takeLatest())
        channel.send(.init(text: "new", revision: UUID()))
        _ = await events.next()
        XCTAssertEqual(channel.takeLatest()?.text, "new")
    }

    func testReconnectionKeepsLatestAndFinishesPreviousConsumer() async {
        let channel = LiveTranslationChannel()
        var oldEvents = channel.connect().makeAsyncIterator()
        var newEvents = channel.connect().makeAsyncIterator()
        let old: Void? = await oldEvents.next()
        XCTAssertNil(old)
        channel.send(.init(text: "latest", revision: UUID()))
        _ = await newEvents.next()
        XCTAssertEqual(channel.takeLatest()?.text, "latest")
    }

    func testMailboxReleasesAndFinishesStream() async {
        var channel: LiveTranslationChannel? = LiveTranslationChannel()
        weak let weakChannel = channel
        var events = channel!.connect().makeAsyncIterator()
        channel = nil
        XCTAssertNil(weakChannel)
        let event: Void? = await events.next()
        XCTAssertNil(event)
    }

    func testCancelledInFlightRequestCanReconnectWithoutReplacingNewerInput() async {
        let channel = LiveTranslationChannel()
        let first = LiveTranslationChannel.Request(text: "first", revision: UUID())
        channel.send(first)
        XCTAssertEqual(channel.takeLatest(), first)
        channel.restoreIfEmpty(first)
        var events = channel.connect().makeAsyncIterator()
        _ = await events.next()
        XCTAssertEqual(channel.takeLatest(), first)
        let latest = LiveTranslationChannel.Request(text: "newer", revision: UUID())
        channel.send(latest)
        channel.restoreIfEmpty(first)
        XCTAssertEqual(channel.takeLatest(), latest)
    }

    func testInFlightRequestIsNotCancelledAndNextIsLatest() async {
        let channel = LiveTranslationChannel()
        var events = channel.connect().makeAsyncIterator()
        channel.send(.init(text: "first", revision: UUID()))
        _ = await events.next()
        let inFlight = channel.takeLatest()
        for index in 0..<100 { channel.send(.init(text: "next \(index)", revision: UUID())) }
        XCTAssertEqual(inFlight?.text, "first")
        XCTAssertFalse(Task.isCancelled)
        _ = await events.next()
        XCTAssertEqual(channel.takeLatest()?.text, "next 99")
    }

    func testLanguageSwitchAndClearRejectInFlightResults() async throws {
        let suite = "LiveTranslationTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SubtitleStore(defaults: defaults, sourceProvider: { [.system] }, automaticallyPrune: false)
        store.acceptTranscript("Synthetic sentence.", isFinal: true, epoch: store.recognitionEpoch)
        for _ in 0..<100 where store.translationInput.isEmpty {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let request = try XCTUnwrap(store.translationChannel(for: .english).takeLatest())
        XCTAssertTrue(store.isCurrentTranslation(request, language: .english))
        store.sourceLanguage = .korean
        XCTAssertFalse(store.isCurrentTranslation(request, language: .english))
        store.acceptTranslation("old", for: request.text, revision: request.revision)
        XCTAssertNotEqual(store.chineseText, "old")
        XCTAssertNil(store.translationChannel(for: .english).takeLatest())
        store.sourceLanguage = .chinese
        store.acceptTranscript("合成中文。", isFinal: true, epoch: store.recognitionEpoch)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(store.translationInput.isEmpty)
        XCTAssertNil(store.translationChannel(for: .korean).takeLatest())
        store.clearTranscript()
        store.acceptTranslation("old", for: request.text, revision: request.revision)
        XCTAssertEqual(store.chineseText, "")
    }
}
