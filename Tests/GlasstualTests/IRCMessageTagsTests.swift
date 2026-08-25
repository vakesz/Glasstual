import XCTest

// Preprocessor directives found in file:
// #import <XCTest/XCTest.h>
// #import "GLTTestClient.h"
// #import "IRCChannelPrivate.h"
// #import "IRCMessage.h"
// #import "IRCTreeItemPrivate.h"
// #import "IRCTypingTrackerPrivate.h"
// #import "TPCPreferencesLocal.h"
// #import "TPCPreferencesUserDefaults.h"
// #pragma mark -
// #pragma mark Typing: sending
// #pragma mark -
// #pragma mark Typing: receiving
// #pragma mark -
// #pragma mark Replies
// #pragma mark -
// #pragma mark Reactions
/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
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
/* Typing notifications, replies and reactions (IRCv3 message-tags:
 "+typing", "+draft/reply", "+draft/react"). */
@objc
class IRCMessageTagsTests: XCTestCase {
    @objc
    override func setUp() {
        super.setUp()
        RZUserDefaults().setBool(true, forKey: "SendTypingNotifications")
    }
    @objc
    func clientWithMessageTags() -> UnsafeMutablePointer<GLTTestClient> {
        let client: UnsafeMutablePointer<GLTTestClient>! = GLTTestClient.testClientWithConfigDictionary(["nickname": "me", "username": "me"])

        client.enableCapability(ClientIRCv3SupportedCapabilityMessageTags)
        client.markAsLoggedIn()

        return client
    }
    @objc
    func addChannelNamed(_ name: String, toClient client: UnsafeMutablePointer<GLTTestClient>) -> UnsafeMutablePointer<IRCChannel> {
        var channel: UnsafeMutablePointer<IRCChannel>! = IRCChannel(configDictionary: ["channelName": name])

        channel.associatedClient = client
        client.addChannel(channel)
        channel.activate()

        return channel
    }
    @objc
    func message(_ line: String, onClient client: UnsafeMutablePointer<IRCClient>) -> UnsafeMutablePointer<IRCMessage> {
        let message: UnsafeMutablePointer<IRCMessage>! = IRCMessage(line: line, onClient: client)

        XCTAssertNotNil(message, "Failed to parse: %@", line)

        return message
    }
    @objc
    func testTypingActiveIsThrottledToEveryThreeSeconds() {
        let client = self.clientWithMessageTags()
        let channel = self.addChannelNamed("#chat", toClient: client)
        let start = Date()

        client.noteLocalUserTyping("h", inChannel: channel, atDate: start)
        client.noteLocalUserTyping("he", inChannel: channel, atDate: start.addingTimeInterval(1.0))
        client.noteLocalUserTyping("hel", inChannel: channel, atDate: start.addingTimeInterval(2.9))

        XCTAssertEqualObjects(client.sentLines, ["@+typing=active TAGMSG #chat"])

        client.noteLocalUserTyping("hell", inChannel: channel, atDate: start.addingTimeInterval(3.0))

        XCTAssertEqual(client.sentLines.count, 2)

        XCTAssertEqualObjects(client.sentLines.lastObject, "@+typing=active TAGMSG #chat")
    }
    @objc
    func testTypingPausedAfterIdleThenActiveAgain() {
        let client = self.clientWithMessageTags()
        let channel = self.addChannelNamed("#chat", toClient: client)
        let start = Date()

        client.noteLocalUserTyping("h", inChannel: channel, atDate: start)
        client.typingPauseTimerFired(channel)

        XCTAssertEqualObjects(client.sentLines, ["@+typing=active TAGMSG #chat", "@+typing=paused TAGMSG #chat"])

        /* Typing again after a pause sends active at once. */
        client.noteLocalUserTyping("he", inChannel: channel, atDate: start.addingTimeInterval(0.5))

        XCTAssertEqualObjects(client.sentLines.lastObject, "@+typing=active TAGMSG #chat")

        XCTAssertEqual(client.sentLines.count, 3)
    }
    @objc
    func testTypingDoneWhenTextClearedOrSent() {
        let client = self.clientWithMessageTags()
        let channel = self.addChannelNamed("#chat", toClient: client)

        client.noteLocalUserTyping("h", inChannel: channel, atDate: Date())
        client.noteLocalUserTyping("", inChannel: channel, atDate: Date())

        XCTAssertEqualObjects(client.sentLines, ["@+typing=active TAGMSG #chat", "@+typing=done TAGMSG #chat"])

        /* Clearing an already clear field sends nothing. */
        client.noteLocalUserTyping("", inChannel: channel, atDate: Date())

        XCTAssertEqual(client.sentLines.count, 2)

        client.noteLocalUserTyping("x", inChannel: channel, atDate: Date())
        client.localUserSentMessageInChannel(channel)

        XCTAssertEqualObjects(client.sentLines.lastObject, "@+typing=done TAGMSG #chat")

        XCTAssertEqual(client.sentLines.count, 4)
    }
    @objc
    func testTypingIsNotSentForCommands() {
        let client = self.clientWithMessageTags()
        let channel = self.addChannelNamed("#chat", toClient: client)

        client.noteLocalUserTyping("/", inChannel: channel, atDate: Date())
        client.noteLocalUserTyping("/me", inChannel: channel, atDate: Date())

        XCTAssertEqual(client.sentLines.count, 0)

        /* Text that turns into a command ends the notification. */
        client.noteLocalUserTyping("h", inChannel: channel, atDate: Date())
        client.noteLocalUserTyping("/h", inChannel: channel, atDate: Date())

        XCTAssertEqualObjects(client.sentLines, ["@+typing=active TAGMSG #chat", "@+typing=done TAGMSG #chat"])
    }
    @objc
    func testTypingIsNotSentWithoutMessageTagsOrToConsole() {
        let client: UnsafeMutablePointer<GLTTestClient>! = GLTTestClient.testClient()

        client.markAsLoggedIn()

        let channel = self.addChannelNamed("#chat", toClient: client)

        client.noteLocalUserTyping("h", inChannel: channel, atDate: Date())
        client.noteLocalUserTyping("h", inChannel: nil, atDate: Date())
        XCTAssertEqual(client.sentLines.count, 0)

        let tagged = self.clientWithMessageTags()

        tagged.noteLocalUserTyping("h", inChannel: nil, atDate: Date())
        XCTAssertEqual(tagged.sentLines.count, 0)
    }
    @objc
    func testTypingRespectsPreference() {
        RZUserDefaults().setBool(false, forKey: "SendTypingNotifications")

        let client = self.clientWithMessageTags()
        let channel = self.addChannelNamed("#chat", toClient: client)

        client.noteLocalUserTyping("h", inChannel: channel, atDate: Date())
        XCTAssertEqual(client.sentLines.count, 0)
        RZUserDefaults().setBool(true, forKey: "SendTypingNotifications")
    }
    @objc
    func testTypingStateExpires() {
        let client = self.clientWithMessageTags()
        let channel = self.addChannelNamed("#chat", toClient: client)
        let tracker: UnsafeMutablePointer<IRCTypingTracker>! = client.typingTracker
        let start = Date()

        tracker.noteTypingState(IRCTypingStateActive, fromNickname: "mara", inChannel: channel, atDate: start)
        tracker.noteTypingState(IRCTypingStatePaused, fromNickname: "jonas", inChannel: channel, atDate: start)

        XCTAssertEqualObjects(tracker.typingNicknamesInChannel(channel, atDate: start.addingTimeInterval(5.0)), ["mara", "jonas"])
        /* Active expires after six seconds, paused after thirty. */
        XCTAssertEqualObjects(tracker.typingNicknamesInChannel(channel, atDate: start.addingTimeInterval(7.0)), ["jonas"])
        XCTAssertEqualObjects(tracker.typingNicknamesInChannel(channel, atDate: start.addingTimeInterval(31.0)), [])

        tracker.expireEntriesAtDate(start.addingTimeInterval(31.0))

        XCTAssertEqualObjects(tracker.typingNicknamesInChannel(channel, atDate: start), [])
    }
    @objc
    func testTypingDoneRemovesEntryAndTagMessageFeedsTracker() {
        let client = self.clientWithMessageTags()
        let channel = self.addChannelNamed("#chat", toClient: client)

        client.receiveTagMessage(self.message("@+typing=active :mara!u@h TAGMSG #chat", onClient: client))

        XCTAssertEqualObjects(client.typingTracker.typingNicknamesInChannel(channel), ["mara"])

        client.receiveTagMessage(self.message("@+typing=done :mara!u@h TAGMSG #chat", onClient: client))

        XCTAssertEqualObjects(client.typingTracker.typingNicknamesInChannel(channel), [])

        /* The local user's own echo is not tracked. */
        client.receiveTagMessage(self.message("@+typing=active :me!u@h TAGMSG #chat", onClient: client))

        XCTAssertEqualObjects(client.typingTracker.typingNicknamesInChannel(channel), [])
    }
    @objc
    func testReplyTagIsSentOnFirstLineOnly() {
        var client = self.clientWithMessageTags()
        let channel = self.addChannelNamed("#chat", toClient: client)

        client.nextMessageReplyIdentifier = "abc123"
        client.sendText(NSAttributedString.attributedStringWithString("first\\nsecond"), asCommand: IRCRemoteCommandPrivmsg, toChannel: channel)

        let privmsgs: [String]! = client.sentLines.filteredArrayUsingPredicate(NSPredicate.predicateWithBlock { (line: String!, bindings: NSDictionary!) -> Bool in
            return line.containsString("PRIVMSG")
        })

        XCTAssertEqualObjects(privmsgs, ["@+draft/reply=abc123 PRIVMSG #chat :first", "PRIVMSG #chat :second"])
        XCTAssertNil(client.nextMessageReplyIdentifier)

        /* The local print carries the reference. */
        let firstPrinted: NSDictionary! = client.printedLines.firstObject

        XCTAssertEqualObjects(firstPrinted["messageBody"], "first")
        client.sendText(NSAttributedString.attributedStringWithString("third"), asCommand: IRCRemoteCommandPrivmsg, toChannel: channel)
        XCTAssertEqualObjects(client.sentLines.lastObject, "PRIVMSG #chat :third")
    }
    @objc
    func testReplyTagIsDroppedWithoutMessageTags() {
        var client: UnsafeMutablePointer<GLTTestClient>! = GLTTestClient.testClient()

        client.markAsLoggedIn()

        let channel = self.addChannelNamed("#chat", toClient: client)

        client.nextMessageReplyIdentifier = "abc123"
        client.sendText(NSAttributedString.attributedStringWithString("hello"), asCommand: IRCRemoteCommandPrivmsg, toChannel: channel)
        XCTAssertEqualObjects(client.sentLines.lastObject, "PRIVMSG #chat :hello")
    }
    @objc
    func testReactionSendsTagMessage() {
        let client = self.clientWithMessageTags()
        let channel = self.addChannelNamed("#chat", toClient: client)

        XCTAssertTrue(client.sendReaction("👍", toMessageIdentifier: "abc123", inChannel: channel))
        XCTAssertEqualObjects(client.sentLines, ["@+draft/react=👍;+draft/reply=abc123 TAGMSG #chat"])
    }
    @objc
    func testReactionRequiresMessageTags() {
        let client: UnsafeMutablePointer<GLTTestClient>! = GLTTestClient.testClient()

        client.markAsLoggedIn()

        let channel = self.addChannelNamed("#chat", toClient: client)

        XCTAssertFalse(client.sendReaction("👍", toMessageIdentifier: "abc123", inChannel: channel))
        XCTAssertEqual(client.sentLines.count, 0)
    }
    @objc
    func testTagMessageEventShape() {
        let client = self.clientWithMessageTags()
        let date: Date! = Date.dateWithTimeIntervalSince1970(1700000000)
        let event: NSDictionary! = client.tagMessageEventWithClientTags(["draft/react": "👍", "draft/reply": "abc123"], sender: "mara", target: "#chat", timestamp: date, messageIdentifier: "tag1", account: "mara")
        let expected = ["sender": "mara", "target": "#chat", "tags": ["draft/react": "👍", "draft/reply": "abc123"], "timestamp": 1.7e+09, "fromLocalUser": false, "localUserNickname": "me", "msgid": "tag1", "account": "mara"]

        XCTAssertEqualObjects(event, expected)

        let own: NSDictionary! = client.tagMessageEventWithClientTags(["draft/react": "👍", "draft/reply": "abc123"], sender: "me", target: "#chat", timestamp: date, messageIdentifier: nil, account: nil)

        XCTAssertEqualObjects(own["fromLocalUser"], true)
        XCTAssertNil(own["msgid"])
        XCTAssertNil(own["account"])
    }
}