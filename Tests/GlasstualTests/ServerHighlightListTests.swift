/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Server highlight list")
struct ServerHighlightListTests {
	private func entry(body: String, receivedAt: Date) -> HighlightLogEntry {
		var line = LogLine()
		line.messageBody = body
		line.nickname = "alice"
		line.lineType = .privateMessage
		line.receivedAt = receivedAt
		return HighlightLogEntry(lineLogged: line, clientId: "client", channelId: "channel")
	}

	@Test("The native table starts with the newest highlight first")
	func newestHighlightIsFirst() {
		let older = entry(body: "older", receivedAt: Date(timeIntervalSince1970: 100))
		let newer = entry(body: "newer", receivedAt: Date(timeIntervalSince1970: 200))
		let model = ServerHighlightListModel()

		model.replace(with: [older, newer])

		#expect(model.rows.map(\.entry.lineNumber) == [newer.lineNumber, older.lineNumber])
	}

	@Test("Changing the table sort order reorders the model")
	func changingSortOrderReordersRows() {
		let older = entry(body: "older", receivedAt: Date(timeIntervalSince1970: 100))
		let newer = entry(body: "newer", receivedAt: Date(timeIntervalSince1970: 200))
		let model = ServerHighlightListModel()
		model.replace(with: [older, newer])

		model.sort(using: [ServerHighlightListComparator(field: .time, order: .forward)])

		#expect(model.rows.map(\.entry.lineNumber) == [older.lineNumber, newer.lineNumber])
	}

	@Test("Copying selected rows joins their visible messages into one item")
	func copiedSelectionUsesVisibleContent() throws {
		let first = entry(body: "release is ready", receivedAt: Date(timeIntervalSince1970: 100))
		let second = entry(body: "tests are green", receivedAt: Date(timeIntervalSince1970: 200))
		let model = ServerHighlightListModel()
		model.replace(with: [first, second])

		model.selection = Set(model.rows.map(\.id))

		let copied = try #require(model.selectedCopyItems.first)
		#expect(model.selectedCopyItems.count == 1)
		#expect(copied.contains("release is ready"))
		#expect(copied.contains("tests are green"))
		#expect(copied.contains("\n"))
		#expect(copied.contains(first.lineNumber) == false)
		#expect(copied.contains(second.lineNumber) == false)
	}

	@Test("Clearing the native table also clears selection")
	func clearRemovesRowsAndSelection() throws {
		let model = ServerHighlightListModel()
		model.replace(with: [entry(body: "message", receivedAt: .now)])
		model.selection = try [#require(model.rows.first?.id)]

		model.clear()

		#expect(model.rows.isEmpty)
		#expect(model.selection.isEmpty)
	}

	@Test("The legacy highlight nib is no longer bundled")
	func legacyNibIsRemoved() {
		#expect(Bundle.main.path(forResource: "TDCServerHighlightListSheet", ofType: "nib") == nil)
	}
}
