// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@Suite("CHATHISTORY requests")
struct ChatHistoryCommandTests {
	private nonisolated static let date = Date(timeIntervalSince1970: 1_793_260_800.123) // 2026-10-29T08:00:00.123Z
	private nonisolated static let stamp = "timestamp=2026-10-29T08:00:00.123Z"
	private nonisolated static let both = ChatHistoryReferenceSupport()

	@Test("Every subcommand writes its parameters", arguments: [
		(ChatHistoryCommand.latest(target: "#c", after: .unbounded, limit: 50), ["LATEST", "#c", "*", "50"]),
		(.latest(target: "#c", after: .timestamp(date), limit: 50), ["LATEST", "#c", stamp, "50"]),
		(.before(target: "#c", .messageIdentifier("abc"), limit: 10), ["BEFORE", "#c", "msgid=abc", "10"]),
		(.after(target: "bob", .timestamp(date), limit: 10), ["AFTER", "bob", stamp, "10"]),
		(.around(target: "#c", .messageIdentifier("x"), limit: 100), ["AROUND", "#c", "msgid=x", "100"]),
		(.between(target: "#c", .messageIdentifier("a"), .timestamp(date), limit: 5), ["BETWEEN", "#c", "msgid=a", stamp, "5"]),
		(.targets(from: date, to: date, limit: 50), ["TARGETS", stamp, stamp, "50"]),
	])
	func argumentLists(_ command: ChatHistoryCommand, _ expected: [String]) throws {
		#expect(try command.arguments(support: Self.both) == expected)
	}

	@Test("A star is only accepted by LATEST")
	func starOnlyInLatest() {
		#expect(throws: ChatHistoryCommandError.unboundedNotAllowed) {
			try ChatHistoryCommand.before(target: "#c", .unbounded, limit: 1).arguments(support: Self.both)
		}
		#expect(throws: ChatHistoryCommandError.unboundedNotAllowed) {
			try ChatHistoryCommand.between(target: "#c", .timestamp(Self.date), .unbounded, limit: 1).arguments(support: Self.both)
		}
	}

	@Test("A message identifier is refused where the server takes only timestamps, and preferred falls back")
	func messageIdentifierSupport() {
		let timestampsOnly = ChatHistoryReferenceSupport(timestamps: true, messageIdentifiers: false)
		#expect(throws: ChatHistoryCommandError.unsupportedReference) {
			try ChatHistoryCommand.after(target: "#c", .messageIdentifier("a"), limit: 1).arguments(support: timestampsOnly)
		}
		#expect(ChatHistoryReference
			.preferred(messageIdentifier: "a", timestamp: Self.date, support: timestampsOnly) == .timestamp(Self.date))
		#expect(ChatHistoryReference.preferred(messageIdentifier: "a", timestamp: Self.date, support: Self.both) == .messageIdentifier("a"))
		#expect(ChatHistoryReference.preferred(
			messageIdentifier: nil,
			timestamp: Self.date,
			support: ChatHistoryReferenceSupport(timestamps: false, messageIdentifiers: true)
		) == nil)
	}

	@Test("A message identifier that would break the line is refused", arguments: [":abc", "a b", "a\rb", ""])
	func invalidMessageIdentifiers(_ identifier: String) {
		#expect(throws: ChatHistoryCommandError.invalidMessageIdentifier) {
			try ChatHistoryCommand.before(target: "#c", .messageIdentifier(identifier), limit: 1).arguments(support: Self.both)
		}
	}

	@Test("A limit of zero and an empty target are refused")
	func limitAndTarget() {
		#expect(throws: ChatHistoryCommandError.invalidLimit) {
			try ChatHistoryCommand.latest(target: "#c", after: .unbounded, limit: 0).arguments(support: Self.both)
		}
		#expect(throws: ChatHistoryCommandError.emptyTarget) {
			try ChatHistoryCommand.latest(target: "", after: .unbounded, limit: 1).arguments(support: Self.both)
		}
	}

	@Test("The limit is clamped to the server's maximum, where it has one", arguments: [
		(UInt(100), UInt(0), UInt(100)), (100, 50, 50), (500, 1000, 500), (100, 1000, 100), (0, 0, 1),
	])
	func clamp(_ requested: UInt, _ maximum: UInt, _ expected: UInt) {
		#expect(ChatHistoryLimit.clamp(requested, serverMaximum: maximum) == expected)
	}
}
