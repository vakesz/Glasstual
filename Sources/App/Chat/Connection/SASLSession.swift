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

/// Where an OAUTHBEARER exchange stands.
enum OAuthBearerExchange: Equatable {
	/// The token went out; the server's verdict is next.
	case sentInitialResponse
	/// The server answered with an error, which was acknowledged; its 904 is next.
	case acknowledgedError(OAuthBearerFailure?)
}

/// Whether the exchange signs in during registration or again afterwards.
enum SASLExchangePhase: Equatable {
	case registration
	/// SASL 3.2 re-authentication on a registered connection. `wasIdentified`
	/// is restored if it fails; `explicit` is the one mechanism the user asked
	/// for, which gets no fallback.
	case reauthentication(wasIdentified: Bool, explicit: SASLMechanism?)
}

/// A re-authentication waiting for the server to acknowledge `sasl`.
struct SASLReauthenticationRequest: Equatable {
	let explicit: SASLMechanism?
}

/// Where the last exchange of this connection stands, for the sign-in sheet.
enum SASLExchangeStatus: Equatable {
	case idle
	case inProgress(SASLMechanism)
	case succeeded(account: String?, mechanism: SASLMechanism)
	case failed(reason: String)
}

/** One SASL exchange.

 The mechanisms the server offered, the one being tried, the ones already
 refused, and the payload waiting to be answered. It is a value the session
 owns: the exchange is per connection and is thrown away whole on a reset. */
struct SASLSession {
	/// Raw, because sasl-3.2 has clients tolerate names they do not know.
	var offeredMechanisms: [String]?
	var mechanism: SASLMechanism?
	var triedMechanisms: [SASLMechanism] = []
	/// The mechanism of the last exchange that succeeded on this connection.
	var lastAuthenticatedMechanism: SASLMechanism?
	var phase = SASLExchangePhase.registration
	var pendingReauthentication: SASLReauthenticationRequest?
	var status = SASLExchangeStatus.idle
	var incomingPayload: String?
	var ecdsaExchange: ECDSAChallengeExchange?
	var oauthExchange: OAuthBearerExchange?
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
