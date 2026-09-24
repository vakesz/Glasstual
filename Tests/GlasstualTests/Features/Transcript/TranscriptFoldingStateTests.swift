// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@Suite("Transcript folding state")
struct TranscriptFoldingStateTests {
	@Test("Routine events share one collapsed summary", arguments: [
		ChatLineKind.join, .part, .quit, .nick, .mode, .topic,
	])
	func routineEventsGroupTogether(kind: ChatLineKind) {
		var state = TranscriptFoldingState()
		let changed = state.update(
			rows: [row("first", kind: .join), row("second", kind: kind)],
			generalEventDisplay: .collapse, mutedNicknames: [], caseMapping: .rfc1459
		)
		#expect(changed == ["first", "second"])
		#expect(state.presentations["first"] == .summary(kind: .generalEvents, count: 2, expanded: false))
		#expect(state.presentations["second"] == .hidden)
	}

	@Test("Conversation and important event rows break general-event groups", arguments: [
		ChatLineKind.privateMessage, .action, .notice, .kick, .kill, .debug, .invite, .ctcp, .undefined,
	])
	func otherRowsRemainVisible(kind: ChatLineKind) {
		var state = TranscriptFoldingState()
		state.update(
			rows: [row("before", kind: .join), row("visible", kind: kind), row("after", kind: .part)],
			generalEventDisplay: .collapse, mutedNicknames: [], caseMapping: .rfc1459
		)
		#expect(state.presentations["visible"] == nil)
		#expect(state.presentations["before"] == .summary(kind: .generalEvents, count: 1, expanded: false))
		#expect(state.presentations["after"] == .summary(kind: .generalEvents, count: 1, expanded: false))
	}

