/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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

import XCTest

final class IRCTypingTrackerTests: XCTestCase {
	private var client: GLTTestClient!
	private var tracker: IRCTypingTracker!

	override func setUp() {
		super.setUp()

		client = GLTTestClient()
		tracker = IRCTypingTracker(client: client)
	}

	override func tearDown() {
		tracker.removeAll()
		tracker = nil
		client = nil

		super.tearDown()
	}

	func testStateParsing() {
		XCTAssertEqual(IRCTypingTracker.state(forTagValue: "active"), .active)
		XCTAssertEqual(IRCTypingTracker.state(forTagValue: "paused"), .paused)
		XCTAssertEqual(IRCTypingTracker.state(forTagValue: "ACTIVE"), .done)
		XCTAssertEqual(IRCTypingTracker.state(forTagValue: "done"), .done)
		XCTAssertEqual(IRCTypingTracker.state(forTagValue: nil), .done)
	}

	func testOrderingCaseFoldingAndNotificationSuppression() {
		let channel = makeChannel(named: "#chat")
		let start = Date(timeIntervalSince1970: 1000)
		var notificationCount = 0
		var notifiedChannel: IRCChannel?
		let token = NotificationCenter.default.addObserver(
			forName: .IRCTypingTrackerDidChange,
			object: client,
			queue: nil
		) { notification in
			notificationCount += 1
			notifiedChannel = notification.userInfo?[IRCTypingTrackerChannelKey] as? IRCChannel
		}
		defer { NotificationCenter.default.removeObserver(token) }

		tracker.note(.active, fromNickname: "Alice", in: channel, at: start)
		tracker.note(.active, fromNickname: "bob", in: channel, at: start.addingTimeInterval(1))
		tracker.note(.paused, fromNickname: "ALICE", in: channel, at: start.addingTimeInterval(2))
		tracker.note(.paused, fromNickname: "alice", in: channel, at: start.addingTimeInterval(3))

		XCTAssertEqual(tracker.typingNicknames(in: channel, at: start.addingTimeInterval(4)), ["Alice", "bob"])
		XCTAssertEqual(notificationCount, 3)
		XCTAssertTrue(notifiedChannel === channel)
	}

	func testEmptyNicknameIsIgnored() {
		let channel = makeChannel(named: "#chat")
		var notificationCount = 0
		let token = NotificationCenter.default.addObserver(
			forName: .IRCTypingTrackerDidChange,
			object: client,
			queue: nil
		) { _ in
			notificationCount += 1
		}
		defer { NotificationCenter.default.removeObserver(token) }

		tracker.note(.active, fromNickname: "", in: channel)

		XCTAssertEqual(tracker.typingNicknames(in: channel), [])
		XCTAssertEqual(notificationCount, 0)
	}

	func testRemoveNicknameAcrossChannels() {
		let firstChannel = makeChannel(named: "#one")
		let secondChannel = makeChannel(named: "#two")
		let start = Date()

		tracker.note(.active, fromNickname: "Mara", in: firstChannel, at: start)
		tracker.note(.paused, fromNickname: "mara", in: secondChannel, at: start)
		tracker.removeNickname("MARA")

		XCTAssertEqual(tracker.typingNicknames(in: firstChannel, at: start), [])
		XCTAssertEqual(tracker.typingNicknames(in: secondChannel, at: start), [])
	}

	func testTimeoutBoundaryAndExplicitExpiry() {
		let channel = makeChannel(named: "#chat")
		let start = Date(timeIntervalSince1970: 1000)

		tracker.note(.active, fromNickname: "active", in: channel, at: start)
		tracker.note(.paused, fromNickname: "paused", in: channel, at: start)

		XCTAssertEqual(
			tracker.typingNicknames(in: channel, at: start.addingTimeInterval(6)),
			["active", "paused"]
		)

		tracker.expireEntries(at: start.addingTimeInterval(6.001))

		XCTAssertEqual(tracker.typingNicknames(in: channel, at: start.addingTimeInterval(30)), ["paused"])

		tracker.expireEntries(at: start.addingTimeInterval(30.001))

		XCTAssertEqual(tracker.typingNicknames(in: channel, at: start), [])
	}

	private func makeChannel(named name: String) -> IRCChannel {
		let channel = IRCChannel(configDictionary: ["channelName": name])

		channel.setValue(client, forKey: "associatedClient")

		return channel
	}
}
