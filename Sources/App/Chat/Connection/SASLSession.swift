// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import os

/// Where an ECDSA-NIST256P-CHALLENGE exchange stands. The client carries the
/// key, so the session keeps it only while the exchange is running.
enum ECDSAChallengeExchange {
	/// The account name went out; the server's challenge is next.
	case sentIdentity(ECDSAChallengeClient)
	/// The signature went out; the server's verdict is next.
	case answered
}

/** One SASL exchange.

 The mechanisms the server offered, the one being tried, the ones already
 refused, and the payload waiting to be answered. It is a value the session
 owns: the exchange is per connection and is thrown away whole on a reset. */
struct SASLSession {
	var offeredMechanisms: [String]?
	var mechanism: String?
	var triedMechanisms: [String] = []
	var incomingPayload: String?
	var ecdsaExchange: ECDSAChallengeExchange?
	var scramTask: Task<Void, Never>?
	var scramSession: SCRAMClient? {
		didSet {
			// Every reset or replacement invalidates work from the old exchange.
			scramTask?.cancel()
			scramTask = nil
		}
	}

	/** Bounds the exchange.

	 A server that acknowledges `sasl` and then never answers `AUTHENTICATE`
	 leaves registration paused, and the only thing that ever noticed was the
	 four-minute retry timer taking the whole connection down. */
	let timeoutTimer: SessionTimer
}