	@Test("A muted sender's first message is collapsed", arguments: [
		ChatLineKind.privateMessage, .action, .notice, .privateMessageNoHighlight, .actionNoHighlight,
	])
	func singleMutedMessagesAreCollapsed(kind: ChatLineKind) {
		var state = TranscriptFoldingState()
		state.update(
			rows: [row("muted", kind: kind, nickname: "ALICE")],
			generalEventDisplay: .show, mutedNicknames: ["Alice"], caseMapping: .rfc1459
		)
		#expect(state.presentations["muted"] == .summary(
			kind: .mutedUser(normalizedNickname: "alice", displayNickname: "ALICE"), count: 1, expanded: false
		))
	}

	@Test("Muted groups follow the server's case mapping and retain the first display spelling")
	func mutedGroupsUseServerCaseMapping() {
		let rows = [row("first", nickname: "[Alice]"), row("second", nickname: "{ALICE}")]
		var state = TranscriptFoldingState()
		state.update(rows: rows, generalEventDisplay: .show, mutedNicknames: ["{Alice}"], caseMapping: .rfc1459)
		#expect(state.presentations["first"] == .summary(
			kind: .mutedUser(normalizedNickname: "{alice}", displayNickname: "[Alice]"), count: 2, expanded: false
		))
		#expect(state.presentations["second"] == .hidden)

		state.update(rows: rows, generalEventDisplay: .show, mutedNicknames: ["{Alice}"], caseMapping: .ascii)
		#expect(state.presentations["first"] == nil)
		#expect(state.presentations["second"] == .summary(
			kind: .mutedUser(normalizedNickname: "{alice}", displayNickname: "{ALICE}"), count: 1, expanded: false
		))
	}

	@Test("Different senders, ordinary messages and general events separate muted groups")
	func mutedGroupsKeepConversationOrder() {
		var state = TranscriptFoldingState()
		state.update(
			rows: [
				row("alice", nickname: "alice"), row("bob", nickname: "bob"),
				row("visible", nickname: "charlie"), row("alice-again", nickname: "alice"),
				row("event", kind: .join), row("alice-last", nickname: "alice"),
			],
			generalEventDisplay: .collapse, mutedNicknames: ["alice", "bob"], caseMapping: .rfc1459
		)
		#expect(state.presentations["visible"] == nil)
		for lineNumber in ["alice", "bob", "alice-again", "alice-last"] {
			guard case let .summary(.mutedUser, count, expanded) = state.presentations[lineNumber] else {
				Issue.record("Each separated muted message must begin its own group")
				continue
			}
			#expect(count == 1)
			#expect(expanded == false)
		}
		#expect(state.presentations["event"] == .summary(kind: .generalEvents, count: 1, expanded: false))
	}

	@Test("A local user's own rows remain visible", arguments: [ChatLineKind.privateMessage, .action, .notice, .join])
	func localRowsNeverFold(kind: ChatLineKind) {
		var local = row("local", kind: kind, nickname: "alice")
		local.memberType = .localUser
		var state = TranscriptFoldingState()
		state.update(rows: [local], generalEventDisplay: .collapse, mutedNicknames: ["alice"], caseMapping: .rfc1459)
		#expect(state.presentations.isEmpty)
	}

	@Test("Markers start a new group and stay on its summary", arguments: [
		TranscriptMarker.date("Today"), .currentSession("Current session"), .unread("Unread messages"),
	])
	func markersAreGroupBoundaries(marker: TranscriptMarker) {
		var boundary = row("boundary", nickname: "alice")
		boundary.markers = [marker]
		var state = TranscriptFoldingState()
		state.update(
			rows: [row("before", nickname: "alice"), boundary, row("after", nickname: "alice")],
			generalEventDisplay: .show, mutedNicknames: ["alice"], caseMapping: .rfc1459
		)
		let kind = TranscriptFoldKind.mutedUser(normalizedNickname: "alice", displayNickname: "alice")
		#expect(state.presentations["before"] == .summary(kind: kind, count: 1, expanded: false))
		#expect(state.presentations["boundary"] == .summary(kind: kind, count: 2, expanded: false))
		#expect(state.presentations["after"] == .hidden)
	}

	@Test("Toggling opens every row and keeps the summary available to close the group")
	func togglingReturnsAllChangedRows() {
		var state = TranscriptFoldingState()
		state.update(
			rows: [row("first", kind: .join), row("second", kind: .part)],
			generalEventDisplay: .collapse, mutedNicknames: [], caseMapping: .rfc1459
		)
		#expect(state.toggle(summaryLineNumber: "first") == ["first", "second"])
		#expect(state.presentations["first"] == .summary(kind: .generalEvents, count: 2, expanded: true))
		#expect(state.presentations["second"] == nil)
		#expect(state.reveal(lineNumber: "second").isEmpty)
		#expect(state.toggle(summaryLineNumber: "first") == ["first", "second"])
		#expect(state.presentations["second"] == .hidden)
		#expect(state.toggle(summaryLineNumber: "missing").isEmpty)
		#expect(state.reveal(lineNumber: "missing").isEmpty)
	}

	@Test("Revealing a hidden display row opens its group")
	func revealingHiddenDisplayRow() {
		let hidden = row("rendered", kind: .quit)
		var state = TranscriptFoldingState()
		state.update(
			rows: [row("summary", kind: .join), hidden],
			generalEventDisplay: .collapse, mutedNicknames: [], caseMapping: .rfc1459
		)
		#expect(state.reveal(lineNumber: "rendered") == ["summary", "rendered"])
		#expect(state.presentations["rendered"] == nil)
		#expect(state.presentations["summary"] == .summary(kind: .generalEvents, count: 2, expanded: true))
	}

	@Test("An expanded group survives append, prepend, and removal of its original summary")
	func expansionFollowsRetainedRows() {
		var rows = [row("first", kind: .join), row("second", kind: .part)]
		var state = TranscriptFoldingState()
		state.update(rows: rows, generalEventDisplay: .collapse, mutedNicknames: [], caseMapping: .rfc1459)
		state.toggle(summaryLineNumber: "first")
		rows.append(row("appended", kind: .quit))
		state.update(rows: rows, generalEventDisplay: .collapse, mutedNicknames: [], caseMapping: .rfc1459)
		#expect(state.presentations["first"] == .summary(kind: .generalEvents, count: 3, expanded: true))
		#expect(state.presentations["appended"] == nil)

		rows.insert(row("prepended", kind: .nick), at: 0)
		state.update(rows: rows, generalEventDisplay: .collapse, mutedNicknames: [], caseMapping: .rfc1459)
		#expect(state.presentations["prepended"] == .summary(kind: .generalEvents, count: 4, expanded: true))
		#expect(state.presentations["first"] == nil)

		rows.removeFirst(3)
		state.update(rows: rows, generalEventDisplay: .collapse, mutedNicknames: [], caseMapping: .rfc1459)
		#expect(state.presentations["appended"] == .summary(kind: .generalEvents, count: 1, expanded: true))
		state.toggle(summaryLineNumber: "appended")
		#expect(state.presentations["appended"] == .summary(kind: .generalEvents, count: 1, expanded: false))
	}

	@Test("Appending to a collapsed group changes its count and conceals the new row")
	func collapsedGroupStaysCollapsedAfterAppend() {
		let first = row("first", kind: .join)
		var state = TranscriptFoldingState()
		state.update(rows: [first], generalEventDisplay: .collapse, mutedNicknames: [], caseMapping: .rfc1459)
		let changed = state.update(
			rows: [first, row("second", kind: .quit)],
			generalEventDisplay: .collapse, mutedNicknames: [], caseMapping: .rfc1459
		)
		#expect(changed == ["first", "second"])
		#expect(state.presentations["first"] == .summary(kind: .generalEvents, count: 2, expanded: false))
		#expect(state.presentations["second"] == .hidden)
	}

	@Test("Incremental edge edits agree with a full regrouping while keeping expansion")
	func incrementalEdgesMatchFullRegrouping() {
		var rows = [row("first", kind: .join), row("second", kind: .part)]
		var state = TranscriptFoldingState()
		#expect(state.append(
			rows: rows, generalEventDisplay: .collapse, mutedNicknames: [], caseMapping: .rfc1459
		) == ["first", "second"])
		state.toggle(summaryLineNumber: "first")
		rows.append(contentsOf: [row("third", kind: .quit), row("visible")])
		#expect(state.append(
			rows: Array(rows.suffix(2)), generalEventDisplay: .collapse,
			mutedNicknames: [], caseMapping: .rfc1459
		) == ["first"])
		expectFullRegroupingAgrees(state, rows: rows)

		let older = [row("older", kind: .nick), row("oldest", kind: .mode)]
		rows.insert(contentsOf: older, at: 0)
		#expect(state.prepend(
			rows: older, generalEventDisplay: .collapse, mutedNicknames: [], caseMapping: .rfc1459
		) == ["older", "oldest", "first"])
		#expect(state.presentations["older"] == .summary(kind: .generalEvents, count: 5, expanded: true))
		expectFullRegroupingAgrees(state, rows: rows)

		let retired = Array(rows.prefix(3))
		rows.removeFirst(3)
		#expect(state.retire(rows: retired, firstRetainedRow: rows.first) == ["second"])
		#expect(state.presentations["second"] == .summary(kind: .generalEvents, count: 2, expanded: true))
		expectFullRegroupingAgrees(state, rows: rows)
		#expect(state.toggle(summaryLineNumber: "second") == ["second", "third"])
		#expect(state.presentations["third"] == .hidden)
	}

	@Test("Retiring a muted summary uses the new oldest sender spelling")
	func mutedSummarySpellingAfterRetirement() {
		let first = row("first", nickname: "ALICE")
		let second = row("second", nickname: "Alice")
		var state = TranscriptFoldingState()
		state.append(
			rows: [first, second], generalEventDisplay: .show,
			mutedNicknames: ["alice"], caseMapping: .rfc1459
		)
		#expect(state.retire(rows: [first], firstRetainedRow: second) == ["second"])
		#expect(state.presentations["second"] == .summary(
			kind: .mutedUser(normalizedNickname: "alice", displayNickname: "Alice"), count: 1, expanded: false
		))
		expectFullRegroupingAgrees(state, rows: [second], generalEventDisplay: .show, mutedNicknames: ["alice"])
	}

	@Test("A marker on the retained first row prevents an older batch from joining its group")
	func prependingRespectsExistingMarkerBoundary() {
		var marked = row("marked", kind: .join)
		marked.markers = [.unread("Unread")]
		var state = TranscriptFoldingState()
		state.append(
			rows: [marked, row("later", kind: .part)], generalEventDisplay: .collapse,
			mutedNicknames: [], caseMapping: .rfc1459
		)
		let older = row("older", kind: .quit)
		state.prepend(
			rows: [older], generalEventDisplay: .collapse,
			mutedNicknames: [], caseMapping: .rfc1459
		)
		#expect(state.presentations["older"] == .summary(kind: .generalEvents, count: 1, expanded: false))
		#expect(state.presentations["marked"] == .summary(kind: .generalEvents, count: 2, expanded: false))
		expectFullRegroupingAgrees(state, rows: [older, marked, row("later", kind: .part)])
	}

	@Test("A capped fold keeps its summary and identifiers after repeated append and trim")
	func cappedGroupSurvivesEdgeChurn() {
		let initial = (0 ..< 1100).map { row("row-\($0)", kind: .join) }
		var retained = ArraySlice(initial)
		var state = TranscriptFoldingState()
		state.append(
			rows: initial, generalEventDisplay: .collapse, mutedNicknames: [], caseMapping: .rfc1459
		)
		for number in 1100 ..< 2300 {
			let newest = row("row-\(number)", kind: .part)
			state.append(
				rows: [newest], generalEventDisplay: .collapse, mutedNicknames: [], caseMapping: .rfc1459
			)
			retained.append(newest)
			let oldest = retained.removeFirst()
			state.retire(rows: [oldest], firstRetainedRow: retained.first)
		}
		#expect(state.rowCount == 1100)
		#expect(state.presentations["row-1200"] == .summary(kind: .generalEvents, count: 1100, expanded: false))
		#expect(state.presentations["row-2299"] == .hidden)
		#expect(state.presentations["row-0"] == nil)
		expectFullRegroupingAgrees(state, rows: Array(retained))
		#expect(state.reveal(lineNumber: "row-2299").count == 1100)
	}

	@Test("Retired row identities cannot reopen a future group")
	func retiredExpansionsArePruned() {
		let first = row("first", kind: .join)
		var state = TranscriptFoldingState()
		state.update(rows: [first], generalEventDisplay: .collapse, mutedNicknames: [], caseMapping: .rfc1459)
		state.toggle(summaryLineNumber: "first")
		state.update(rows: [], generalEventDisplay: .collapse, mutedNicknames: [], caseMapping: .rfc1459)
		state.update(rows: [first], generalEventDisplay: .collapse, mutedNicknames: [], caseMapping: .rfc1459)
		#expect(state.presentations["first"] == .summary(kind: .generalEvents, count: 1, expanded: false))
	}

	@Test("Updating identical rows does not request a redraw and disabling folding restores them")
	func settingsChangesRemovePresentations() {
		let rows = [row("event", kind: .join), row("muted", nickname: "alice")]
		var state = TranscriptFoldingState()
		state.update(rows: rows, generalEventDisplay: .collapse, mutedNicknames: ["alice"], caseMapping: .rfc1459)
		#expect(state.update(rows: rows, generalEventDisplay: .collapse, mutedNicknames: ["alice"], caseMapping: .rfc1459).isEmpty)
		#expect(state.update(rows: rows, generalEventDisplay: .show, mutedNicknames: [], caseMapping: .rfc1459) == ["event", "muted"])
		#expect(state.presentations.isEmpty)
	}

	@Test("Clearing the transcript forgets expansion")
	func resetClearsExpansion() {
		let rows = [row("first", kind: .join)]
		var state = TranscriptFoldingState()
		state.update(rows: rows, generalEventDisplay: .collapse, mutedNicknames: [], caseMapping: .rfc1459)
		state.toggle(summaryLineNumber: "first")
		state.reset()
		#expect(state.presentations.isEmpty)
		state.update(rows: rows, generalEventDisplay: .collapse, mutedNicknames: [], caseMapping: .rfc1459)
		#expect(state.presentations["first"] == .summary(kind: .generalEvents, count: 1, expanded: false))
	}

	@Test("Muting again starts collapsed after a previously expanded mute was removed")
	func remutingResetsExpansion() {
		let rows = [row("message", nickname: "alice")]
		var state = TranscriptFoldingState()
		state.update(rows: rows, generalEventDisplay: .show, mutedNicknames: ["alice"], caseMapping: .rfc1459)
		state.toggle(summaryLineNumber: "message")
		state.update(rows: rows, generalEventDisplay: .show, mutedNicknames: [], caseMapping: .rfc1459)
		state.update(rows: rows, generalEventDisplay: .show, mutedNicknames: ["alice"], caseMapping: .rfc1459)
		#expect(state.presentations["message"] == .summary(
			kind: .mutedUser(normalizedNickname: "alice", displayNickname: "alice"), count: 1, expanded: false
		))
	}

	@Test("Hide conceals retained general events without making them expandable and Show restores them")
	func hidingRemovesExpandableGroups() {
		let rows = [row("first", kind: .join), row("second", kind: .part), row("visible")]
		var state = TranscriptFoldingState()
		state.update(rows: rows, generalEventDisplay: .collapse, mutedNicknames: [], caseMapping: .rfc1459)
		state.toggle(summaryLineNumber: "first")
		state.update(rows: rows, generalEventDisplay: .hide, mutedNicknames: [], caseMapping: .rfc1459)
		#expect(state.presentations["first"] == .hidden)
		#expect(state.presentations["second"] == .hidden)
		#expect(state.presentations["visible"] == nil)
		#expect(state.reveal(lineNumber: "second").isEmpty)
		#expect(state.toggle(summaryLineNumber: "first").isEmpty)
		state.update(rows: rows, generalEventDisplay: .show, mutedNicknames: [], caseMapping: .rfc1459)
		#expect(state.presentations.isEmpty)
		state.update(rows: rows, generalEventDisplay: .collapse, mutedNicknames: [], caseMapping: .rfc1459)
		#expect(state.presentations["first"] == .summary(kind: .generalEvents, count: 2, expanded: false))
	}

	private func row(_ identifier: String, kind: ChatLineKind = .privateMessage, nickname: String? = nil) -> TranscriptRow {
		TranscriptRow(
			lineNumber: identifier, receivedAt: Date(timeIntervalSince1970: 0), nickname: nickname,
			memberType: .normal, lineType: kind, command: "", messageIdentifier: nil, replyToMessageIdentifier: nil,
			deliveryState: .none, deliveryFailureReason: nil, reactions: [:], markers: [],
			body: TranscriptBody(plainText: identifier)
		)
	}

	private func expectFullRegroupingAgrees(
		_ state: TranscriptFoldingState,
		rows: [TranscriptRow],
		generalEventDisplay: GeneralEventMessageDisplay = .collapse,
		mutedNicknames: Set<String> = []
	) {
		var rebuilt = state
		rebuilt.update(
			rows: rows, generalEventDisplay: generalEventDisplay,
			mutedNicknames: mutedNicknames, caseMapping: .rfc1459
		)
		#expect(state.presentations == rebuilt.presentations)
		#expect(state.rowCount == rows.count)
	}
}
