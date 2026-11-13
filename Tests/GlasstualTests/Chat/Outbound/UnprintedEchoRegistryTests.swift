// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Unprinted echo registry")
struct UnprintedEchoRegistryTests {
	private let start = ContinuousClock.now

	private func record(
		_ registry: inout UnprintedEchoRegistry,
		target: String,
		text: String,
		lineType: ChatLineKind = .privateMessage
	) {
		registry.record(target: target, text: text, lineType: lineType, caseMapping: .rfc1459, now: start)
	}

	private func consume(
		_ registry: inout UnprintedEchoRegistry,
		target: String,
		text: String,
		lineType: ChatLineKind = .privateMessage,
		after delay: Duration = .zero
	) -> Bool {
		registry.consume(target: target, text: text, lineType: lineType, caseMapping: .rfc1459, now: start + delay)
	}

	@Test("A recorded message matches one echo, under the server's casemapping", arguments: [
		("NickServ", "nickserv"),
		("[a]", "{a}"),
	])
	func matchesOnceUnderCasemapping(_ sent: String, _ echoed: String) {
		var registry = UnprintedEchoRegistry()
		record(&registry, target: sent, text: "IDENTIFY x")

		let first = consume(&registry, target: echoed, text: "IDENTIFY x")
		let second = consume(&registry, target: echoed, text: "IDENTIFY x")

		#expect(first)
		#expect(second == false)
	}

	@Test("A different target, text or line type does not match")
	func differentTextOrTypeDoesNotMatch() {
		var registry = UnprintedEchoRegistry()
		record(&registry, target: "#chat", text: "hello")

		let otherText = consume(&registry, target: "#chat", text: "hello!")
		let otherType = consume(&registry, target: "#chat", text: "hello", lineType: .action)
		let otherTarget = consume(&registry, target: "#other", text: "hello")
		let same = consume(&registry, target: "#chat", text: "hello")

		#expect(otherText == false)
		#expect(otherType == false)
		#expect(otherTarget == false)
		#expect(same)
	}

	@Test("An entry lapses its lifetime after the line is written")
	func expiredEntryDoesNotMatch() {
		var registry = UnprintedEchoRegistry()
		record(&registry, target: "alice", text: "hi", lineType: .notice)
		registry.noteWritten(target: "alice", text: "hi", lineType: .notice, caseMapping: .rfc1459, now: start)

		let matched = consume(&registry, target: "alice", text: "hi", lineType: .notice, after: UnprintedEchoRegistry.lifetime)

		#expect(matched == false)
		#expect(registry.isEmpty)
	}

	/** A long paste waits in flood control for longer than an entry lives, so
	 the lifetime counts from the write, not from when the line was produced. */
	@Test("A line still queued does not lapse, and its lifetime starts when it is written")
	func lifetimeStartsAtTheWrite() {
		var registry = UnprintedEchoRegistry()
		record(&registry, target: "alice", text: "first")
		record(&registry, target: "alice", text: "second")
		let written = start + .seconds(300)
		registry.noteWritten(target: "Alice", text: "first", lineType: .privateMessage, caseMapping: .rfc1459, now: written)

		let first = consume(&registry, target: "alice", text: "first", after: .seconds(300) + UnprintedEchoRegistry.lifetime / 2)
		let queued = consume(&registry, target: "alice", text: "second", after: .seconds(3600))

		#expect(first)
		#expect(queued)
	}

	@Test("An echo carrying the label of a recorded message matches it, whatever its text")
	func labelMatches() {
		var registry = UnprintedEchoRegistry()
		registry.record(target: "alice", text: "hi", lineType: .privateMessage, label: "g7", caseMapping: .rfc1459, now: start)
		registry.noteWritten(label: "g7", now: start)

		let otherLabel = registry.consume(label: "g8", now: start)
		let matched = registry.consume(label: "g7", now: start)

		#expect(otherLabel == false)
		#expect(matched)
		#expect(registry.isEmpty)
	}

	@Test("A full registry keeps every waiting entry and refuses the next one")
	func fullRegistryRefusesInsteadOfEvicting() {
		var registry = UnprintedEchoRegistry()
		for index in 0 ..< UnprintedEchoRegistry.capacity {
			record(&registry, target: "alice", text: "line \(index)")
		}

		let refused = registry.record(
			target: "alice", text: "one more", lineType: .privateMessage, caseMapping: .rfc1459, now: start
		)
		let oldest = consume(&registry, target: "alice", text: "line 0")
		let room = registry.record(
			target: "alice", text: "one more", lineType: .privateMessage, caseMapping: .rfc1459, now: start
		)

		#expect(refused == false)
		#expect(oldest)
		#expect(room)
	}

	@Test("Written entries that are never echoed make room once they lapse")
	func lapsedEntriesMakeRoom() {
		var registry = UnprintedEchoRegistry()
		for index in 0 ..< UnprintedEchoRegistry.capacity {
			record(&registry, target: "alice", text: "line \(index)")
			registry.noteWritten(target: "alice", text: "line \(index)", lineType: .privateMessage, caseMapping: .rfc1459, now: start)
		}

		let accepted = registry.record(
			target: "alice", text: "later", lineType: .privateMessage, caseMapping: .rfc1459,
			now: start + UnprintedEchoRegistry.lifetime
		)

		#expect(accepted)
	}
}
