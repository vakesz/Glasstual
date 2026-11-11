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

	@Test("An entry past its lifetime does not match")
	func expiredEntryDoesNotMatch() {
		var registry = UnprintedEchoRegistry()
		record(&registry, target: "alice", text: "hi", lineType: .notice)

		let matched = consume(&registry, target: "alice", text: "hi", lineType: .notice, after: UnprintedEchoRegistry.lifetime)

		#expect(matched == false)
		#expect(registry.isEmpty)
	}

	@Test("The oldest entry goes once the registry is full")
	func oldestEntryIsEvicted() {
		var registry = UnprintedEchoRegistry()
		for index in 0 ... UnprintedEchoRegistry.capacity {
			record(&registry, target: "alice", text: "line \(index)")
		}

		let oldest = consume(&registry, target: "alice", text: "line 0")
		let second = consume(&registry, target: "alice", text: "line 1")
		let newest = consume(&registry, target: "alice", text: "line \(UnprintedEchoRegistry.capacity)")

		#expect(oldest == false)
		#expect(second)
		#expect(newest)
	}
}
