/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import Testing

private actor TranscriptPageGate {
	private var started = false
	private var observers: [CheckedContinuation<Void, Never>] = []
	private var fetch: CheckedContinuation<HistoricLogFetchOutcome, Never>?

	func suspend() async -> HistoricLogFetchOutcome {
		started = true
		for observer in observers {
			observer.resume()
		}
		observers.removeAll()
		return await withCheckedContinuation { fetch = $0 }
	}

	func waitUntilRequested() async {
		guard !started else { return }
		await withCheckedContinuation { observers.append($0) }
	}

	func finish(_ entries: [HistoricLogEntry]) {
		fetch?.resume(returning: .page(entries))
		fetch = nil
	}
}

@MainActor
@Suite("Controller transcript application", .serialized)
struct LogControllerTranscriptApplicationTests {
	private func line(_ body: String, date: TimeInterval = 100) -> LogLine {
		var line = LogLine()
		line.messageBody = body
		line.lineType = .privateMessage
		line.nickname = "alice"
		line.receivedAt = Date(timeIntervalSince1970: date)
		line.messageIdentifier = UUID().uuidString
		return line
	}

	private func window() -> MainWindow {
		MainWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
		           styleMask: .borderless, backing: .buffered, defer: false)
	}

	@Test("Jump to Present resumes following from either the present or historical text", arguments: [false, true])
	func jumpToPresentFollowsSubsequentPrints(fromHistory: Bool) async throws {
		let lazy = Preferences.Logging.loadHistoryLazily.value
		Preferences.Logging.loadHistoryLazily.value = false
		defer { Preferences.Logging.loadHistoryLazily.value = lazy }
		let client = IRCClient(config: ClientConfig())
		let window = window()
		let controller = LogController(client: client, in: window)
		defer { controller.tearDown(.permanentRemoval) }
		controller.historyPageFetcher = { _ in .page([]) }
		let view = controller.ensureBackingView()
		view.view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
		window.contentView = view.view
		await controller.drainRenderJobs()
		view.setBufferLimit(1000)
		let first = line("first message", date: 0)
		controller.print(first)
		for index in 1 ..< 100 {
			controller.print(line("message \(index)", date: Double(index)))
		}
		await controller.drainRenderJobs()
		view.view.layoutSubtreeIfNeeded()
		controller.moveToBottom()
		let scroll = try #require(view.view.subviews.compactMap { $0 as? NSScrollView }.first)
		let text = try #require(scroll.documentView as? NSTextView)
		let layout = try #require(text.textLayoutManager)
		try #require(text.frame.height > scroll.contentView.bounds.height)
		if fromHistory {
			controller.jump(toLine: first.uniqueIdentifier) { #expect($0) }
			#expect(scroll.contentView.bounds.maxY < text.frame.maxY - 40)
		}
		controller.jumpToPresent()
		let oldHeight = text.frame.height
		#expect(abs(scroll.contentView.bounds.maxY - scroll.contentInsets.bottom - text.frame.maxY) < 2)
		for index in 100 ..< 140 {
			controller.print(line("new message \(index)", date: Double(index)))
		}
		await controller.drainRenderJobs()
		view.view.layoutSubtreeIfNeeded()
		layout.ensureLayout(for: layout.documentRange)
		text.sizeToFit()
		#expect(text.frame.height > oldHeight)
		#expect(abs(scroll.contentView.bounds.maxY - scroll.contentInsets.bottom - text.frame.maxY) < 2)
		// Ordinary history navigation still suspends following.
		controller.jump(toLine: first.uniqueIdentifier) { #expect($0) }
		controller.print(line("after history navigation", date: 150))
		await controller.drainRenderJobs()
		layout.ensureLayout(for: layout.documentRange)
		text.sizeToFit()
		#expect(scroll.contentView.bounds.maxY < text.frame.maxY - 40)
	}

	@Test(
		"Late older pages cannot decode into the duplicate index after clear or destruction",
		arguments: [false, true]
	)
	func staleOlderPageCannotMutateController(destroy: Bool) async throws {
		let lazy = Preferences.Logging.loadHistoryLazily.value
		Preferences.Logging.loadHistoryLazily.value = false
		defer { Preferences.Logging.loadHistoryLazily.value = lazy }
		let client = IRCClient(config: ClientConfig())
		let window = window()
		let controller = LogController(client: client, in: window)
		let gate = TranscriptPageGate()
		controller.historyPageFetcher = { request in
			if case .before = request.kind {
				return await gate.suspend()
			}
			return .page([])
		}
		let view = controller.ensureBackingView()
		await controller.drainRenderJobs()
		controller.print(line("live"))
		await controller.drainRenderJobs()
		controller.loadOlderHistory()
		await gate.waitUntilRequested()
		let stale = line("stale", date: 1)
		let retiredFetch = controller.olderHistoryTask
		let entry = stale.historicEntry(forView: controller.uniqueIdentifier)
		if destroy {
			controller.tearDown(.permanentRemoval)
		} else {
			controller.clear()
		}
		await gate.finish([entry])
		await retiredFetch?.value
		await controller.drainRenderJobs()
		#expect(view.displayedLines.allSatisfy { $0.lineNumber != stale.uniqueIdentifier })
		#expect(try LogControllerHistoricLogFile.shared().containsMessageIdentifier(
			#require(stale.messageIdentifier), forView: controller.uniqueIdentifier
		) == false)
		if !destroy {
			controller.tearDown(.permanentRemoval)
		}
	}

	@Test("Initial replay merges archived reactions with deltas and retains live prints")
	func initialReplayKeepsLiveState() async throws {
		let lazy = Preferences.Logging.loadHistoryLazily.value
		let reload = Preferences.Logging.reloadScrollbackOnLaunch.value
		Preferences.Logging.loadHistoryLazily.value = false
		Preferences.Logging.reloadScrollbackOnLaunch.value = true
		defer {
			Preferences.Logging.loadHistoryLazily.value = lazy
			Preferences.Logging.reloadScrollbackOnLaunch.value = reload
		}
		let client = IRCClient(config: ClientConfig())
		let window = window()
		let controller = LogController(client: client, in: window)
		defer { controller.tearDown(.permanentRemoval) }
		let gate = TranscriptPageGate()
		controller.historyPageFetcher = { _ in await gate.suspend() }
		let view = controller.ensureBackingView()
		await gate.waitUntilRequested()
		var archived = line("archived")
		archived.reactions = ["+1": ["alice"]]
		let identifier = try #require(archived.messageIdentifier)
		controller.noteReaction("+1", fromNickname: "bob", toMessageIdentifier: identifier)
		let live = line("live", date: 200)
		let (completed, completion) = AsyncStream<Void>.makeStream()
		controller.print(live) { _ in
			completion.yield()
			completion.finish()
		}
		for await _ in completed {
			break
		}
		await gate.finish([live.historicEntry(forView: controller.uniqueIdentifier),
		                   archived.historicEntry(forView: controller.uniqueIdentifier)])
		await controller.drainRenderJobs()
		#expect(view.displayedLines.map(\.lineNumber) == [archived.uniqueIdentifier, live.uniqueIdentifier])
		#expect(view.displayedLines.first?.reactions == ["+1": ["alice", "bob"]])
		controller.noteReaction("+1", fromNickname: "carol", toMessageIdentifier: identifier)
		await controller.drainRenderJobs()
		#expect(view.displayedLines.first?.reactions == ["+1": ["alice", "bob", "carol"]])
		#expect(controller.oldestLineNumber == archived.uniqueIdentifier)
		#expect(controller.newestLineNumber == live.uniqueIdentifier)
	}

	@Test("Trimming during an older fetch cannot create a skipped interval")
	func movedDisplayedCursorRejectsPage() async throws {
		let lazy = Preferences.Logging.loadHistoryLazily.value
		Preferences.Logging.loadHistoryLazily.value = false
		defer { Preferences.Logging.loadHistoryLazily.value = lazy }
		let client = IRCClient(config: ClientConfig())
		let window = window()
		let controller = LogController(client: client, in: window)
		defer { controller.tearDown(.permanentRemoval) }
		controller.historyPageFetcher = { _ in .page([]) }
		let view = controller.ensureBackingView()
		await controller.drainRenderJobs()
		view.setBufferLimit(1)
		let previous = line("previous", date: 100)
		controller.print(previous)
		await controller.drainRenderJobs()
		let gate = TranscriptPageGate()
		controller.historyPageFetcher = { _ in await gate.suspend() }
		controller.loadOlderHistory()
		await gate.waitUntilRequested()
		let current = line("current", date: 200)
		let (completed, completion) = AsyncStream<Void>.makeStream()
		controller.print(current) { _ in
			completion.yield()
			completion.finish()
		}
		for await _ in completed {
			break
		}
		// The edit transaction must finish before the fetch resumes.
		view.setBufferLimit(1)
		let stale = line("stale", date: 1)
		await gate.finish([stale.historicEntry(forView: controller.uniqueIdentifier)])
		await controller.drainRenderJobs()
		#expect(view.displayedLines.map(\.lineNumber) == [current.uniqueIdentifier])
		#expect(try !LogControllerHistoricLogFile.shared().containsMessageIdentifier(
			#require(stale.messageIdentifier), forView: controller.uniqueIdentifier
		))
		let currentIdentifier = current.uniqueIdentifier
		let adjacentEntry = previous.historicEntry(forView: controller.uniqueIdentifier)
		controller.historyPageFetcher = { request in
			if case let .before(identifier, _, _) = request.kind {
				#expect(identifier == currentIdentifier)
			}
			return .page([adjacentEntry])
		}
		controller.loadOlderHistory()
		await controller.drainRenderJobs()
		#expect(view.displayedLines.map(\.lineNumber) == [previous.uniqueIdentifier, current.uniqueIdentifier])
	}

	@Test("A failed older fetch leaves its cursor retryable and merges reactions on prepend")
	func failedPageDoesNotAdvanceCursor() async throws {
		let lazy = Preferences.Logging.loadHistoryLazily.value
		Preferences.Logging.loadHistoryLazily.value = false
		defer { Preferences.Logging.loadHistoryLazily.value = lazy }
		let client = IRCClient(config: ClientConfig())
		let window = window()
		let controller = LogController(client: client, in: window)
		defer { controller.tearDown(.permanentRemoval) }
		controller.historyPageFetcher = { _ in .page([]) }
		let view = controller.ensureBackingView()
		await controller.drainRenderJobs()
		let live = line("live")
		controller.print(live)
		await controller.drainRenderJobs()
		controller.historyPageFetcher = { _ in .failed(.read("Injected read failure")) }
		controller.loadOlderHistory()
		await controller.drainRenderJobs()
		#expect(controller.olderHistoryFailed)
		#expect(controller.olderHistoryFailure == .read("Injected read failure"))
		#expect(controller.oldestLineNumber == live.uniqueIdentifier)
		var older = line("older", date: 1)
		older.reactions = ["+1": ["alice"]]
		let identifier = try #require(older.messageIdentifier)
		let entry = older.historicEntry(forView: controller.uniqueIdentifier)
		controller.noteReaction("+1", fromNickname: "bob", toMessageIdentifier: identifier)
		controller.historyPageFetcher = { _ in .page([entry]) }
		controller.loadOlderHistory()
		await controller.drainRenderJobs()
		#expect(!controller.olderHistoryFailed)
		#expect(controller.oldestLineNumber == older.uniqueIdentifier)
		#expect(view.displayedLines.first?.reactions == ["+1": ["alice", "bob"]])
	}

	@Test("Batched production prints preserve completion order and visible bounds after trimming")
	func completionOrderSurvivesBatchingAndTrim() async {
		let lazy = Preferences.Logging.loadHistoryLazily.value
		Preferences.Logging.loadHistoryLazily.value = false
		defer { Preferences.Logging.loadHistoryLazily.value = lazy }
		let client = IRCClient(config: ClientConfig())
		let window = window()
		let controller = LogController(client: client, in: window)
		defer { controller.tearDown(.permanentRemoval) }
		controller.historyPageFetcher = { _ in .page([]) }
		let view = controller.ensureBackingView()
		await controller.drainRenderJobs()
		view.setBufferLimit(5)
		let lines = (0 ..< 80).map { line("message \($0)", date: Double($0)) }
		var completed: [String] = []
		for line in lines {
			controller.print(line) { context in
				#expect(view.displayedLines.contains { $0.lineNumber == context.lineNumber })
				completed.append(context.lineNumber)
			}
		}
		await controller.drainRenderJobs()
		#expect(completed == lines.map(\.uniqueIdentifier))
		#expect(view.displayedLines.map(\.lineNumber) == lines.suffix(5).map(\.uniqueIdentifier))
		#expect(controller.numberOfLines == 5)
		#expect(controller.oldestLineNumber == lines[75].uniqueIdentifier)
		#expect(controller.newestLineNumber == lines.last?.uniqueIdentifier)
	}

	@Test(
		"Empty wire history pages complete; only labeled pages prove exhaustion",
		arguments: [false, true],
		[false, true]
	)
	func emptyServerPageCompletes(labeled: Bool, nested: Bool) async throws {
		try await withServerHistoryController(labeled: labeled) { client, channel, controller in
			let socket = try #require(client.socket)
			let request = try #require(controller.serverHistoryRequest)
			let label = try outgoingHistoryLabel(on: client)
			let tags = label.map { "@label=\($0) " } ?? ""
			if nested {
				client.ircConnection(socket, didReceiveData: "\(tags)BATCH +wrapper labeled-response")
				client.ircConnection(socket, didReceiveData: "@batch=wrapper BATCH +page chathistory \(channel.name)")
				client.ircConnection(socket, didReceiveData: "BATCH -page")
				#expect(controller.serverHistoryRequest == request)
				client.ircConnection(socket, didReceiveData: "BATCH -wrapper")
			} else {
				client.ircConnection(socket, didReceiveData: "\(tags)BATCH +page chathistory \(channel.name)")
				client.ircConnection(socket, didReceiveData: "BATCH -page")
			}
			#expect(controller.serverHistoryRequest == nil)
			#expect(controller.serverHistoryExhaustedBefore == (labeled ? request.before : nil))
			#expect(!controller.serverHistoryFailed)
			#expect(client.serverHistoryRequests.isEmpty)
			let count = client.sentLines.count
			controller.loadOlderHistory()
			await controller.drainRenderJobs()
			#expect(
				client.sentLines.count == count,
				"An empty or duplicate-only response must not create a scroll-triggered request loop"
			)
			controller.retryServerHistory()
			#expect(controller.serverHistoryRequest?.id != request.id)
			#expect(controller.serverHistoryRequest != nil)
		}
	}

	@Test("Wire history failures are retryable and cannot exhaust the transcript", arguments: [false, true])
	func failedServerPageCanRetry(labeled: Bool) async throws {
		try await withServerHistoryController(labeled: labeled) { client, channel, controller in
			let socket = try #require(client.socket)
			let first = try #require(controller.serverHistoryRequest)
			let label = try outgoingHistoryLabel(on: client)
			let tags = label.map { "@label=\($0) " } ?? ""
			let failure = "\(tags)FAIL CHATHISTORY TEMPORARILY_UNAVAILABLE BEFORE \(channel.name) :Retry later"
			client.ircConnection(socket, didReceiveData: failure)
			#expect(controller.serverHistoryFailed)
			#expect(controller.serverHistoryExhaustedBefore == nil)
			#expect(controller.serverHistoryRequest == nil)
			#expect(client.chatHistoryIsAvailable(for: channel))
			controller.loadOlderHistory()
			await controller.drainRenderJobs()
			let retry = try #require(controller.serverHistoryRequest)
			#expect(retry.id != first.id)
			#expect(!controller.serverHistoryFailed)
			if labeled {
				client.ircConnection(socket, didReceiveData: failure)
				#expect(controller.serverHistoryRequest == retry)
				#expect(!controller.serverHistoryFailed)
			}
		}
	}

	@Test("A labeled batch admitted before clear cannot complete or prepend into the next generation")
	func retiredServerPageCannotMutateController() async throws {
		try await withServerHistoryController(labeled: true) { client, channel, controller in
			let socket = try #require(client.socket)
			let label = try #require(try outgoingHistoryLabel(on: client))
			let identifier = UUID().uuidString
			client.ircConnection(socket, didReceiveData: "@label=\(label) BATCH +old chathistory \(channel.name)")
			client.ircConnection(socket, didReceiveData:
				"@batch=old;msgid=\(identifier);time=1970-01-01T00:00:50.000Z :alice!u@h PRIVMSG \(channel.name) :retired page")
			controller.clear()
			await controller.drainRenderJobs()
			controller.print(line("new generation", date: 200))
			await controller.drainRenderJobs()
			controller.loadOlderHistory()
			await controller.drainRenderJobs()
			let current = try #require(controller.serverHistoryRequest)
			client.ircConnection(socket, didReceiveData: "BATCH -old")
			await controller.drainRenderJobs()
			#expect(controller.serverHistoryRequest == current)
			#expect(!controller.serverHistoryFailed)
			#expect(controller.serverHistoryExhaustedBefore == nil)
			#expect(controller.backingView?.displayedLines.map(\.receivedAt) == [Date(timeIntervalSince1970: 200)])
			#expect(!LogControllerHistoricLogFile.shared().containsMessageIdentifier(
				identifier,
				forView: channel.uniqueIdentifier
			))
		}
	}

	@Test("An uncorrelated empty batch cannot complete a labeled request")
	func unrelatedEmptyBatchDoesNotExhaust() async throws {
		try await withServerHistoryController(labeled: true) { client, channel, controller in
			let socket = try #require(client.socket)
			let request = try #require(controller.serverHistoryRequest)
			client.ircConnection(socket, didReceiveData: "BATCH +unsolicited chathistory \(channel.name)")
			client.ircConnection(socket, didReceiveData: "BATCH -unsolicited")
			#expect(controller.serverHistoryRequest == request)
			#expect(controller.serverHistoryExhaustedBefore == nil)
		}
	}

	@Test("A duplicate-only wire page is not mistaken for an empty server page")
	func duplicateOnlyServerPageDoesNotExhaust() async throws {
		try await withServerHistoryController(labeled: true) { client, channel, controller in
			let socket = try #require(client.socket)
			let label = try #require(try outgoingHistoryLabel(on: client))
			let duplicate = line("already stored", date: 50)
			let identifier = try #require(duplicate.messageIdentifier)
			LogControllerHistoricLogFile.shared().indexLogLines([duplicate], forView: channel.uniqueIdentifier)
			for wire in [
				"@label=\(label) BATCH +page chathistory \(channel.name)",
				"@batch=page;msgid=\(identifier);time=1970-01-01T00:00:50.000Z :alice!u@h PRIVMSG \(channel.name) :already stored",
				"BATCH -page",
			] {
				client.ircConnection(socket, didReceiveData: wire)
			}
			#expect(controller.serverHistoryRequest == nil)
			#expect(controller.serverHistoryExhaustedBefore == nil)
			#expect(!controller.serverHistoryFailed)
		}
	}

	@Test("Nested labeled wire history reaches the controller prepend path")
	func nestedServerPagePrepends() async throws {
		try await withServerHistoryController(labeled: true) { client, channel, controller in
			let socket = try #require(client.socket)
			let label = try #require(try outgoingHistoryLabel(on: client))
			let identifier = UUID().uuidString
			for wire in [
				"@label=\(label) BATCH +wrapper labeled-response",
				"@batch=wrapper BATCH +page chathistory \(channel.name)",
				"@batch=page;msgid=\(identifier);time=1970-01-01T00:00:50.000Z :alice!u@h PRIVMSG \(channel.name) :older",
				"BATCH -page", "BATCH -wrapper",
			] {
				client.ircConnection(socket, didReceiveData: wire)
			}
			await controller.drainRenderJobs()
			#expect(controller.serverHistoryRequest == nil)
			#expect(controller.serverHistoryExhaustedBefore == nil)
			#expect(controller.backingView?.displayedLines.map(\.receivedAt) == [50, 100]
				.map { Date(timeIntervalSince1970: $0) })
			#expect(LogControllerHistoricLogFile.shared().containsMessageIdentifier(
				identifier,
				forView: channel.uniqueIdentifier
			))
			let oldest = try #require(controller.oldestLineNumber)
			let fetch = HistoricLogFetchRequest(
				viewIdentifier: channel.uniqueIdentifier,
				kind: .before(uniqueIdentifier: oldest, fetchLimit: 1, limitToDate: nil)
			)
			let clock = ContinuousClock()
			let deadline = clock.now.advanced(by: .seconds(5))
			var outcome = await HistoricLogClient.shared.fetchOutcome(fetch)
			while case .failed(.missingCursor) = outcome, clock.now < deadline {
				try await Task.sleep(for: .milliseconds(1))
				outcome = await HistoricLogClient.shared.fetchOutcome(fetch)
			}
			guard case let .page(entries) = outcome else {
				Issue.record("An accepted server row never became a valid local history cursor")
				return
			}
			#expect(entries.isEmpty)
		}
	}

	private func outgoingHistoryLabel(on client: GLTTestClient) throws -> String? {
		let wire = try #require(client.sentLines.compactMap { $0 as? String }
			.last { $0.contains("CHATHISTORY BEFORE ") })
		return try #require(Message(line: wire, on: client)).messageTags?["label"]
	}

	@Test("An initial read failure keeps live rendering active and allows history retry")
	func initialReadFailureIsRetryable() async {
		let lazy = Preferences.Logging.loadHistoryLazily.value
		let reload = Preferences.Logging.reloadScrollbackOnLaunch.value
		Preferences.Logging.loadHistoryLazily.value = false
		Preferences.Logging.reloadScrollbackOnLaunch.value = true
		defer {
			Preferences.Logging.loadHistoryLazily.value = lazy
			Preferences.Logging.reloadScrollbackOnLaunch.value = reload
		}
		let client = IRCClient(config: ClientConfig())
		let window = window()
		let controller = LogController(client: client, in: window)
		defer { controller.tearDown(.permanentRemoval) }
		controller.historyPageFetcher = { _ in .failed(.read("Cannot read history")) }
		let view = controller.ensureBackingView()
		await controller.drainRenderJobs()
		#expect(controller.historyLoadFailure == .read("Cannot read history"))
		let live = line("live")
		controller.print(live)
		await controller.drainRenderJobs()
		#expect(view.displayedLines.map(\.lineNumber) == [live.uniqueIdentifier])
		controller.historyPageFetcher = { _ in .page([]) }
		controller.notifyDidBecomeVisible()
		await controller.drainRenderJobs()
		#expect(controller.historyLoadFailure == nil)
		#expect(view.displayedLines.map(\.lineNumber) == [live.uniqueIdentifier])
	}

	@Test("Controller renders refresh the retained member snapshot after relevant member edits")
	func memberCacheTracksNicknameAndMarkChanges() async throws {
		let lazy = Preferences.Logging.loadHistoryLazily.value
		Preferences.Logging.loadHistoryLazily.value = false
		defer { Preferences.Logging.loadHistoryLazily.value = lazy }
		let client = GLTTestClient()
		let channel = IRCChannel(config: ChannelConfig(channelName: "#members"))
		channel.associatedClient = client
		channel.activate()
		let member = ChannelUser(user: client.findUserOrCreate("alice"), prefixes: client.currentUserPrefixes)
		channel.addMember(member)
		let window = window()
		let controller = LogController(channel: channel, in: window)
		defer { controller.tearDown(.permanentRemoval) }
		controller.historyPageFetcher = { _ in .page([]) }
		let view = controller.ensureBackingView()
		await controller.drainRenderJobs()
		controller.print(line("hello alice"))
		await controller.drainRenderJobs()
		#expect(view.displayedLines.last?.body.mentionedNicknames == ["alice"])
		var ranked = try #require(channel.findMember("alice"))
		ranked.modes = "o"
		channel.memberInfo?.replaceMember(member, with: ranked)
		controller.print(line("ranked alice"))
		await controller.drainRenderJobs()
		#expect(view.displayedLines.last?.modeSymbol == ranked.mark)
		#expect(view.displayedLines.first?.modeSymbol == member.mark)
		channel.removeMember(withNickname: "alice")
		controller.print(line("departed alice"))
		await controller.drainRenderJobs()
		#expect(view.displayedLines.last?.body.mentionedNicknames.isEmpty == true)
	}

	private func withServerHistoryController(
		labeled: Bool,
		_ body: (GLTTestClient, IRCChannel, LogController) async throws -> Void
	) async throws {
		let lazy = Preferences.Logging.loadHistoryLazily.value
		Preferences.Logging.loadHistoryLazily.value = false
		defer { Preferences.Logging.loadHistoryLazily.value = lazy }
		var preferences = ClientPreferences()
		preferences.requestChatHistory = true
		let client = GLTTestClient(configDictionary: ["nickname": "me"], nicknamePassword: nil,
		                           fixture: GLTClientEnvironmentFixture(preferences: preferences))
		client.enableCapability([.batch, .serverTime, .messageTags, .chatHistory])
		if labeled {
			client.enableCapability(.labeledResponse)
		}
		let channel = try #require(client.findChannelOrCreate("#history"))
		client.isConnected = true
		client.isLoggedIn = true
		client.socket = Connection(config: IRCConnectionConfig(), onClient: client)
		client.forwardsProcessedMessages = true
		client.linePrintObserver = nil
		let window = window()
		let controller = LogController(channel: channel, in: window)
		channel.presentation = controller
		defer {
			controller.tearDown(.permanentRemoval)
			client.resetChatHistoryState()
			client.stopAllTimers()
		}
		controller.historyPageFetcher = { _ in .page([]) }
		_ = controller.ensureBackingView()
		await controller.drainRenderJobs()
		controller.print(line("live", date: 100))
		await controller.drainRenderJobs()
		controller.loadOlderHistory()
		await controller.drainRenderJobs()
		try #require(controller.serverHistoryRequest != nil)
		try await body(client, channel, controller)
	}
}
