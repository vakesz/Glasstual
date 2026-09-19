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

	@Test("Tracking matches without regard to case but keeps the nickname as added")
	func trackingIsCaseInsensitiveAndPreservesOriginalNickname() {
		tracker.addTrackedUser("Alice")
		tracker.addTrackedUser("ALICE")

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

	@Test("Removal announces the nickname as tracked, not the spelling passed in")
	func removalUsesCanonicalNicknameInNotification() async {
		tracker.addTrackedUser("Alice")
		let center = NotificationCenter.default

		await confirmation("The removal notification is posted") { removed in
			let token = center.addObserver(
				forName: .addressBookTrackingRemovedUser,
				object: tracker,
				queue: nil
			) { notification in
				#expect(notification.userInfo?[addressBookTrackingNicknameKey] as? String == "Alice")
				removed()
			}
			defer { center.removeObserver(token) }

			tracker.removeTrackedUser("ALICE")
		}

		#expect(tracker.trackedUsers.isEmpty)
	}

	@Test("Clearing announces itself and leaves nobody tracked")
	func clearPostsNotificationAndRemovesAllUsers() async {
		tracker.addTrackedUser("Alice")
		tracker.addTrackedUser("Bob")
		let center = NotificationCenter.default

		await confirmation("The cleared notification is posted") { cleared in
			let token = center.addObserver(
				forName: .addressBookTrackingRemovedAllUsers,
				object: tracker,
				queue: nil
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
