// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CoreData
import Foundation
@testable import Glasstual
import Testing

/// Search over stored history: what is written beside each line, what a query
/// matches, and how a hit is turned back into a window of lines.
@MainActor
@Suite("Scrollback search")
struct ScrollbackSearchTests {
	private func openStore() async throws -> (ScrollbackStore, URL) {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		let store = ScrollbackStore(filenameSetting: ScrollbackFilenameFixture.unique().store)
		#expect(await store.openDatabase(inDirectory: directory.path).isOpen)
		return (store, directory)
	}

	private func line(
		_ body: String,
		from nickname: String = "alice",
		at seconds: TimeInterval,
		type: ChatLineKind = .privateMessage,
		identifier: String? = nil
	) -> ChatLine {
		var line = ChatLine()
		line.messageBody = body
		line.nickname = nickname
		line.lineType = type
		line.messageIdentifier = identifier
		line.receivedAt = Date(timeIntervalSince1970: seconds)
		return line
	}

	@discardableResult
	private func write(_ lines: [ChatLine], to view: String, in store: ScrollbackStore) async -> Bool {
		for line in lines {
			guard await store.writeChatLine(line.scrollbackEntry(forView: view)) == .accepted else { return false }
		}
		return true
	}

	private func search(
		_ store: ScrollbackStore,
		text: String = "",
		sender: String = "",
		views: [String],
		from: Date? = nil,
		through: Date? = nil,
		limit: Int = ScrollbackSearchQuery.defaultResultLimit
	) async -> [ScrollbackSearchHit] {
		let outcome = await store.search(ScrollbackSearchQuery(
			text: text, sender: sender, viewIdentifiers: views, from: from, through: through, limit: limit
		))
		guard case let .results(hits, _) = outcome else {
			Issue.record("Expected results, got \(outcome)")
			return []
		}
		return hits
	}

	// MARK: - What is written

	@Test("A written line carries its plain text, sender and folded text")
	func writingStoresTheSearchColumns() {
		let entry = line("Caf\u{00E9} \u{02}au\u{02} lait", from: "Zo\u{00EB}", at: 10).scrollbackEntry(forView: "view")

		#expect(entry.search.plainText == "Caf\u{00E9} au lait")
		#expect(entry.search.sender == "Zo\u{00EB}")
		#expect(entry.search.searchText == "cafe au lait")
	}

	@Test("Only what a person said is searchable", arguments: [
		ChatLineKind.join, .part, .quit, .mode, .topic, .kick, .nick, .debug,
	])
	func eventsHaveNoSearchText(type: ChatLineKind) {
		let entry = line("something happened", at: 10, type: type).scrollbackEntry(forView: "view")

		#expect(entry.search == .empty)
	}

	@Test("Messages, actions and notices are searchable", arguments: [
		ChatLineKind.privateMessage, .action, .notice,
	])
	func conversationLinesHaveSearchText(type: ChatLineKind) {
		let entry = line("hello there", at: 10, type: type).scrollbackEntry(forView: "view")

		#expect(entry.search.plainText == "hello there")
	}

	@Test("A very long line is stored bounded")
	func longTextIsBounded() {
		let entry = line(String(repeating: "a", count: 50000), at: 10).scrollbackEntry(forView: "view")

		#expect(entry.search.plainText.count == ScrollbackSearchFields.maximumTextLength)
	}

	// MARK: - Matching

	@Test("A query matches text regardless of case and accents, newest first")
	func matchesFoldedTextNewestFirst() async throws {
		let (store, directory) = try await openStore()
		defer { try? FileManager.default.removeItem(at: directory) }
		await write([
			line("Un caf\u{00E9} s'il vous pla\u{00EE}t", at: 100),
			line("nothing to see", at: 101),
			line("CAFE is open", from: "bob", at: 102),
		], to: "view", in: store)

		let hits = await search(store, text: "Caf\u{00E9}", views: ["view"])

		#expect(hits.map(\.text) == ["CAFE is open", "Un caf\u{00E9} s'il vous pla\u{00EE}t"])
		#expect(hits.map(\.sender) == ["bob", "alice"])
		_ = await store.close()
	}

	@Test("A query also matches the sender's nickname")
	func matchesNicknames() async throws {
		let (store, directory) = try await openStore()
		defer { try? FileManager.default.removeItem(at: directory) }
		await write([
			line("hi", from: "Carol", at: 100),
			line("hello", from: "dave", at: 101),
		], to: "view", in: store)

		let hits = await search(store, text: "carol", views: ["view"])

		#expect(hits.map(\.text) == ["hi"])
		_ = await store.close()
	}

