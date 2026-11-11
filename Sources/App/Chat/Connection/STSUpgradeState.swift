// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

/// Strict transport security across one connection attempt and the upgrade it may trigger.
struct STSUpgradeState {
	/// Stops one connection attempt from upgrading twice.
	private(set) var performedUpgrade = false
	/// The policy this connection's `sts` capability stored, which teardown persists.
	var activePolicy: STSConnectionPolicy?
	/// The last plaintext-to-TLS upgrade attempt, cleared once TLS secures.
	/// A disconnect before that records the endpoint as failed for a cooldown.
	private(set) var lastAttempt: PendingIRCEndpoint?

	/// The server offered an upgrade. False when this attempt already upgraded.
	mutating func beginUpgrade(to endpoint: PendingIRCEndpoint) -> Bool {
		guard performedUpgrade == false else { return false }
		performedUpgrade = true
		lastAttempt = endpoint
		return true
	}

	/// TLS completed. Returns the upgrade attempt to report as succeeded.
	mutating func noteSecured() -> PendingIRCEndpoint? {
		performedUpgrade = false
		defer { lastAttempt = nil }
		return lastAttempt
	}

	/// The socket closed. Returns the upgrade attempt to report as failed: one
	/// that closed with an error before it was secured. A secured close forgets
	/// the attempt.
	mutating func noteDisconnect(withError: Bool, secured: Bool) -> PendingIRCEndpoint? {
		if let attempt = lastAttempt, withError, secured == false {
			lastAttempt = nil
			return attempt
		}
		if secured {
			lastAttempt = nil
		}
		return nil
	}

	/** Teardown: clears the upgrade flag and hands back the policy to persist.

	 The flag exists to stop one connection attempt from upgrading twice.
	 Clearing it only on a successful TLS handshake meant an upgrade that failed
	 to connect left it set for the life of the session object, and every later
	 STS offer from that server was ignored. The attempt it guards ends here.
	 The last attempt survives, so the disconnect that follows can report it. */
	mutating func resetForTeardown() -> STSConnectionPolicy? {
		performedUpgrade = false
		defer { activePolicy = nil }
		return activePolicy
	}
}
