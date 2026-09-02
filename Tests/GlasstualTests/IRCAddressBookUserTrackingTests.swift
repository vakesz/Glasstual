/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Address book user tracking")
struct IRCAddressBookUserTrackingTests {
	private let tracker: IRCAddressBookUserTrackingContainer

	init() {
		tracker = IRCAddressBookUserTrackingContainer(client: GLTTestClient())
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

	@Test("A client with no channels has no WHO batch to send")
	func whoBatchPolicyReturnsNoRangeForAnEmptyChannelList() {
		#expect(UserTrackingWhoBatchPolicy.indexRange(startingAt: 0, channelCount: 0) == nil)
	}

	@Test("A start index that no longer names a channel wraps to the first one")
	func whoBatchPolicyWrapsAStaleStartIndex() {
		#expect(UserTrackingWhoBatchPolicy.indexRange(startingAt: 20, channelCount: 3) == 0 ... 2)
	}

	/// The legacy scheduler walks the starting channel plus four more.
	@Test("A WHO batch spans five channels from the start index")
	func whoBatchPolicyPreservesLegacyFiveChannelWindow() {
		#expect(UserTrackingWhoBatchPolicy.indexRange(startingAt: 2, channelCount: 10) == 2 ... 6)
	}
}