	@Test("The sender filter narrows the text match")
	func senderFilterNarrowsTheMatch() async throws {
		let (store, directory) = try await openStore()
		defer { try? FileManager.default.removeItem(at: directory) }
		await write([
			line("pizza tonight", from: "alice", at: 100),
			line("pizza tomorrow", from: "bob", at: 101),
			line("salad", from: "bob", at: 102),
		], to: "view", in: store)

		let withText = await search(store, text: "pizza", sender: "BOB", views: ["view"])
		let senderOnly = await search(store, sender: "bob", views: ["view"])

		#expect(withText.map(\.text) == ["pizza tomorrow"])
		#expect(senderOnly.map(\.text) == ["salad", "pizza tomorrow"])
		_ = await store.close()
	}

	@Test("Only the views the query names are read")
	func scopeLimitsTheViews() async throws {
		let (store, directory) = try await openStore()
		defer { try? FileManager.default.removeItem(at: directory) }
		await write([line("shared word one", at: 100)], to: "a", in: store)
		await write([line("shared word two", at: 101)], to: "b", in: store)
		await write([line("shared word three", at: 102)], to: "c", in: store)

		let single = await search(store, text: "shared", views: ["b"])
		let several = await search(store, text: "shared", views: ["a", "c", "a"])
		let none = await search(store, text: "shared", views: [])

		#expect(single.map(\.viewIdentifier) == ["b"])
		#expect(several.map(\.text) == ["shared word three", "shared word one"])
		#expect(none.isEmpty)
		_ = await store.close()
	}

	@Test("A date range keeps only the lines inside it")
	func dateRangeBoundsTheMatch() async throws {
		let (store, directory) = try await openStore()
		defer { try? FileManager.default.removeItem(at: directory) }
		await write([
			line("report early", at: 100),
			line("report middle", at: 200),
			line("report late", at: 300),
		], to: "view", in: store)

		let range = await search(
			store, text: "report", views: ["view"],
			from: Date(timeIntervalSince1970: 150), through: Date(timeIntervalSince1970: 250)
		)
		let from = await search(store, text: "report", views: ["view"], from: Date(timeIntervalSince1970: 200))

		#expect(range.map(\.text) == ["report middle"])
		#expect(from.map(\.text) == ["report late", "report middle"])
		_ = await store.close()
	}

	@Test("Events never match, however the query reads")
	func eventsAreNotFound() async throws {
		let (store, directory) = try await openStore()
		defer { try? FileManager.default.removeItem(at: directory) }
		await write([
			line("alice has joined", at: 100, type: .join),
			line("alice said hello", at: 101),
		], to: "view", in: store)

		let hits = await search(store, text: "alice", views: ["view"])

		#expect(hits.map(\.text) == ["alice said hello"])
		_ = await store.close()
	}

	@Test("A query is a literal, not a pattern")
	func wildcardsAreLiteral() async throws {
		let (store, directory) = try await openStore()
		defer { try? FileManager.default.removeItem(at: directory) }
		await write([line("100% sure", at: 100), line("plain text", at: 101)], to: "view", in: store)

		#expect(await search(store, text: "%", views: ["view"]).map(\.text) == ["100% sure"])
		#expect(await search(store, text: "*", views: ["view"]).isEmpty)
		#expect(await search(store, text: "p?ain", views: ["view"]).isEmpty)
		_ = await store.close()
	}

	@Test("The result limit caps the answer and says it did")
	func limitTruncates() async throws {
		let (store, directory) = try await openStore()
		defer { try? FileManager.default.removeItem(at: directory) }
		await write((0 ..< 12).map { line("needle \($0)", at: TimeInterval(100 + $0)) }, to: "view", in: store)

		let outcome = await store.search(ScrollbackSearchQuery(text: "needle", viewIdentifiers: ["view"], limit: 5))

		guard case let .results(hits, truncated) = outcome else {
			Issue.record("Expected results, got \(outcome)")
			return
		}
		#expect(hits.count == 5)
		#expect(truncated)
		#expect(hits.first?.text == "needle 11")
		_ = await store.close()
	}

	@Test("A query with no text and no sender asks for nothing")
	func emptyQueryIsNotSearchable() {
		#expect(ScrollbackSearchQuery(text: "  ", sender: "").isSearchable == false)
		#expect(ScrollbackSearchQuery(text: "x").isSearchable)
		#expect(ScrollbackSearchQuery(sender: "bob").isSearchable)
	}

	// MARK: - Staying current

