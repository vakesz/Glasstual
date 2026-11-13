// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Transcript log viewer")
struct TranscriptLogViewerModelTests {
	private func model(for fixture: TranscriptLogFixture) -> TranscriptLogViewerModel {
		TranscriptLogViewerModel(rootProvider: { fixture.root })
	}

	@Test("With no transcript folder the window asks for one")
	func noFolderIsReported() async {
		let model = TranscriptLogViewerModel(rootProvider: { nil })

		await model.refresh()

		#expect(model.phase == .noFolder)
		#expect(model.servers.isEmpty)
	}

	@Test("Choosing a conversation opens its newest day")
	func conversationOpensItsNewestDay() async throws {
		let fixture = try TranscriptLogFixture()
		defer { fixture.remove() }
		try fixture.write("old\n", server: "S (00000)", folder: "Channels", name: "#a", day: "2026-01-01")
		try fixture.write("new\n", server: "S (00000)", folder: "Channels", name: "#a", day: "2026-02-01")
		let model = model(for: fixture)
		await model.refresh()

		try model.selectConversation(id: #require(model.servers.first?.conversations.first?.id))
		await model.loadSelectedLog()

		#expect(model.phase == .ready)
		#expect(model.selectedDay == TranscriptDay(year: 2026, month: 2, day: 1))
		#expect(model.lines.map(\.text) == ["new"])
		#expect(model.revealURL?.lastPathComponent == "2026-02-01.txt")
	}

	@Test("Choosing another day replaces the text")
	func anotherDayReplacesTheText() async throws {
		let fixture = try TranscriptLogFixture()
		defer { fixture.remove() }
		try fixture.write("old\n", server: "S (00000)", folder: "Channels", name: "#a", day: "2026-01-01")
		try fixture.write("new\n", server: "S (00000)", folder: "Channels", name: "#a", day: "2026-02-01")
		let model = model(for: fixture)
		await model.refresh()
		try model.selectConversation(id: #require(model.servers.first?.conversations.first?.id))

		model.selectDay(TranscriptDay(year: 2026, month: 1, day: 1))
		await model.loadSelectedLog()

		#expect(model.lines.map(\.text) == ["old"])
	}

	@Test("Search moves to the newest match, steps both ways and wraps")
	func searchStepsThroughMatches() async throws {
		let fixture = try TranscriptLogFixture()
		defer { fixture.remove() }
		try fixture.write("hit one\nmiss\nhit two\nhit three\n", server: "S (00000)", folder: "Console", day: "2026-01-01")
		let model = model(for: fixture)
		await model.refresh()
		try model.selectConversation(id: #require(model.servers.first?.conversations.first?.id))
		await model.loadSelectedLog()

		model.searchText = "HIT"
		await model.search()

		#expect(model.matchOffsets == [0, 13, 21])
		#expect(model.currentMatchIndex == 2)
		#expect(model.scrollRequest?.lineID == 21)

		await model.nextMatch()
		#expect(model.currentMatchIndex == 0)
		#expect(model.scrollRequest?.lineID == 0)

		await model.previousMatch()
		#expect(model.currentMatchIndex == 2)
	}

	@Test("Stepping onto the same line again is a new scroll request")
	func repeatedStepIsANewRequest() async throws {
		let fixture = try TranscriptLogFixture()
		defer { fixture.remove() }
		try fixture.write("only hit\n", server: "S (00000)", folder: "Console", day: "2026-01-01")
		let model = model(for: fixture)
		await model.refresh()
		try model.selectConversation(id: #require(model.servers.first?.conversations.first?.id))
		await model.loadSelectedLog()
		model.searchText = "hit"
		await model.search()
		let first = model.scrollRequest

		await model.nextMatch()

		#expect(model.scrollRequest != first)
		#expect(model.scrollRequest?.lineID == first?.lineID)
	}

	@Test("A search for text that is not there leaves no match to step to")
	func missingTextHasNoMatches() async throws {
		let fixture = try TranscriptLogFixture()
		defer { fixture.remove() }
		try fixture.write("nothing here\n", server: "S (00000)", folder: "Console", day: "2026-01-01")
		let model = model(for: fixture)
		await model.refresh()
		try model.selectConversation(id: #require(model.servers.first?.conversations.first?.id))
		await model.loadSelectedLog()

		model.searchText = "absent"
		await model.search()
		await model.nextMatch()

		#expect(model.hasMatches == false)
		#expect(model.currentMatchIndex == nil)
	}

	@Test("A match before the loaded lines loads them before scrolling")
	func matchBeforeTheLoadedLinesIsLoaded() async throws {
		let fixture = try TranscriptLogFixture()
		defer { fixture.remove() }
		let padding = String(repeating: "x", count: 99) + "\n"
		let text = "needle\n" + String(repeating: padding, count: 8000)
		try fixture.write(text, server: "S (00000)", folder: "Console", day: "2026-01-01")
		let model = model(for: fixture)
		await model.refresh()
		try model.selectConversation(id: #require(model.servers.first?.conversations.first?.id))
		await model.loadSelectedLog()
		#expect(model.hasEarlierLines)

		model.searchText = "needle"
		await model.search()

		#expect(model.startOffset == 0)
		#expect(model.lines.first?.text == "needle")
		#expect(model.scrollRequest?.lineID == 0)
	}
}
