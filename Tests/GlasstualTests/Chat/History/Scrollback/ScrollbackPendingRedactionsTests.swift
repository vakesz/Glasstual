// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

/// The redactions a view waits to apply are evicted oldest first.
@MainActor
@Suite("Scrollback pending redactions")
struct ScrollbackPendingRedactionsTests {
	private func pending(_ identifiers: [MessageIdentifierKey], limit: Int = 3) -> ScrollbackPendingRedactions {
		var pending = ScrollbackPendingRedactions(limit: limit)
		for identifier in identifiers {
			pending.insert(identifier)
		}
		return pending
	}

	@Test("Past the limit, the identifier that has waited longest goes first")
	func evictsTheOldest() {
		let redactions = pending(["a", "b", "c", "d"])

		#expect(!redactions.contains("a"))
		#expect(redactions.contains("b"))
		#expect(redactions.contains("c"))
		#expect(redactions.contains("d"))
		#expect(redactions.count == 3)
	}

	@Test("An identifier asked for again keeps its place and is not counted twice")
	func reinsertingKeepsThePlace() {
		var redactions = pending(["a", "b", "c"])

		redactions.insert("a")
		#expect(redactions.count == 3)
		redactions.insert("d")

		#expect(!redactions.contains("a"))
		#expect(redactions.contains("b"))
		#expect(redactions.contains("d"))
	}

	@Test("A removed identifier leaves the order of the rest intact")
	func removalKeepsTheOrder() {
		var redactions = pending(["b", "c", "d"])

		redactions.remove("c")
		redactions.insert("e")
		#expect(redactions.contains("b"))
		redactions.insert("f")
		#expect(!redactions.contains("b"))
		#expect(redactions.contains("d"))
		redactions.insert("g")

		#expect(!redactions.contains("d"))
		#expect(redactions.contains("e"))
		#expect(redactions.contains("f"))
		#expect(redactions.contains("g"))
	}

	@Test("Removing the last identifier leaves the set empty")
	func removingEverythingEmpties() {
		var redactions = pending(["a"])

		redactions.remove("a")
		redactions.remove("missing")

		#expect(redactions.isEmpty)
	}
}
