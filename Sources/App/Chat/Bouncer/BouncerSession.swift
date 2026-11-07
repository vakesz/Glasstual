// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// A `FAIL BOUNCER` reply: the code and the description the bouncer gave.
nonisolated struct BouncerFailure: Equatable, Sendable {
	let code: String
	let description: String
}

/** What a session knows about soju's bouncer networks.

 A connection is one of two kinds. The account connection, the parent, lists
 the account's networks and is where they are managed; ``networks`` is what it
 last heard. A network connection is bound to one of them and keeps only what
 the parent last said about it. */
struct BouncerSession {
	/// The parent's last known listing.
	var networks = BouncerNetworkSet()
	/// What the bouncer says a bound network's upstream connection is doing.
	var networkState: BouncerNetwork.State?
	var networkError: String?
	/// The newest failure of a management command, until the next command.
	var lastFailure: BouncerFailure?
}

struct ServerSessionBouncerNetworksDidChange: SubjectMessage {
	typealias Subject = ServerSession

	nonisolated static let name = Notification.Name("Glasstual.serverSessionBouncerNetworksDidChange")

	let subject: ServerSession
}