	@Test("Redacting a line withdraws its words from search and keeps its row")
	func redactionRemovesTheText() async throws {
		let (store, directory) = try await openStore()
		defer { try? FileManager.default.removeItem(at: directory) }
		await write([
			line("the password is hunter2", at: 100, identifier: "msg-1"),
			line("an ordinary line", at: 101, identifier: "msg-2"),
		], to: "view", in: store)
		#expect(await search(store, text: "hunter2", views: ["view"]).count == 1)

		let outcome = await store.redactChatLine(messageIdentifier: "msg-1", inView: "view")

		guard case .redacted = outcome else {
			Issue.record("Expected the line to be redacted, got \(outcome)")
			return
		}
		#expect(await search(store, text: "hunter2", views: ["view"]).isEmpty)
		#expect(await search(store, text: "password", views: ["view"]).isEmpty)
		#expect(await search(store, sender: "alice", views: ["view"]).map(\.text) == ["an ordinary line"])
		#expect(await store.fetchOutcome(.newestEntries(forView: "view", fetchLimit: 10)).entries.count == 2)
		_ = await store.close()
	}

	@Test("Replacing a line updates the text a search finds")
	func replacementUpdatesTheText() async throws {
		let (store, directory) = try await openStore()
		defer { try? FileManager.default.removeItem(at: directory) }
		var original = line("before edit", at: 100)
		await write([original], to: "view", in: store)
		original.messageBody = "after edit"

		#expect(await store.replaceChatLine(original.scrollbackEntry(forView: "view")) == .replaced)

		#expect(await search(store, text: "before", views: ["view"]).isEmpty)
		#expect(await search(store, text: "after", views: ["view"]).count == 1)
		_ = await store.close()
	}

	@Test("A search sees lines written a moment ago, before any periodic save")
	func searchSeesUnsavedLines() async throws {
		let (store, directory) = try await openStore()
		defer { try? FileManager.default.removeItem(at: directory) }
		await write([line("fresh off the wire", at: 100)], to: "view", in: store)

		#expect(await search(store, text: "fresh", views: ["view"]).count == 1)
		_ = await store.close()
	}

	@Test("A cancelled search reports itself cancelled")
	func cancellationIsReported() async throws {
		let (store, directory) = try await openStore()
		defer { try? FileManager.default.removeItem(at: directory) }
		await write([line("anything", at: 100)], to: "view", in: store)

		let task = Task { await store.search(ScrollbackSearchQuery(text: "any", viewIdentifiers: ["view"])) }
		task.cancel()

		#expect(await task.value == .cancelled)
		_ = await store.close()
	}

	// MARK: - Jumping to a hit

	@Test("A window holds the hit between the rows before and after it, oldest first")
	func windowSurroundsTheHit() async throws {
		let (store, directory) = try await openStore()
		defer { try? FileManager.default.removeItem(at: directory) }
		let lines = (0 ..< 9).map { line("line \($0)", at: TimeInterval(100 + $0)) }
		await write(lines, to: "view", in: store)
		let hit = try #require(await search(store, text: "line 4", views: ["view"]).first)

		let outcome = await store.fetchOutcome(ScrollbackFetchRequest(
			viewIdentifier: "view", kind: .window(around: hit.cursor, olderLimit: 2, newerLimit: 3)
		))

		let entries = outcome.entries
		#expect(entries.compactMap { ChatLine(entry: $0)?.messageBody } == ["line 2", "line 3", "line 4", "line 5", "line 6", "line 7"])
		#expect(entries[2].cursor == hit.cursor)
		_ = await store.close()
	}

	@Test("A window at either end holds what exists")
	func windowAtTheEdges() async throws {
		let (store, directory) = try await openStore()
		defer { try? FileManager.default.removeItem(at: directory) }
		await write((0 ..< 4).map { line("line \($0)", at: TimeInterval(100 + $0)) }, to: "view", in: store)
		let oldest = try #require(await search(store, text: "line 0", views: ["view"]).first)
		let newest = try #require(await search(store, text: "line 3", views: ["view"]).first)

		let atStart = await store.fetchOutcome(ScrollbackFetchRequest(
			viewIdentifier: "view", kind: .window(around: oldest.cursor, olderLimit: 5, newerLimit: 1)
		)).entries
		let atEnd = await store.fetchOutcome(ScrollbackFetchRequest(
			viewIdentifier: "view", kind: .window(around: newest.cursor, olderLimit: 1, newerLimit: 5)
		)).entries

		#expect(atStart.compactMap { ChatLine(entry: $0)?.messageBody } == ["line 0", "line 1"])
		#expect(atEnd.compactMap { ChatLine(entry: $0)?.messageBody } == ["line 2", "line 3"])
		_ = await store.close()
	}

