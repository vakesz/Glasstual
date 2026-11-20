// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import Testing

/** A disconnect the owner asked for carries no error, and a write that the
 close interrupts must not supply one. */
@Suite("Disconnect reason")
nonisolated struct DisconnectReasonTests {
	private static let reset = NSError(domain: NSPOSIXErrorDomain, code: Int(ECONNRESET))

	@Test("A failure on a live connection is the reason for its disconnect")
	func liveFailureIsRecorded() {
		#expect(DisconnectReason.records(Self.reset, closedByOwner: false, disconnecting: false))
	}

	@Test("A cancelled write is never the reason, whatever the connection's state", arguments: [
		(false, false), (true, false), (false, true), (true, true),
	])
	func cancellationIsNotRecorded(closedByOwner: Bool, disconnecting: Bool) {
		#expect(DisconnectReason.records(
			CancellationError(), closedByOwner: closedByOwner, disconnecting: disconnecting
		) == false)
	}

	@Test("A failure after the owner closed the connection is not the reason")
	func failureAfterOwnerCloseIsNotRecorded() {
		#expect(DisconnectReason.records(Self.reset, closedByOwner: true, disconnecting: false) == false)
		#expect(DisconnectReason.records(Self.reset, closedByOwner: true, disconnecting: true) == false)
	}

	@Test("A failure while a disconnect is under way is not the reason")
	func failureWhileDisconnectingIsNotRecorded() {
		#expect(DisconnectReason.records(Self.reset, closedByOwner: false, disconnecting: true) == false)
	}
}
