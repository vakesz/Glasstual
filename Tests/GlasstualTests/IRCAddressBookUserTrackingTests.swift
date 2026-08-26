@testable import Glasstual
import XCTest

/// Preprocessor directives found in file:
/// #import <XCTest/XCTest.h>
/// #import "GLTTestClient.h"
/// #import "IRCAddressBookUserTrackingPrivate.h"
/** *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
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
class IRCAddressBookUserTrackingTests: XCTestCase {
	private var tracker: IRCAddressBookUserTrackingContainer!

	override func setUp() {
		super.setUp()
		tracker = IRCAddressBookUserTrackingContainer(client: GLTTestClient())
	}

	func testTrackingIsCaseInsensitiveAndPreservesOriginalNickname() {
		tracker.addTrackedUser("Alice")
		tracker.addTrackedUser("ALICE")

		XCTAssertEqual(tracker.trackedUsers.count, 1)
		XCTAssertNotNil(tracker.trackedUsers["Alice"])
		XCTAssertEqual(tracker.status(ofUser: "alice"), .notAvailable)

		tracker.status(ofTrackedNickname: "aLiCe", changedTo: .available)

		XCTAssertEqual(tracker.status(ofUser: "ALICE"), .available)
		XCTAssertEqual(tracker.trackedUsers["Alice"], true)
	}

	func testSignedOnAddsUnknownUserButSignedOffDoesNot() {
		tracker.status(ofTrackedNickname: "new-user", changedTo: .signedOn)
		tracker.status(ofTrackedNickname: "absent", changedTo: .signedOff)

		XCTAssertEqual(tracker.status(ofUser: "NEW-USER"), .available)
		XCTAssertEqual(tracker.status(ofUser: "absent"), .unknown)
	}

	func testRemovalUsesCanonicalNicknameInNotification() {
		tracker.addTrackedUser("Alice")
		let expectation = expectation(
			forNotification: .IRCAddressBookUserTrackingRemovedTrackedUser,
			object: tracker
		) { notification in
			notification.userInfo?["nickname"] as? String == "Alice"
		}

		tracker.removeTrackedUser("ALICE")

		wait(for: [expectation], timeout: 1)
		XCTAssertTrue(tracker.trackedUsers.isEmpty)
	}

	func testClearPostsNotificationAndRemovesAllUsers() {
		tracker.addTrackedUser("Alice")
		tracker.addTrackedUser("Bob")
		let expectation = expectation(
			forNotification: .IRCAddressBookUserTrackingRemovedAllTrackedUsers,
			object: tracker
		)

		tracker.clearTrackedUsers()

		wait(for: [expectation], timeout: 1)
		XCTAssertTrue(tracker.trackedUsers.isEmpty)
	}
}
