// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// `extended-monitor`: AWAY, ACCOUNT and CHGHOST arrive for monitored people
/// who share no channel with the session.
@MainActor
@Suite("Extended monitor")
struct ServerSessionExtendedMonitorTests {
	private func session(extendedMonitor: Bool = true) -> TestServerSession {
		let session = TestServerSession(configDictionary: ["nickname": "me", "username": "me"])
		session.userNickname = "me"
		session.forwardsProcessedMessages = true
		session.enableCapability(.awayNotify)
		session.enableCapability(.accountNotify)
		session.enableCapability(.changeHost)
		session.enableCapability(.monitorCommand)
		if extendedMonitor {
			session.enableCapability(.extendedMonitor)
		}
		session.trackedUsers.addTrackedUser("alice")
		return session
	}

	private func receive(_ line: String, on session: TestServerSession) throws {
		let message = try #require(Message(line: line, on: session))
		session.processIncomingMessage(message)
	}

	@Test("A line from a monitored nickname marks it available", arguments: [
		":alice!a@h AWAY :gone",
		":alice!a@h ACCOUNT alice",
		":alice!a@h CHGHOST newuser new.example.org",
	])
	func monitoredActivityMarksAvailable(_ line: String) throws {
		let session = session()
		#expect(session.trackedUsers.status(ofUser: "alice") == .notAvailable)

		try receive(line, on: session)

		#expect(session.trackedUsers.status(ofUser: "alice") == .available)
	}

	@Test("A nickname the address book does not track is left alone")
	func untrackedNicknameIsIgnored() throws {
		let session = session()

		try receive(":bob!b@h AWAY :gone", on: session)

		#expect(session.trackedUsers.status(ofUser: "bob") == .unknown)
	}

	@Test("Without the capability the tracker is not touched")
	func ungatedLineIsIgnored() throws {
		let session = session(extendedMonitor: false)

		try receive(":alice!a@h AWAY :gone", on: session)

		#expect(session.trackedUsers.status(ofUser: "alice") == .notAvailable)
	}

	@Test("An AWAY report is recorded as the tracker's away status")
	func awayStatusIsReported() throws {
		let session = session()
		var reported: [AddressBookUserTrackingStatus] = []
		let token = NotificationCenter.default.addObserver(
			of: session.trackedUsers,
			for: AddressBookTrackingStatusChanged.self
		) { message in
			reported.append(message.status)
		}
		defer { NotificationCenter.default.removeObserver(token) }

		try receive(":alice!a@h AWAY :gone", on: session)
		try receive(":alice!a@h AWAY", on: session)

		#expect(reported == [.available, .away, .notAway])
	}
}
