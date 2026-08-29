/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
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
import Synchronization
import Testing

@MainActor
@Suite("Typing tracker")
struct IRCTypingTrackerTests {
	private let client: GLTTestClient
	private let tracker: IRCTypingTracker

	init() {
		let client = GLTTestClient()

		self.client = client
		tracker = IRCTypingTracker(client: client)
	}

	@Test("A tag value only names a state when it is spelled exactly")
	func stateParsing() {
		#expect(IRCTypingTracker.state(forTagValue: "active") == .active)
		#expect(IRCTypingTracker.state(forTagValue: "paused") == .paused)
		#expect(IRCTypingTracker.state(forTagValue: "ACTIVE") == .done)
		#expect(IRCTypingTracker.state(forTagValue: "done") == .done)
		#expect(IRCTypingTracker.state(forTagValue: nil) == .done)
	}

	@Test("Nicknames keep their first spelling and their arrival order, and a repeat is not announced")
	func orderingCaseFoldingAndNotificationSuppression() {
		let channel = makeChannel(named: "#chat")
		let start = Date(timeIntervalSince1970: 1000)
		let notificationCount = Mutex(0)
		let notifiedChannel = Mutex<Channel?>(nil)
		let token = NotificationCenter.default.addObserver(
			forName: .IRCTypingTrackerDidChange,
			object: client,
			queue: nil
		) { notification in
			notificationCount.withLock { count in
				count += 1
			}
			notifiedChannel.withLock { notifiedChannel in
				notifiedChannel = notification.userInfo?[IRCTypingTrackerChannelKey] as? Channel
			}
		}
		defer { NotificationCenter.default.removeObserver(token) }

		tracker.noteTypingState(.active, fromNickname: "Alice", in: channel, at: start)
		tracker.noteTypingState(.active, fromNickname: "bob", in: channel, at: start.addingTimeInterval(1))
		tracker.noteTypingState(.paused, fromNickname: "ALICE", in: channel, at: start.addingTimeInterval(2))
		tracker.noteTypingState(.paused, fromNickname: "alice", in: channel, at: start.addingTimeInterval(3))

		#expect(tracker.typingNicknames(in: channel, at: start.addingTimeInterval(4)) == ["Alice", "bob"])
		#expect(notificationCount.withLock { $0 } == 3)
		#expect(notifiedChannel.withLock { $0 === channel })
	}

	@Test("A state with no nickname is dropped without announcing anything")
	func emptyNicknameIsIgnored() {
		let channel = makeChannel(named: "#chat")
		let notificationCount = Mutex(0)
		let token = NotificationCenter.default.addObserver(
			forName: .IRCTypingTrackerDidChange,
			object: client,
			queue: nil
		) { _ in
			notificationCount.withLock { count in
				count += 1
			}
		}
		defer { NotificationCenter.default.removeObserver(token) }

		tracker.noteTypingState(.active, fromNickname: "", in: channel)

		#expect(tracker.typingNicknames(in: channel) == [])
		#expect(notificationCount.withLock { $0 } == 0)
	}

	@Test("Removing a nickname removes it from every channel, whatever case it was seen in")
	func removeNicknameAcrossChannels() {
		let firstChannel = makeChannel(named: "#one")
		let secondChannel = makeChannel(named: "#two")
		let start = Date()

		tracker.noteTypingState(.active, fromNickname: "Mara", in: firstChannel, at: start)
		tracker.noteTypingState(.paused, fromNickname: "mara", in: secondChannel, at: start)
		tracker.removeNickname("MARA")

		#expect(tracker.typingNicknames(in: firstChannel, at: start) == [])
		#expect(tracker.typingNicknames(in: secondChannel, at: start) == [])
	}

	@Test("An active entry expires before a paused one, and neither expires early")
	func timeoutBoundaryAndExplicitExpiry() {
		let channel = makeChannel(named: "#chat")
		let start = Date(timeIntervalSince1970: 1000)

		tracker.noteTypingState(.active, fromNickname: "active", in: channel, at: start)
		tracker.noteTypingState(.paused, fromNickname: "paused", in: channel, at: start)

		#expect(
			tracker.typingNicknames(in: channel, at: start.addingTimeInterval(6)) == ["active", "paused"]
		)

		tracker.expireEntries(at: start.addingTimeInterval(6.001))

		#expect(tracker.typingNicknames(in: channel, at: start.addingTimeInterval(30)) == ["paused"])

		tracker.expireEntries(at: start.addingTimeInterval(30.001))

		#expect(tracker.typingNicknames(in: channel, at: start) == [])
	}

	private func makeChannel(named name: String) -> Channel {
		let channel = Channel(config: ChannelConfig(channelName: name))

		channel.associatedClient = client

		return channel
	}
}
