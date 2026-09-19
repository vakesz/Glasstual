// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

private actor TranscriptPageGate {
	private var started = false
	private var observers: [CheckedContinuation<Void, Never>] = []
	private var fetch: CheckedContinuation<ScrollbackFetchOutcome, Never>?

	func suspend() async -> ScrollbackFetchOutcome {
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

	func finish(_ entries: [ScrollbackEntry]) {
		fetch?.resume(returning: .page(entries))
		fetch = nil
	}
}

@MainActor
@Suite("Controller transcript application", .serialized)
struct TranscriptControllerApplicationTests {
	private func line(_ body: String, date: TimeInterval = 100) -> ChatLine {
		var line = ChatLine()
		line.messageBody = body
		line.lineType = .privateMessage
		line.nickname = "alice"
		line.receivedAt = Date(timeIntervalSince1970: date)
		line.messageIdentifier = UUID().uuidString
		return line
	}

	/** The controller refers to its window weakly, as it does to its session, so
	 a test keeps both in scope for as long as the controller is in use. A window
	 passed as a temporary was gone by the time an `await` returned, and the view
	 the test then made never loaded its history. */
	private func window() -> MainWindow {
		MainWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
		           styleMask: .borderless, backing: .buffered, defer: false)
	}

	@Test("Duplicate render completions still finish but cannot count as new messages")
	func duplicateRenderCompletion() async {
		let session = ServerSession(config: ServerConfig())
		let window = window()
		let controller = TranscriptController(session: session, in: window)
		defer { controller.tearDown(.permanentRemoval) }
		let message = line("duplicate")
		var results: [Bool] = []
		controller.print(message) { results.append($0.isDuplicate) }
		controller.print(message) { results.append($0.isDuplicate) }
		await controller.drainRenderJobs()
		#expect(results == [false, true])
	}

	@Test("Buffered rendering is not a viewed timestamp until the transcript is displayed")
	func bufferedRenderingIsNotViewed() async {
		let session = ServerSession(config: ServerConfig())
		let window = window()
		let controller = TranscriptController(session: session, in: window)
		defer { controller.tearDown(.permanentRemoval) }
		controller.historyPageFetcher = { _ in .page([]) }
		controller.loadsHistoryLazily = { false }
		let message = line("waiting for the view")
		var wasDisplayed: Bool?
		controller.print(message) { wasDisplayed = $0.isDisplayed }
		await controller.drainRenderJobs()
		#expect(wasDisplayed == false)
		#expect(controller.lastRenderedLineDate() == nil)
		_ = controller.ensureBackingView()
		await controller.drainRenderJobs()
		#expect(controller.lastRenderedLineDate() == message.receivedAt)
	}

	/** A read marker is answered in the turn the line was printed in, before the
	 render job has applied it, so the controller counts what it has been handed
	 as well as what it is showing — and counts it once. */
	@Test("A printed conversation line counts before it renders and only once afterwards")
	func conversationLinesCountBeforeRenderingAndOnlyOnce() async {
		let session = ServerSession(config: ServerConfig())
		let window = window()
		let controller = TranscriptController(session: session, in: window)
		defer { controller.tearDown(.permanentRemoval) }
		controller.historyPageFetcher = { _ in .page([]) }
		controller.loadsHistoryLazily = { false }
		_ = controller.ensureBackingView()
		await controller.drainRenderJobs()
		let marker = Date(timeIntervalSince1970: 50)
		let message = line("said out loud", date: 100)
		var topic = line("the topic", date: 200)
		topic.lineType = .topic

		controller.print(message)

		#expect(controller.newestConversationLineDate() == message.receivedAt)
		#expect(controller.conversationLineCount(after: marker) == 1)

		await controller.drainRenderJobs()

		#expect(controller.newestConversationLineDate() == message.receivedAt)
		#expect(controller.conversationLineCount(after: marker) == 1)
		#expect(controller.conversationLineCount(after: message.receivedAt) == 0)

		controller.print(topic)
		await controller.drainRenderJobs()

		#expect(controller.newestConversationLineDate() == message.receivedAt)
		#expect(controller.conversationLineCount(after: marker) == 1)
	}

	/// What the pipeline drops, the seams forget: clearing the view cancels the
	/// queued jobs, so a line that was waiting on one must stop answering for a
	/// view that is never going to show it.
	@Test("Cancelling the queued rendering forgets the lines that were waiting on it")
	func cancelledRenderingForgetsWaitingLines() async {
		let session = ServerSession(config: ServerConfig())
		let window = window()
		let controller = TranscriptController(session: session, in: window)
		defer { controller.tearDown(.permanentRemoval) }
		controller.historyPageFetcher = { _ in .page([]) }
		controller.loadsHistoryLazily = { false }
		_ = controller.ensureBackingView()
		await controller.drainRenderJobs()

		controller.print(line("said out loud", date: 100))

		#expect(controller.conversationLineCount(after: .distantPast) == 1)

		controller.clear()

		#expect(controller.newestConversationLineDate() == nil)
		#expect(controller.conversationLineCount(after: .distantPast) == 0)

		await controller.drainRenderJobs()

		#expect(controller.newestConversationLineDate() == nil)
		#expect(controller.conversationLineCount(after: .distantPast) == 0)
	}

	@Test("Jump to Present resumes following from either the present or earlier text", arguments: [false, true])
	func jumpToPresentFollowsSubsequentPrints(fromHistory: Bool) async throws {
		let session = ServerSession(config: ServerConfig())
		let window = window()
		let controller = TranscriptController(session: session, in: window)
		controller.loadsHistoryLazily = { false }
		defer { controller.tearDown(.permanentRemoval) }
		controller.historyPageFetcher = { _ in .page([]) }
		let view = controller.ensureBackingView()
		view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
		window.contentView = view
		await controller.drainRenderJobs()
		view.setBufferLimit(1000)
		let first = line("first message", date: 0)
		controller.print(first)
		for index in 1 ..< 100 {
			controller.print(line("message \(index)", date: Double(index)))
		}
		await controller.drainRenderJobs()
		view.layoutSubtreeIfNeeded()
		controller.jumpToPresent()
		let scroll = try #require(view.subviews.compactMap { $0 as? NSScrollView }.first)
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
		view.layoutSubtreeIfNeeded()
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
		let session = ServerSession(config: ServerConfig())
		let window = window()
		let controller = TranscriptController(session: session, in: window)
		controller.loadsHistoryLazily = { false }
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
		let entry = stale.scrollbackEntry(forView: controller.uniqueIdentifier)
		if destroy {
			controller.tearDown(.permanentRemoval)
		} else {
			controller.clear()
		}
		await gate.finish([entry])
		await retiredFetch?.value
		await controller.drainRenderJobs()
		#expect(view.displayedLines.allSatisfy { $0.lineNumber != stale.uniqueIdentifier })
		#expect(try Scrollback.shared.duplicates.containsMessageIdentifier(
			#require(stale.messageIdentifier), forView: controller.uniqueIdentifier
		) == false)
		if !destroy {
			controller.tearDown(.permanentRemoval)
		}
	}

	@Test("Initial replay merges archived reactions with deltas and retains live prints")
	func initialReplayKeepsLiveState() async throws {
		let reload = SettingsKeys.Logging.reloadScrollbackOnLaunch.value
		SettingsKeys.Logging.reloadScrollbackOnLaunch.value = true
		defer { SettingsKeys.Logging.reloadScrollbackOnLaunch.value = reload }
		let session = ServerSession(config: ServerConfig())
		let window = window()
		let controller = TranscriptController(session: session, in: window)
		controller.loadsHistoryLazily = { false }
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
		await gate.finish([live.scrollbackEntry(forView: controller.uniqueIdentifier),
		                   archived.scrollbackEntry(forView: controller.uniqueIdentifier)])
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
		let session = ServerSession(config: ServerConfig())
		let window = window()
		let controller = TranscriptController(session: session, in: window)
		controller.loadsHistoryLazily = { false }
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
		await gate.finish([stale.scrollbackEntry(forView: controller.uniqueIdentifier)])
		await controller.drainRenderJobs()
		#expect(view.displayedLines.map(\.lineNumber) == [current.uniqueIdentifier])
		#expect(try !Scrollback.shared.duplicates.containsMessageIdentifier(
			#require(stale.messageIdentifier), forView: controller.uniqueIdentifier
		))
		let currentIdentifier = current.uniqueIdentifier
		let adjacentEntry = previous.scrollbackEntry(forView: controller.uniqueIdentifier)
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

	@Test("A failed older fetch leaves its cursor retryable and restores archived reactions")
	func failedPageDoesNotAdvanceCursor() async throws {
		let session = ServerSession(config: ServerConfig())
		let window = window()
		let controller = TranscriptController(session: session, in: window)
		controller.loadsHistoryLazily = { false }
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
		let entry = older.scrollbackEntry(forView: controller.uniqueIdentifier)
		// A reaction to an unknown message is deliberately outside retention.
		controller.noteReaction("+1", fromNickname: "bob", toMessageIdentifier: identifier)
		controller.historyPageFetcher = { _ in .page([entry]) }
		controller.loadOlderHistory()
		await controller.drainRenderJobs()
		#expect(!controller.olderHistoryFailed)
		#expect(controller.oldestLineNumber == older.uniqueIdentifier)
		#expect(view.displayedLines.first?.reactions == ["+1": ["alice"]])
	}

	@Test("Batched production prints preserve completion order and visible bounds after trimming")
	func completionOrderSurvivesBatchingAndTrim() async {
		let session = ServerSession(config: ServerConfig())
		let window = window()
		let controller = TranscriptController(session: session, in: window)
		controller.loadsHistoryLazily = { false }
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
		try await withServerHistoryController(labeled: labeled) { session, channel, controller in
			_ = try #require(session.socket)
			let request = try #require(controller.serverHistory.request)
			let label = try outgoingHistoryLabel(on: session)
			let tags = label.map { "@label=\($0) " } ?? ""
			if nested {
				session.connectionDidReceive("\(tags)BATCH +wrapper labeled-response")
				session.connectionDidReceive("@batch=wrapper BATCH +page chathistory \(channel.name)")
				session.connectionDidReceive("BATCH -page")
				#expect(controller.serverHistory.request == request)
				session.connectionDidReceive("BATCH -wrapper")
			} else {
				session.connectionDidReceive("\(tags)BATCH +page chathistory \(channel.name)")
				session.connectionDidReceive("BATCH -page")
			}
			#expect(controller.serverHistory.request == nil)
			#expect(controller.serverHistory.exhaustedBefore == (labeled ? request.before : nil))
			#expect(!controller.serverHistory.failed)
			#expect(session.chatHistory.serverRequests.isEmpty)
			let count = session.sentLines.count
			controller.loadOlderHistory()
			await controller.drainRenderJobs()
			#expect(
				session.sentLines.count == count,
				"An empty or duplicate-only response must not create a scroll-triggered request loop"
			)
			controller.retryServerHistory()
			#expect(controller.serverHistory.request?.id != request.id)
			#expect(controller.serverHistory.request != nil)
		}
	}

	@Test("Wire history failures are retryable and cannot exhaust the transcript", arguments: [false, true])
	func failedServerPageCanRetry(labeled: Bool) async throws {
		try await withServerHistoryController(labeled: labeled) { session, channel, controller in
			_ = try #require(session.socket)
			let first = try #require(controller.serverHistory.request)
			let label = try outgoingHistoryLabel(on: session)
			let tags = label.map { "@label=\($0) " } ?? ""
			let failure = "\(tags)FAIL CHATHISTORY TEMPORARILY_UNAVAILABLE BEFORE \(channel.name) :Retry later"
			session.connectionDidReceive(failure)
			#expect(controller.serverHistory.failed)
			#expect(controller.serverHistory.exhaustedBefore == nil)
			#expect(controller.serverHistory.request == nil)
			#expect(session.chatHistoryIsAvailable(for: channel))
			controller.loadOlderHistory()
			await controller.drainRenderJobs()
			let retry = try #require(controller.serverHistory.request)
			#expect(retry.id != first.id)
			#expect(!controller.serverHistory.failed)
			if labeled {
				session.connectionDidReceive(failure)
				#expect(controller.serverHistory.request == retry)
				#expect(!controller.serverHistory.failed)
			}
		}
	}

	@Test("A labeled batch admitted before clear cannot complete or prepend into the next generation")
	func retiredServerPageCannotMutateController() async throws {
		try await withServerHistoryController(labeled: true) { session, channel, controller in
			_ = try #require(session.socket)
			let label = try #require(try outgoingHistoryLabel(on: session))
			let identifier = UUID().uuidString
			session.connectionDidReceive("@label=\(label) BATCH +old chathistory \(channel.name)")
			session
				.connectionDidReceive(
					"@batch=old;msgid=\(identifier);time=1970-01-01T00:00:50.000Z :alice!u@h PRIVMSG \(channel.name) :retired page"
				)
			controller.clear()
			await controller.drainRenderJobs()
			controller.print(line("new generation", date: 200))
			await controller.drainRenderJobs()
			controller.loadOlderHistory()
			await controller.drainRenderJobs()
			let current = try #require(controller.serverHistory.request)
			session.connectionDidReceive("BATCH -old")
			await controller.drainRenderJobs()
			#expect(controller.serverHistory.request == current)
			#expect(!controller.serverHistory.failed)
			#expect(controller.serverHistory.exhaustedBefore == nil)
			#expect(controller.backingView?.displayedLines.map(\.receivedAt) == [Date(timeIntervalSince1970: 200)])
			#expect(!Scrollback.shared.duplicates.containsMessageIdentifier(
				identifier,
				forView: channel.uniqueIdentifier
			))
		}
	}

	@Test("An uncorrelated empty batch cannot complete a labeled request")
	func unrelatedEmptyBatchDoesNotExhaust() async throws {
		try await withServerHistoryController(labeled: true) { session, channel, controller in
			_ = try #require(session.socket)
			let request = try #require(controller.serverHistory.request)
			session.connectionDidReceive("BATCH +unsolicited chathistory \(channel.name)")
			session.connectionDidReceive("BATCH -unsolicited")
			#expect(controller.serverHistory.request == request)
			#expect(controller.serverHistory.exhaustedBefore == nil)
		}
	}

	@Test("A duplicate-only wire page is not mistaken for an empty server page")
	func duplicateOnlyServerPageDoesNotExhaust() async throws {
		try await withServerHistoryController(labeled: true) { session, channel, controller in
			_ = try #require(session.socket)
			let label = try #require(try outgoingHistoryLabel(on: session))
			let duplicate = line("already stored", date: 50)
			let identifier = try #require(duplicate.messageIdentifier)
			Scrollback.shared.duplicates.indexChatLines([duplicate], forView: channel.uniqueIdentifier)
			for wire in [
				"@label=\(label) BATCH +page chathistory \(channel.name)",
				"@batch=page;msgid=\(identifier);time=1970-01-01T00:00:50.000Z :alice!u@h PRIVMSG \(channel.name) :already stored",
				"BATCH -page",
			] {
				session.connectionDidReceive(wire)
			}
			#expect(controller.serverHistory.request == nil)
			#expect(controller.serverHistory.exhaustedBefore == nil)
			#expect(!controller.serverHistory.failed)
		}
	}

	@Test("Nested labeled wire history reaches the controller prepend path")
	func nestedServerPagePrepends() async throws {
		try await withServerHistoryController(labeled: true) { session, channel, controller in
			_ = try #require(session.socket)
			let label = try #require(try outgoingHistoryLabel(on: session))
			let identifier = UUID().uuidString
			for wire in [
				"@label=\(label) BATCH +wrapper labeled-response",
				"@batch=wrapper BATCH +page chathistory \(channel.name)",
				"@batch=page;msgid=\(identifier);time=1970-01-01T00:00:50.000Z :alice!u@h PRIVMSG \(channel.name) :older",
				"BATCH -page", "BATCH -wrapper",
			] {
				session.connectionDidReceive(wire)
			}
			await controller.drainRenderJobs()
			#expect(controller.serverHistory.request == nil)
			#expect(controller.serverHistory.exhaustedBefore == nil)
			#expect(controller.backingView?.displayedLines.map(\.receivedAt) == [50, 100]
				.map { Date(timeIntervalSince1970: $0) })
			#expect(Scrollback.shared.duplicates.containsMessageIdentifier(
				identifier,
				forView: channel.uniqueIdentifier
			))
			let oldest = try #require(controller.oldestLineNumber)
			let fetch = ScrollbackFetchRequest(
				viewIdentifier: channel.uniqueIdentifier,
				kind: .before(uniqueIdentifier: oldest, fetchLimit: 1, limitToDate: nil)
			)
			let clock = ContinuousClock()
			let deadline = clock.now.advanced(by: .seconds(5))
			var outcome = await ScrollbackSession.shared.fetchOutcome(fetch)
			while case .failed(.missingCursor) = outcome, clock.now < deadline {
				try await Task.sleep(for: .milliseconds(1))
				outcome = await ScrollbackSession.shared.fetchOutcome(fetch)
			}
			guard case let .page(entries) = outcome else {
				Issue.record("An accepted server row never became a valid local history cursor")
				return
			}
			#expect(entries.isEmpty)
		}
	}

	private func outgoingHistoryLabel(on session: TestServerSession) throws -> String? {
		let wire = try #require(session.sentLines.compactMap { $0 as? String }
			.last { $0.contains("CHATHISTORY BEFORE ") })
		return try #require(Message(line: wire, on: session)).messageTags?["label"]
	}

	@Test("An initial read failure keeps live rendering active and allows history retry")
	func initialReadFailureIsRetryable() async {
		let reload = SettingsKeys.Logging.reloadScrollbackOnLaunch.value
		SettingsKeys.Logging.reloadScrollbackOnLaunch.value = true
		defer { SettingsKeys.Logging.reloadScrollbackOnLaunch.value = reload }
		let session = ServerSession(config: ServerConfig())
		let window = window()
		let controller = TranscriptController(session: session, in: window)
		controller.loadsHistoryLazily = { false }
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
		let session = TestServerSession()
		let channel = Conversation(config: ConversationConfig(name: "#members"))
		channel.associatedSession = session
		channel.activate()
		let member = Member(user: session.findUserOrCreate("alice"), prefixes: session.currentUserPrefixes)
		channel.addMember(member)
		let window = window()
		let controller = TranscriptController(conversation: channel, in: window)
		controller.loadsHistoryLazily = { false }
		defer { controller.tearDown(.permanentRemoval) }
		controller.historyPageFetcher = { _ in .page([]) }
		let view = controller.ensureBackingView()
		await controller.drainRenderJobs()
		controller.print(line("hello @alice"))
		await controller.drainRenderJobs()
		#expect(view.displayedLines.last?.body.mentionedNicknames == ["alice"])
		var ranked = try #require(channel.findMember("alice"))
		ranked.modes = "o"
		channel.memberInfo?.replaceMember(member, with: ranked)
		controller.print(line("ranked @alice"))
		await controller.drainRenderJobs()
		#expect(view.displayedLines.last?.modeSymbol == ranked.mark)
		#expect(view.displayedLines.first?.modeSymbol == member.mark)
		channel.removeMember(withNickname: "alice")
		controller.print(line("departed @alice"))
		await controller.drainRenderJobs()
		#expect(view.displayedLines.last?.body.mentionedNicknames.isEmpty == true)
	}

	private func withServerHistoryController(
		labeled: Bool,
		_ body: (TestServerSession, Conversation, TranscriptController) async throws -> Void
	) async throws {
		var settings = ChatSettings()
		settings.requestChatHistory = true
		let session = TestServerSession(configDictionary: ["nickname": "me"], nicknamePassword: nil,
		                                fixture: ChatEnvironmentFixture(settings: settings))
		session.enableCapability([.batch, .serverTime, .messageTags, .chatHistory])
		if labeled {
			session.enableCapability(.labeledResponse)
		}
		let channel = try #require(session.findConversationOrCreate("#history"))
		session.isConnected = true
		session.isLoggedIn = true
		session.socket = Connection(config: ConnectionConfig(), onSession: session)
		session.forwardsProcessedMessages = true
		session.linePrintObserver = nil
		let window = window()
		let controller = TranscriptController(conversation: channel, in: window)
		controller.loadsHistoryLazily = { false }
		channel.presentation = controller
		defer {
			controller.tearDown(.permanentRemoval)
			session.resetChatHistoryState()
			session.stopAllTimers()
		}
		controller.historyPageFetcher = { _ in .page([]) }
		_ = controller.ensureBackingView()
		await controller.drainRenderJobs()
		controller.print(line("live", date: 100))
		await controller.drainRenderJobs()
		controller.loadOlderHistory()
		await controller.drainRenderJobs()
		try #require(controller.serverHistory.request != nil)
		try await body(session, channel, controller)
	}
}
