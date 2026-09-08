/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
import CoreData
@testable import Glasstual
import Testing

/// Holds the first history read open until the test lets it answer. Every read
/// after it returns an empty page, so a controller that starts a second one
/// finishes without help.
private actor FirstFetchGate {
	private var fetches = 0
	private var parked: CheckedContinuation<HistoricLogFetchOutcome, Never>?
	private var observers: [CheckedContinuation<Void, Never>] = []

	var fetchCount: Int {
		fetches
	}

	func fetch() async -> HistoricLogFetchOutcome {
		fetches += 1
		guard fetches == 1 else { return .page([]) }
		for observer in observers {
			observer.resume()
		}
		observers.removeAll()
		return await withCheckedContinuation { parked = $0 }
	}

	func waitUntilRequested() async {
		guard fetches == 0 else { return }
		await withCheckedContinuation { observers.append($0) }
	}

	func release() {
		parked?.resume(returning: .page([]))
		parked = nil
	}
}

@MainActor
@Suite("Controller history latch", .serialized)
struct LogControllerHistoryLatchTests {
	private func window() -> MainWindow {
		MainWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
		           styleMask: .borderless, backing: .buffered, defer: false)
	}

	/** The flag that says "a reload is under way" is only cleared by the job
	 that finishes the replay. A job that never applies — because clearing the
	 view retired the generation it rendered for — has to leave the flag down
	 anyway, or the view refuses every later reload and parks its deferred
	 prepends for good. */
	@Test("A history job dropped mid-flight still leaves the view able to reload",
	      .timeLimit(.minutes(1)))
	func droppedHistoryJobDoesNotLatchTheReload() async {
		let lazy = Preferences.Logging.loadHistoryLazily.value
		let reload = Preferences.Logging.reloadScrollbackOnLaunch.value
		Preferences.Logging.loadHistoryLazily.value = false
		Preferences.Logging.reloadScrollbackOnLaunch.value = true
		defer {
			Preferences.Logging.loadHistoryLazily.value = lazy
			Preferences.Logging.reloadScrollbackOnLaunch.value = reload
		}
		let client = IRCClient(config: ClientConfig())
		let controller = LogController(client: client, in: window())
		defer { controller.tearDown(.permanentRemoval) }
		let gate = FirstFetchGate()
		controller.historyPageFetcher = { _ in await gate.fetch() }

		controller.ensureBackingView()
		await gate.waitUntilRequested()
		#expect(controller.reloadingHistory)

		/* Clearing retires the generation the parked read is rendering for, so
		 its output is dropped when it finally arrives. */
		controller.clear()
		await gate.release()
		await controller.drainRenderJobs()

		#expect(controller.reloadingHistory == false)
		#expect(controller.historyLoaded)
		#expect(await gate.fetchCount == 2)
	}

	/** The controller holds its client weakly, so a view can outlive the item
	 its lines belong to. A reload it cannot even submit must leave the flag
	 down: closing it would refuse every later reload for good. */
	@Test("A reload with nothing to attribute the lines to does not latch the flag")
	func reloadWithoutAnItemDoesNotLatchTheFlag() async throws {
		let lazy = Preferences.Logging.loadHistoryLazily.value
		Preferences.Logging.loadHistoryLazily.value = false
		defer { Preferences.Logging.loadHistoryLazily.value = lazy }
		var client: IRCClient? = IRCClient(config: ClientConfig())
		let controller = try LogController(client: #require(client), in: window())
		defer { controller.tearDown(.permanentRemoval) }
		controller.historyPageFetcher = { _ in .failed(.unavailable) }

		controller.ensureBackingView()
		await controller.drainRenderJobs()
		#expect(controller.historyLoaded == false)
		#expect(controller.reloadingHistory == false)

		weak let retiredClient = client
		client = nil
		try #require(retiredClient == nil)
		#expect(controller.associatedItem == nil)

		controller.notifyDidBecomeVisible()

		#expect(controller.reloadingHistory == false)
	}

	/** A retired view can no longer read history into a transcript, so Retry
	 has one job left: reopen the store. It has to do that whichever failure the
	 banner is showing — the one this view recorded, or the store's own. */
	@Test("Retry on a retired view repairs the store and clears the view's own failure")
	func retryAfterRetirementRepairsTheStore() async throws {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
			UUID().uuidString, isDirectory: true
		)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		let store = HistoricLogStore(filenameStore: HistoricLogFilenameFixture())
		let historyClient = HistoricLogClient(
			store: store,
			databaseDirectory: { directory.path },
			reportFailure: { Issue.record("\($0)") }
		)
		let client = IRCClient(config: ClientConfig())
		let controller = LogController(
			client: client, in: window(), inlineImageLoader: NativeInlineImageLoader(),
			historicLog: LogControllerHistoricLogFile(client: historyClient)
		)
		controller.historyPageFetcher = { _ in .page([]) }
		controller.historyLoadFailure = .unavailable
		#expect(controller.historyRecovery.localMessage != nil)
		#expect(controller.historyStorageRecovery.localMessage == nil)

		controller.tearDown(.preservingRemoval)
		controller.retryHistory()
		#expect(controller.historyRecovery.isRetrying)
		await controller.historyRetryTask?.value

		#expect(controller.historyRecovery.isRetrying == false)
		#expect(controller.historyLoadFailure == nil)
		#expect(controller.historyRecovery.localMessage == nil)
		await historyClient.prepareForTermination()
	}

	/// The banner offers Retry Server History only while both sides can ask
	/// for another page: the view has no request in flight and is not retired,
	/// and the client would admit a request for that channel. A server console
	/// has no channel to ask about, so it never offers the button.
	@Test("Retry Server History is offered only while the view can ask again")
	func serverHistoryRetryAvailability() {
		let client = GLTTestClient()
		client.enableCapability(.batch)
		client.enableCapability(.serverTime)
		client.enableCapability(.messageTags)
		client.enableCapability(.chatHistory)
		client.isLoggedIn = true
		let channel = IRCChannel(config: ChannelConfig(channelName: "#retry"))
		channel.associatedClient = client
		channel.activate()
		let window = window()
		let controller = LogController(channel: channel, in: window)
		defer { controller.tearDown(.permanentRemoval) }

		#expect(controller.serverHistoryRetryIsAvailable)

		controller.serverHistoryRequest = ServerHistoryRequest(
			id: UUID(), before: Date(timeIntervalSince1970: 100), oldestLineNumber: "line"
		)
		#expect(controller.serverHistoryRetryIsAvailable == false)
		controller.serverHistoryRequest = nil
		#expect(controller.serverHistoryRetryIsAvailable)

		client.isLoggedIn = false
		#expect(controller.serverHistoryRetryIsAvailable == false)
		client.isLoggedIn = true

		let console = LogController(client: client, in: window)
		defer { console.tearDown(.permanentRemoval) }
		#expect(console.serverHistoryRetryIsAvailable == false)

		controller.tearDown(.preservingRemoval)
		#expect(controller.serverHistoryRetryIsAvailable == false)
	}
}
