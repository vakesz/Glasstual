// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

/** Which transport failures become the reason a disconnect is reported with.

 Only a failure that ends a live connection is a reason. Closing cancels the
 host's writer and ends the dial, so the write that close interrupts fails
 too; reporting that failure turned a disconnect the owner asked for into an
 error. */
nonisolated enum DisconnectReason {
	/// Whether `error`, raised by a transport operation, is recorded as the
	/// reason for the disconnect that follows.
	static func records(_ error: any Error, closedByOwner: Bool, disconnecting: Bool) -> Bool {
		guard closedByOwner == false, disconnecting == false else { return false }

		return (error is CancellationError) == false
	}
}
