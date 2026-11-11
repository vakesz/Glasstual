// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// Collects the profile change messages one session posts.
@MainActor
final class ProfileChangeLog {
	private(set) var messages: [SessionProfilesDidChange] = []
	private let subscriptions = NotificationSubscriptions()

	init(_ session: ServerSession) {
		subscriptions.observe(SessionProfilesDidChange.self, of: session) { [weak self] message in
			self?.messages.append(message)
		}
	}
}

/** A logged-in session that negotiated `batch` and `draft/metadata-2`, in
 `#c` with `peer` and `spoof`. */
@MainActor
func makeMetadataSession(
	offer: String = "batch draft/metadata-2",
	showsServerProfiles: Bool = true,
	joined: Bool = true
) throws -> TestServerSession {
	var settings = ChatSettings.current()
	settings.showsServerProfiles = showsServerProfiles
	let session = TestServerSession(
		configDictionary: [:], nicknamePassword: nil, fixture: ChatEnvironmentFixture(settings: settings)
	)
	session.config.nickname = "ada"
	session.config.serverProfile = nil
	session.setConnectionTransportForTesting(.connected)
	session.userNickname = "ada"
	try session.negotiate(offer)
	try session.receive(":irc.example.net 001 ada :Welcome")
	if joined {
		try session.receive(":ada!a@host JOIN #c")
		try session.receive(":irc.example.net 353 ada = #c :ada peer spoof")
		try session.receive(":irc.example.net 366 ada #c :End of NAMES")
	}
	return session
}
