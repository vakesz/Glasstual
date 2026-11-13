// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Address book user tracking")
struct AddressBookUserTrackingTests {
	private let tracker: AddressBookUserTrackingContainer

	init() {
		tracker = AddressBookUserTrackingContainer()
	}

	private func trackingEntry(forNickname nickname: String) -> AddressBookEntry {
		var entry = AddressBookEntry.newUserTrackingEntry()
		entry.hostmask = nickname
		return entry
	}

	private func loggedInSession(tracking nicknames: [String]) -> TestServerSession {
		let session = TestServerSession(configDictionary: ["nickname": "me", "username": "me"])
		session.config.ignoreList = nicknames.map(trackingEntry(forNickname:))
		session.markAsLoggedIn()
		return session
	}

	@Test("Tracking matches without regard to case but keeps the nickname as added")
	func trackingIsCaseInsensitiveAndPreservesOriginalNickname() {
		let session = loggedInSession(tracking: ["Alice", "ALICE"])
		let tracker = session.trackedUsers

		session.populateISONTrackedUsersList()

		#expect(tracker.trackedUsers.count == 1)
		#expect(tracker.trackedUsers["Alice"] != nil)
		#expect(tracker.status(ofUser: "alice") == .notAvailable)

		tracker.status(ofTrackedNickname: "aLiCe", changedTo: .available)

		#expect(tracker.status(ofUser: "ALICE") == .available)
		#expect(tracker.trackedUsers["Alice"] == true)
	}

	@Test("Signing on adds an untracked user but signing off does not")
	func signedOnAddsUnknownUserButSignedOffDoesNot() {
		tracker.status(ofTrackedNickname: "new-user", changedTo: .signedOn)
		tracker.status(ofTrackedNickname: "absent", changedTo: .signedOff)

		#expect(tracker.status(ofUser: "NEW-USER") == .available)
		#expect(tracker.status(ofUser: "absent") == .unknown)
	}

	@Test("Removal announces the nickname as tracked, not the spelling configured")
	func removalUsesCanonicalNicknameInNotification() async {
		let session = loggedInSession(tracking: ["Alice"])
		let tracker = session.trackedUsers
		session.populateISONTrackedUsersList()
		session.config.ignoreList = [trackingEntry(forNickname: "ALICE")]
		session.populateISONTrackedUsersList()
		session.config.ignoreList = []
		let center = NotificationCenter.default

		await confirmation("The removal notification is posted") { removed in
			let token = center.addObserver(
				of: tracker,
				for: AddressBookTrackedUserRemoved.self
			) { message in
				#expect(message.nickname == "Alice")
				removed()
			}
			defer { center.removeObserver(token) }

			session.populateISONTrackedUsersList()
		}

		#expect(tracker.trackedUsers.isEmpty)
	}

	@Test("Clearing announces itself and leaves nobody tracked")
	func clearPostsNotificationAndRemovesAllUsers() async {
		tracker.addTrackedUser(canonical: "Alice")
		tracker.addTrackedUser(canonical: "Bob")
		let center = NotificationCenter.default

		await confirmation("The cleared notification is posted") { cleared in
			let token = center.addObserver(
				of: tracker,
				for: AddressBookTrackedUsersCleared.self
			) { _ in
				cleared()
			}
			defer { center.removeObserver(token) }

			tracker.clearTrackedUsers()
		}

		#expect(tracker.trackedUsers.isEmpty)
	}

	@Test("A session with no channels has no WHO batch to send")
	func whoBatchPolicyReturnsNoRangeForAnEmptyChannelList() {
		#expect(UserTrackingWhoBatchPolicy.indexRange(startingAt: 0, conversationCount: 0) == nil)
	}

	@Test("A start index that no longer names a channel wraps to the first one")
	func whoBatchPolicyWrapsAStaleStartIndex() {
		#expect(UserTrackingWhoBatchPolicy.indexRange(startingAt: 20, conversationCount: 3) == 0 ... 2)
	}

	/// The legacy scheduler walks the starting channel plus four more.
	@Test("A WHO batch spans five channels from the start index")
	func whoBatchPolicyPreservesLegacyFiveChannelWindow() {
		#expect(UserTrackingWhoBatchPolicy.indexRange(startingAt: 2, conversationCount: 10) == 2 ... 6)
	}
}

@MainActor
@Suite("Address book tracking messages")
struct AddressBookTrackingMessageTests {
	@Test("A status change carries the nickname and a typed status")
	func statusChangeRoundTrips() throws {
		let tracker = AddressBookUserTrackingContainer()
		let notification = AddressBookTrackingStatusChanged.makeNotification(
			AddressBookTrackingStatusChanged(subject: tracker, nickname: "Alice", status: .away)
		)

		let message = try #require(AddressBookTrackingStatusChanged.makeMessage(notification))
		#expect(message.subject === tracker)
		#expect(message.nickname == "Alice")
		#expect(message.status == .away)
		#expect(notification.userInfo?["status"] as? UInt == AddressBookUserTrackingStatus.away.rawValue)
	}

	@Test("Adding a tracked user announces the nickname")
	func additionCarriesNickname() {
		let tracker = AddressBookUserTrackingContainer()
		var nicknames: [String] = []
		let token = NotificationCenter.default.addObserver(
			of: tracker,
			for: AddressBookTrackedUserAdded.self
		) { nicknames.append($0.nickname) }
		defer { NotificationCenter.default.removeObserver(token) }

		tracker.addTrackedUser(canonical: "Bob")

		#expect(nicknames == ["Bob"])
	}
}