	@Test("Two rows that share a line identity are told apart by their cursors")
	func windowCentresOnTheRowTheCursorNames() async throws {
		let (store, directory) = try await openStore()
		defer { try? FileManager.default.removeItem(at: directory) }
		let first = line("twin one", at: 100)
		await write([first], to: "view", in: store)
		/* The same line identity stored twice, as a replayed line can be. */
		let twin = line("twin two", at: 100)
		var duplicate = twin.scrollbackEntry(forView: "view")
		duplicate = ScrollbackEntry(
			lineData: duplicate.data, uniqueIdentifier: first.uniqueIdentifier, viewIdentifier: "view",
			sessionIdentifier: duplicate.sessionIdentifier, creationDate: duplicate.creationDate, search: duplicate.search
		)
		#expect(await store.writeChatLine(duplicate) == .accepted)
		await write([line("after", at: 101)], to: "view", in: store)
		let hits = await search(store, text: "twin", views: ["view"])
		#expect(hits.count == 2)
		#expect(Set(hits.map(\.cursor.rowURI)).count == 2)

		for hit in hits {
			let window = await store.fetchOutcome(ScrollbackFetchRequest(
				viewIdentifier: "view", kind: .window(around: hit.cursor, olderLimit: 0, newerLimit: 0)
			)).entries
			#expect(window.count == 1)
			#expect(window.first?.cursor == hit.cursor)
			#expect(window.first.flatMap { ChatLine(entry: $0)?.messageBody } == hit.text)
		}
		_ = await store.close()
	}

	@Test("Rows that tie on time keep one order across the two halves of a window")
	func windowKeepsTiedRowsInOrder() async throws {
		let (store, directory) = try await openStore()
		defer { try? FileManager.default.removeItem(at: directory) }
		await write((0 ..< 6).map { line("tied \($0)", at: 100) }, to: "view", in: store)
		let hits = await search(store, text: "tied", views: ["view"])
		let middle = try #require(hits.sorted { $0.cursor < $1.cursor }[safe: 2])

		let window = await store.fetchOutcome(ScrollbackFetchRequest(
			viewIdentifier: "view", kind: .window(around: middle.cursor, olderLimit: 10, newerLimit: 10)
		)).entries

		#expect(window.count == 6)
		let cursors = window.compactMap(\.cursor)
		#expect(cursors == cursors.sorted())
		#expect(Set(window.map(\.uniqueIdentifier)).count == 6)
		_ = await store.close()
	}

	@Test("A cursor whose row is gone is reported, not replaced by a neighbour")
	func windowReportsAPrunedRow() async throws {
		let (store, directory) = try await openStore()
		defer { try? FileManager.default.removeItem(at: directory) }
		await write([line("here today", at: 100), line("also here", at: 101)], to: "view", in: store)
		let hit = try #require(await search(store, text: "here today", views: ["view"]).first)
		_ = await store.resetData(forView: "view")

		let outcome = await store.fetchOutcome(ScrollbackFetchRequest(
			viewIdentifier: "view", kind: .window(around: hit.cursor, olderLimit: 3, newerLimit: 3)
		))

		guard case let .failed(failure) = outcome else {
			Issue.record("Expected a failure, got \(outcome)")
			return
		}
		#expect(failure == .missingCursor)
		_ = await store.close()
	}

	@Test("A window never reaches into another view")
	func windowStaysInItsView() async throws {
		let (store, directory) = try await openStore()
		defer { try? FileManager.default.removeItem(at: directory) }
		await write([line("mine", at: 100)], to: "view", in: store)
		await write([line("theirs before", at: 99), line("theirs after", at: 101)], to: "other", in: store)
		let hit = try #require(await search(store, text: "mine", views: ["view"]).first)

		let window = await store.fetchOutcome(ScrollbackFetchRequest(
			viewIdentifier: "view", kind: .window(around: hit.cursor, olderLimit: 5, newerLimit: 5)
		)).entries

		#expect(window.compactMap { ChatLine(entry: $0)?.messageBody } == ["mine"])
		_ = await store.close()
	}
}

private extension Array {
	subscript(safe index: Int) -> Element? {
		indices.contains(index) ? self[index] : nil
	}
}

/// The upgrade's progress as the window reads it.
@MainActor
@Suite("Scrollback upgrade progress")
struct ScrollbackMigrationProgressTests {
	@Test("Progress rises, never falls back, and clears when the upgrade finishes")
	func progressIsMonotonic() {
		let recovery = ScrollbackStorageRecovery()
		#expect(recovery.migrationFraction == nil)

		recovery.noteMigrationProgress(0)
		recovery.noteMigrationProgress(0.5)
		// An earlier fraction that lands late is a stale one.
		recovery.noteMigrationProgress(0.25)
		#expect(recovery.migrationFraction == 0.5)

		recovery.noteMigrationProgress(1)
		#expect(recovery.migrationFraction == nil)
	}
}
