import XCTest

// Preprocessor directives found in file:
// #import <XCTest/XCTest.h>
// #import "GLTTestClient.h"
// #import "IRCChannelPrivate.h"
// #import "IRCTreeItemPrivate.h"
// #import "IRCTypingTrackerPrivate.h"
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
@objc
class IRCTypingTrackerTests: XCTestCase {
    @objc var client: UnsafeMutablePointer<GLTTestClient>
    @objc var tracker: UnsafeMutablePointer<IRCTypingTracker>

    @objc
    override func setUp() {
        super.setUp()
        self.client = GLTTestClient.testClient()
        self.tracker = IRCTypingTracker(client: self.client)
    }
    @objc
    override func tearDown() {
        self.tracker.removeAll()
        super.tearDown()
    }
    @objc
    func channelNamed(_ name: String) -> UnsafeMutablePointer<IRCChannel> {
        var channel: UnsafeMutablePointer<IRCChannel>! = IRCChannel(configDictionary: ["channelName": name])

        channel.associatedClient = self.client

        return channel
    }
    @objc
    func testStateParsing() {
        XCTAssertEqual(IRCTypingTracker.stateForTagValue("active"), IRCTypingStateActive)
        XCTAssertEqual(IRCTypingTracker.stateForTagValue("paused"), IRCTypingStatePaused)
        XCTAssertEqual(IRCTypingTracker.stateForTagValue("ACTIVE"), IRCTypingStateDone)
        XCTAssertEqual(IRCTypingTracker.stateForTagValue("done"), IRCTypingStateDone)
        XCTAssertEqual(IRCTypingTracker.stateForTagValue(nil), IRCTypingStateDone)
    }
    @objc
    func testOrderingCaseFoldingAndNotificationSuppression() {
        let channel = self.channelNamed("#chat")
        let start: Date! = Date.dateWithTimeIntervalSince1970(1000.0)
        var notificationCount: UInt = 0
        var notifiedChannel: UnsafeMutablePointer<IRCChannel>! = nil
        let token: AnyObject! = RZNotificationCenter().addObserverForName(IRCTypingTrackerDidChangeNotification, object: self.client, queue: nil) { (notification: Notification!) -> Void in
            notificationCount += 1
            notifiedChannel = notification.userInfo[IRCTypingTrackerChannelKey]
        }

        self.tracker.noteTypingState(IRCTypingStateActive, fromNickname: "Alice", inChannel: channel, atDate: start)
        self.tracker.noteTypingState(IRCTypingStateActive, fromNickname: "bob", inChannel: channel, atDate: start.addingTimeInterval(1.0))
        self.tracker.noteTypingState(IRCTypingStatePaused, fromNickname: "ALICE", inChannel: channel, atDate: start.addingTimeInterval(2.0))
        self.tracker.noteTypingState(IRCTypingStatePaused, fromNickname: "alice", inChannel: channel, atDate: start.addingTimeInterval(3.0))

        XCTAssertEqualObjects(self.tracker.typingNicknamesInChannel(channel, atDate: start.addingTimeInterval(4.0)), ["Alice", "bob"])

        XCTAssertEqual(notificationCount, 3)
        XCTAssertEqual(notifiedChannel, channel)

        RZNotificationCenter().removeObserver(token)
    }
    @objc
    func testEmptyNicknameIsIgnored() {
        let channel = self.channelNamed("#chat")
        var notificationCount: UInt = 0
        let token: AnyObject! = RZNotificationCenter().addObserverForName(IRCTypingTrackerDidChangeNotification, object: self.client, queue: nil) { (notification: Notification!) -> Void in
            notificationCount += 1
        }

        self.tracker.noteTypingState(IRCTypingStateActive, fromNickname: "", inChannel: channel)

        XCTAssertEqualObjects(self.tracker.typingNicknamesInChannel(channel), [])

        XCTAssertEqual(notificationCount, 0)

        RZNotificationCenter().removeObserver(token)
    }
    @objc
    func testRemoveNicknameAcrossChannels() {
        let firstChannel = self.channelNamed("#one")
        let secondChannel = self.channelNamed("#two")
        let start = Date()

        self.tracker.noteTypingState(IRCTypingStateActive, fromNickname: "Mara", inChannel: firstChannel, atDate: start)
        self.tracker.noteTypingState(IRCTypingStatePaused, fromNickname: "mara", inChannel: secondChannel, atDate: start)
        self.tracker.removeNickname("MARA")

        XCTAssertEqualObjects(self.tracker.typingNicknamesInChannel(firstChannel, atDate: start), [])
        XCTAssertEqualObjects(self.tracker.typingNicknamesInChannel(secondChannel, atDate: start), [])
    }
    @objc
    func testTimeoutBoundaryAndExplicitExpiry() {
        let channel = self.channelNamed("#chat")
        let start: Date! = Date.dateWithTimeIntervalSince1970(1000.0)

        self.tracker.noteTypingState(IRCTypingStateActive, fromNickname: "active", inChannel: channel, atDate: start)
        self.tracker.noteTypingState(IRCTypingStatePaused, fromNickname: "paused", inChannel: channel, atDate: start)

        XCTAssertEqualObjects(self.tracker.typingNicknamesInChannel(channel, atDate: start.addingTimeInterval(6.0)), ["active", "paused"])

        self.tracker.expireEntriesAtDate(start.addingTimeInterval(6.001))

        XCTAssertEqualObjects(self.tracker.typingNicknamesInChannel(channel, atDate: start.addingTimeInterval(30.0)), ["paused"])

        self.tracker.expireEntriesAtDate(start.addingTimeInterval(30.001))

        XCTAssertEqualObjects(self.tracker.typingNicknamesInChannel(channel, atDate: start), [])
    }
}