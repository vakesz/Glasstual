// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Transcript redaction ledger")
struct TranscriptRedactionLedgerTests {
	@Test("A recorded deletion is found, and only once news")
	func recordsOnce() {
		var ledger = TranscriptRedactionLedger()

		let first = ledger.record("msg-1")
		let second = ledger.record("msg-1")
		#expect(first)
		#expect(second == false)
		#expect(ledger.contains("msg-1"))
		#expect(ledger.contains("msg-2") == false)
		#expect(ledger.contains(nil) == false)
		#expect(ledger.contains("") == false)
	}

	@Test("An empty identifier is never recorded")
	func ignoresEmptyIdentifiers() {
		var ledger = TranscriptRedactionLedger()

		let recorded = ledger.record("")
		#expect(recorded == false)
		#expect(ledger.all.isEmpty)
	}

	@Test("Identifiers compare byte for byte")
	func identifiersAreCaseSensitive() {
		var ledger = TranscriptRedactionLedger()
		ledger.record("Msg-1")

		#expect(ledger.contains("msg-1") == false)
	}

	@Test("The oldest deletion goes first beyond the capacity")
	func evictsTheOldest() {
		var ledger = TranscriptRedactionLedger()
		for index in 0 ... TranscriptRedactionLedger.capacity {
			ledger.record("msg-\(index)")
		}

		#expect(ledger.all.count == TranscriptRedactionLedger.capacity)
		#expect(ledger.contains("msg-0") == false)
		#expect(ledger.contains("msg-\(TranscriptRedactionLedger.capacity)"))
	}

	@Test("Clearing forgets everything")
	func removeAllForgets() {
		var ledger = TranscriptRedactionLedger()
		ledger.record("msg-1")

		ledger.removeAll()

		#expect(ledger.contains("msg-1") == false)
		#expect(ledger.all.isEmpty)
	}
}
