// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

/// How far this connection has got with registering: the lines sent and the nickname on offer.
struct ConnectionRegistration {
	var gate = RegistrationGate.notStarted
	/// Which alternate nickname registration is on, and the one it sent.
	var nicknameRetry = NicknameRetry()
}

/** How far a connection has got with sending `CAP LS`, `PASS`, `NICK` and `USER`.

 The server password is often a bouncer's login, so it is held to the same
 rule as the account password: it goes only where the connection can vouch for
 the server. Bouncers expect `PASS` before registration completes, so the lines
 after it wait with it rather than go out without it. */
enum RegistrationGate: Equatable {
	/// Nothing has been sent on this connection yet.
	case notStarted
	/// The connection is to be TLS and the handshake has not finished.
	case awaitingTLS
	/// The user is being asked whether the password may go to a server whose
	/// certificate was not checked.
	case awaitingCredentialConsent
	/// The registration lines are on their way.
	case sent
}

/** Where registration is in working through the alternate nicknames.

 A server that refuses a nickname is answered with the next candidate, so the
 session has to remember which one it is on and what it last sent: the refusal
 names the nickname the server saw, not the one the user configured. */
struct NicknameRetry {
	/// How many alternates have been tried, zero before the first refusal.
	var attempt: UInt = 0
	/// The nickname the last `NICK` sent, which is what a refusal is about.
	var sentNickname: String?
}
