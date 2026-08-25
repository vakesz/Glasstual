import XCTest

// Preprocessor directives found in file:
// #import <XCTest/XCTest.h>
// #import "GLTTestClient.h"
// #import "IRCChannelPrivate.h"
// #import "IRCISupportInfoPrivate.h"
// #import "IRCMessage.h"
// #import "IRCTreeItemPrivate.h"
// #import "TVCLogControllerHistoricLogFilePrivate.h"
// #import "TPCPreferencesUserDefaults.h"
// #import "TVCLogLinePrivate.h"
// #pragma mark -
// #pragma mark Capability and ISUPPORT
// #pragma mark -
// #pragma mark Requests
// #pragma mark -
// #pragma mark Replay
// #pragma mark -
// #pragma mark Read markers
// #pragma mark -
// #pragma mark Netsplit
let _joinLeavePreferenceKey: String = "DisplayEventInLogView -> Join, Part, Quit"

/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
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
class IRCClientHistoryTests: XCTestCase {
    @objc
    func message(_ line: String, onClient client: UnsafeMutablePointer<IRCClient>) -> UnsafeMutablePointer<IRCMessage> {
        let message: UnsafeMutablePointer<IRCMessage>! = IRCMessage(line: line, onClient: client)

        XCTAssertNotNil(message, "Failed to parse: %@", line)

        return message
    }
    @objc
    func feedLines(_ lines: [String], toClient client: UnsafeMutablePointer<GLTTestClient>) {
        for line in lines {
            let message = self.message(line, onClient: client)

            if client.filterBatchCommandIncomingData(message) {
                continue
            }

            if message.command == "BATCH" {
                client.receiveBatch(message)
            } else {
                client.processIncomingMessage(message)
            }
        }
    }
    @objc
    func channelNamed(_ name: String, onClient client: UnsafeMutablePointer<GLTTestClient>) -> UnsafeMutablePointer<IRCChannel> {
        var channel: UnsafeMutablePointer<IRCChannel>! = IRCChannel(configDictionary: ["channelName": name])

        channel.associatedClient = client
        client.addChannel(channel)

        return channel
    }
    @objc
    func historyClient() -> UnsafeMutablePointer<GLTTestClient> {
        var client: UnsafeMutablePointer<GLTTestClient>! = GLTTestClient.testClient()

        client.enableCapability(ClientIRCv3SupportedCapabilityBatch)
        client.enableCapability(ClientIRCv3SupportedCapabilityServerTime)
        client.enableCapability(ClientIRCv3SupportedCapabilityMessageTags)
        client.enableCapability(ClientIRCv3SupportedCapabilityChatHistory)
        client.isLoggedIn = true

        return client
    }
    @objc
    func logLineWithMessageIdentifier(_ messageIdentifier: String?, nickname: String, text: String, date: Date) -> UnsafeMutablePointer<TVCLogLine> {
        var logLine: UnsafeMutablePointer<TVCLogLineMutable>! = TVCLogLineMutable()

        logLine.command = "privmsg"
        logLine.lineType = TVCLogLineTypePrivateMessage
        logLine.messageIdentifier = messageIdentifier
        logLine.nickname = nickname
        logLine.messageBody = text
        logLine.receivedAt = date

        return logLine.copy()
    }
    @objc
    func testChatHistoryIsRequestedOnlyWithItsDependencies() {
        let client: UnsafeMutablePointer<GLTTestClient>! = GLTTestClient.testClient()

        client.receiveCapabilityOrAuthenticationRequest(self.message(":irc.example.net CAP * LS :draft/chathistory draft/read-marker", onClient: client))
        /* No batch, server-time or message-tags: chathistory stays out. */
        XCTAssertEqualObjects(client.sentCapabilityCommands, ["REQ draft/read-marker"])

        let complete: UnsafeMutablePointer<GLTTestClient>! = GLTTestClient.testClient()

        complete.receiveCapabilityOrAuthenticationRequest(self.message(":irc.example.net CAP * LS :batch server-time message-tags chathistory read-marker", onClient: complete))

        XCTAssertEqualObjects(complete.sentCapabilityCommands, ["REQ message-tags"])
        XCTAssertEqualObjects(complete.pendingCapabilityRequests, ["batch", "chathistory", "read-marker", "server-time"])

        complete.receiveCapabilityOrAuthenticationRequest(self.message(":irc.example.net CAP me ACK :chathistory", onClient: complete))

        XCTAssertTrue(complete.isCapabilityEnabled(ClientIRCv3SupportedCapabilityChatHistory))
    }
    @objc
    func testChatHistoryLimitComesFromISupport() {
        let client = self.historyClient()

        XCTAssertEqual(client.chatHistoryRequestLimit, 100)

        client.supportInfo.processConfigurationData("CHATHISTORY=50")

        XCTAssertEqual(client.supportInfo.chatHistoryMaximumLines, 50)
        XCTAssertEqual(client.chatHistoryRequestLimit, 50)

        client.supportInfo.processConfigurationData("draft/CHATHISTORY=20")

        XCTAssertEqual(client.chatHistoryRequestLimit, 20)

        /* The client never asks for more than its own batch size. */
        client.supportInfo.processConfigurationData("CHATHISTORY=1000")

        XCTAssertEqual(client.chatHistoryRequestLimit, 100)
    }
    @objc
    func testLatestRequestUsesStarWithoutLocalScrollbackAndTimestampWithIt() {
        let client = self.historyClient()
        let channel = self.channelNamed("#chat", onClient: client)

        client.requestChatHistoryForChannel(channel)
        XCTAssertEqualObjects(client.sentLines, ["CHATHISTORY LATEST #chat * 100"])

        /* A line in the local store: only the gap after it is wanted. */
        let date: Date! = Date.dateWithTimeIntervalSince1970(1.7e+09)

        TVCLogControllerHistoricLogSharedInstance().indexLogLine(self.logLineWithMessageIdentifier("m1", nickname: "a", text: "hi", date: date), forItem: channel)
        client.requestChatHistoryForChannel(channel)
        XCTAssertEqualObjects(client.sentLines.lastObject, "CHATHISTORY LATEST #chat timestamp=2023-11-14T22:13:20.500Z 100")
    }
    @objc
    func testLatestRequestNeedsTheCapability() {
        var client: UnsafeMutablePointer<GLTTestClient>! = GLTTestClient.testClient()

        client.isLoggedIn = true

        let channel = self.channelNamed("#chat", onClient: client)

        client.requestChatHistoryForChannel(channel)
        XCTAssertEqual(client.sentLines.count, 0)
    }
    @objc
    func testBeforeRequestIsSentOncePerTargetUntilAnswered() {
        let client = self.historyClient()
        let channel = self.channelNamed("#chat", onClient: client)
        let oldest: Date! = Date.dateWithTimeIntervalSince1970(1700000000)

        client.requestChatHistoryBeforeDate(oldest, inChannel: channel)
        client.requestChatHistoryBeforeDate(oldest, inChannel: channel)

        XCTAssertEqualObjects(client.sentLines, ["CHATHISTORY BEFORE #chat timestamp=2023-11-14T22:13:20.000Z 100"])

        /* The reply releases the target for the next request. */
        self.feedLines([":irc.example.net BATCH +h1 chathistory #chat", "@batch=h1;msgid=x1;time=2023-11-14T22:00:00.000Z :a!u@h PRIVMSG #chat :older", ":irc.example.net BATCH -h1"], toClient: client)

        XCTAssertEqual(client.processedMessages.count, 1)

        client.requestChatHistoryBeforeDate(Date.dateWithTimeIntervalSince1970(1699999200), inChannel: channel)

        XCTAssertEqual(client.sentLines.count, 2)
    }
    @objc
    func testFailedTargetIsReportedOnceAndNotRetried() {
        let client = self.historyClient()
        let channel = self.channelNamed("#chat", onClient: client)

        client.receiveStandardReply(self.message(":irc.example.net FAIL CHATHISTORY INVALID_TARGET LATEST #chat :No history for #chat", onClient: client))
        client.receiveStandardReply(self.message(":irc.example.net FAIL CHATHISTORY INVALID_TARGET BEFORE #chat :No history for #chat", onClient: client))

        XCTAssertEqual(client.printedLines.count, 1)

        XCTAssertEqualObjects(client.printedLines[0]["messageBody"], "FAIL CHATHISTORY/INVALID_TARGET: No history for #chat")

        client.requestChatHistoryForChannel(channel)
        client.requestChatHistoryBeforeDate(Date(), inChannel: channel)

        XCTAssertEqual(client.sentLines.count, 0)
    }
    @objc
    func testChatHistoryWinsOverZNCPlayback() {
        let client = self.historyClient()

        client.enableCapability(ClientIRCv3SupportedCapabilityPlayback)
        client.requestPlayback()

        XCTAssertEqual(client.sentLines.count, 0)

        /* Without chathistory the playback module is asked as before. */
        client.disableCapability(ClientIRCv3SupportedCapabilityChatHistory)
        client.requestPlayback()

        XCTAssertEqualObjects(client.sentLines, ["PRIVMSG *playback :play * 0"])
    }
    @objc
    func testChatHistoryCommandIsPassedThrough() {
        let client = self.historyClient()

        client.sendCommand("/chathistory AROUND #chat timestamp=2023-11-14T22:13:20.000Z 10", completeTarget: false, target: nil)
        XCTAssertEqualObjects(client.sentLines, ["CHATHISTORY AROUND #chat timestamp=2023-11-14T22:13:20.000Z 10"])
    }
    @objc
    func testReplayedLinesAreHistoricAndDeduplicatedByMessageIdentifier() {
        let client = self.historyClient()
        let channel = self.channelNamed("#chat", onClient: client)
        let date: Date! = Date.dateWithTimeIntervalSince1970(1700000000)

        TVCLogControllerHistoricLogSharedInstance().indexLogLine(self.logLineWithMessageIdentifier("seen", nickname: "a", text: "one", date: date), forItem: channel)
        TVCLogControllerHistoricLogSharedInstance().indexLogLine(self.logLineWithMessageIdentifier(nil, nickname: "b", text: "two", date: date), forItem: channel)
        self.feedLines([":irc.example.net BATCH +h1 chathistory #chat", "@batch=h1;msgid=seen;time=2023-11-14T22:13:20.000Z :a!u@h PRIVMSG #chat :one", "@batch=h1;time=2023-11-14T22:13:20.000Z :b!u@h PRIVMSG #chat :two", "@batch=h1;time=2023-11-14T22:13:20.000Z :b!u@h PRIVMSG #chat :two again", "@batch=h1;msgid=new;time=2023-11-14T22:13:21.000Z :c!u@h PRIVMSG #chat :three", ":irc.example.net BATCH -h1"], toClient: client)

        let bodies: [String]! = client.processedMessages.valueForKeyPath("sequence")

        XCTAssertEqualObjects(bodies, ["two again", "three"])

        for message in client.processedMessages {
            XCTAssertTrue(message.isHistoric)
        }
    }
    @objc
    func testDuplicateCheckFallsBackToTimestampSenderAndText() {
        let client = self.historyClient()
        let channel = self.channelNamed("#chat", onClient: client)
        let date: Date! = Date.dateWithTimeIntervalSince1970(1700000000)

        TVCLogControllerHistoricLogSharedInstance().indexLogLine(self.logLineWithMessageIdentifier(nil, nickname: "b", text: "two", date: date), forItem: channel)

        XCTAssertTrue(client.chatHistoryMessageIsDuplicate(self.message("@time=2023-11-14T22:13:20.000Z :b!u@h PRIVMSG #chat :two", onClient: client)))

        XCTAssertFalse(client.chatHistoryMessageIsDuplicate(self.message("@time=2023-11-14T22:13:20.000Z :c!u@h PRIVMSG #chat :two", onClient: client)))
        XCTAssertFalse(client.chatHistoryMessageIsDuplicate(self.message("@time=2023-11-14T22:13:21.000Z :b!u@h PRIVMSG #chat :two", onClient: client)))
        /* Without a server time there is nothing to match on. */
        XCTAssertFalse(client.chatHistoryMessageIsDuplicate(self.message(":b!u@h PRIVMSG #chat :two", onClient: client)))
    }
    @objc
    func testReceivedReadMarkerAtNewestLineClearsUnreadCounts() {
        let client = self.historyClient()

        client.enableCapability(ClientIRCv3SupportedCapabilityReadMarker)

        var channel = self.channelNamed("#chat", onClient: client)
        let date: Date! = Date.dateWithTimeIntervalSince1970(1700000000)

        TVCLogControllerHistoricLogSharedInstance().indexLogLine(self.logLineWithMessageIdentifier("r1", nickname: "a", text: "hi", date: date), forItem: channel)

        channel.treeUnreadCount = 3
        channel.nicknameHighlightCount = 1

        /* A marker before the newest line leaves the counts alone. */
        client.receiveReadMarker(self.message(":irc.example.net MARKREAD #chat timestamp=2023-11-14T22:13:19.000Z", onClient: client))

        XCTAssertEqual(channel.treeUnreadCount, 3)
        XCTAssertEqual(channel.nicknameHighlightCount, 1)

        client.receiveReadMarker(self.message(":irc.example.net MARKREAD #chat timestamp=2023-11-14T22:13:20.000Z", onClient: client))

        XCTAssertEqual(channel.treeUnreadCount, 0)
        XCTAssertEqual(channel.nicknameHighlightCount, 0)

        XCTAssertFalse(channel.isUnread)

        /* "*" means no marker and changes nothing. */
        channel.treeUnreadCount = 1

        client.receiveReadMarker(self.message(":irc.example.net MARKREAD #chat *", onClient: client))

        XCTAssertEqual(channel.treeUnreadCount, 1)
    }
    @objc
    func testReadMarkerIsSentOncePerNewestLine() {
        let client = self.historyClient()

        client.enableCapability(ClientIRCv3SupportedCapabilityReadMarker)

        let channel = self.channelNamed("#chat", onClient: client)

        /* Nothing to mark in an empty channel. */
        client.markChannelAsRead(channel)
        client.onReadMarkerTimer()
        XCTAssertEqual(client.sentLines.count, 0)

        let date: Date! = Date.dateWithTimeIntervalSince1970(1700000000)

        TVCLogControllerHistoricLogSharedInstance().indexLogLine(self.logLineWithMessageIdentifier("r1", nickname: "a", text: "hi", date: date), forItem: channel)

        client.markChannelAsRead(channel)
        client.markChannelAsRead(channel)
        client.onReadMarkerTimer()

        XCTAssertEqualObjects(client.sentLines, ["MARKREAD #chat timestamp=2023-11-14T22:13:20.000Z"])

        /* The same newest line is not reported twice. */
        client.markChannelAsRead(channel)
        client.onReadMarkerTimer()

        XCTAssertEqual(client.sentLines.count, 1)

        /* A newer line is. */
        TVCLogControllerHistoricLogSharedInstance().indexLogLine(self.logLineWithMessageIdentifier("r2", nickname: "a", text: "again", date: date.addingTimeInterval(5)), forItem: channel)

        client.markChannelAsRead(channel)
        client.onReadMarkerTimer()

        XCTAssertEqualObjects(client.sentLines.lastObject, "MARKREAD #chat timestamp=2023-11-14T22:13:25.000Z")

        XCTAssertEqual(client.sentLines.count, 2)
    }
    @objc
    func testReadMarkerIsQueriedOnActivation() {
        let client = self.historyClient()

        client.enableCapability(ClientIRCv3SupportedCapabilityReadMarker)

        let channel = self.channelNamed("#chat", onClient: client)

        client.noteChannelActivated(channel)
        XCTAssertEqualObjects(client.sentLines, ["CHATHISTORY LATEST #chat * 100", "MARKREAD #chat"])
    }
    @objc
    func testReadMarkerIsNotSentWithoutTheCapability() {
        let client = self.historyClient()
        let channel = self.channelNamed("#chat", onClient: client)

        TVCLogControllerHistoricLogSharedInstance().indexLogLine(self.logLineWithMessageIdentifier("r1", nickname: "a", text: "hi", date: Date()), forItem: channel)
        client.sendReadMarkerForChannel(channel)
        XCTAssertEqual(client.sentLines.count, 0)
    }
    @objc
    func netsplitClientShowingJoinsAndQuits(_ showJoinLeave: Bool) -> UnsafeMutablePointer<GLTTestClient> {
        /* The summary follows the join/quit print preference. */
        let previous: AnyObject! = RZUserDefaults().objectForKey(_joinLeavePreferenceKey)

        self.addTeardownBlock { () -> Void in
            if previous {
                RZUserDefaults().setObject(previous, forKey: _joinLeavePreferenceKey)
            } else {
                RZUserDefaults().removeObjectForKey(_joinLeavePreferenceKey)
            }
        }
        RZUserDefaults().setBool(showJoinLeave, forKey: _joinLeavePreferenceKey)

        var client: UnsafeMutablePointer<GLTTestClient>! = GLTTestClient.testClient()

        client.enableCapability(ClientIRCv3SupportedCapabilityBatch)
        client.forwardsProcessedMessages = true

        return client
    }
    @objc
    func testNetsplitSummaryIsHiddenWithJoinsAndQuits() {
        let client = self.netsplitClientShowingJoinsAndQuits(false)
        let channel = self.channelNamed("#chat", onClient: client)

        channel.activate()
        self.feedLines([":alice!u@h JOIN #chat"], toClient: client)

        let linesBefore: UInt = client.printedLines.count

        self.feedLines([":irc.example.net BATCH +ns netsplit irc.hub irc.leaf", "@batch=ns :alice!u@h QUIT :irc.hub irc.leaf", ":irc.example.net BATCH -ns"], toClient: client)
        XCTAssertFalse(channel.memberExists("alice"))
        XCTAssertEqual(client.printedLines.count, linesBefore)
    }
    @objc
    func testNetsplitBatchProducesOneSummaryLineAndUpdatesMembers() {
        let client = self.netsplitClientShowingJoinsAndQuits(true)
        let channel = self.channelNamed("#chat", onClient: client)

        channel.activate()

        self.feedLines([":alice!u@h JOIN #chat", ":bob!u@h JOIN #chat", ":carol!u@h JOIN #chat"], toClient: client)

        XCTAssertTrue(channel.memberExists("alice"))
        XCTAssertTrue(channel.memberExists("bob"))
        XCTAssertTrue(channel.memberExists("carol"))

        var linesBefore: UInt = client.printedLines.count

        self.feedLines([":irc.example.net BATCH +ns netsplit irc.hub irc.leaf", "@batch=ns :alice!u@h QUIT :irc.hub irc.leaf", "@batch=ns :bob!u@h QUIT :irc.hub irc.leaf", ":irc.example.net BATCH -ns"], toClient: client)

        XCTAssertFalse(channel.memberExists("alice"))
        XCTAssertFalse(channel.memberExists("bob"))

        XCTAssertTrue(channel.memberExists("carol"))

        var newLines: [NSDictionary]! = client.printedLines.subarrayWithRange(NSMakeRange(linesBefore, client.printedLines.count - linesBefore))

        XCTAssertEqual(newLines.count, 1)

        XCTAssertEqualObjects(newLines.firstObject["messageBody"], "Netsplit between \\002irc.hub\\002 and \\002irc.leaf\\002: 2 users left (alice, bob)")

        XCTAssertEqual(newLines.firstObject["lineType"].unsignedIntegerValue(), TVCLogLineTypeQuit)
        XCTAssertEqual(newLines.firstObject["channel"], channel)

        /* The netjoin brings them back with one line as well. */
        linesBefore = client.printedLines.count

        self.feedLines([":irc.example.net BATCH +nj netjoin irc.hub irc.leaf", "@batch=nj :alice!u@h JOIN #chat", "@batch=nj :bob!u@h JOIN #chat", ":irc.example.net BATCH -nj"], toClient: client)

        XCTAssertTrue(channel.memberExists("alice"))
        XCTAssertTrue(channel.memberExists("bob"))

        newLines = client.printedLines.subarrayWithRange(NSMakeRange(linesBefore, client.printedLines.count - linesBefore))

        XCTAssertEqual(newLines.count, 1)

        XCTAssertEqualObjects(newLines.firstObject["messageBody"], "Netjoin between \\002irc.hub\\002 and \\002irc.leaf\\002: 2 users rejoined (alice, bob)")

        XCTAssertEqual(newLines.firstObject["lineType"].unsignedIntegerValue(), TVCLogLineTypeJoin)
    }
    @objc
    func testNetsplitSummaryListsAtMostTenNicknames() {
        let client = self.netsplitClientShowingJoinsAndQuits(true)
        let channel = self.channelNamed("#chat", onClient: client)

        channel.activate()

        let joins = NSMutableArray()
        let quits = NSMutableArray()

        quits.add(":irc.example.net BATCH +ns netsplit irc.hub irc.leaf")

        var i: UInt = 1

        while i <= 12 {
            defer {
                i += 1
            }

            joins.add(String(format: ":user%lu!u@h JOIN #chat", CUnsignedLong(i)))
            quits.add(String(format: "@batch=ns :user%lu!u@h QUIT :split", CUnsignedLong(i)))
        }

        quits.add(":irc.example.net BATCH -ns")
        self.feedLines(joins, toClient: client)

        let linesBefore: UInt = client.printedLines.count

        self.feedLines(quits, toClient: client)

        XCTAssertEqual(client.printedLines.count, linesBefore + 1)

        XCTAssertEqualObjects(client.printedLines.lastObject["messageBody"], "Netsplit between \\002irc.hub\\002 and \\002irc.leaf\\002: 12 users left (user1, user2, user3, user4, user5, user6, user7, user8, user9, user10, … and 2 more)")

        XCTAssertFalse(channel.memberExists("user1"))
        XCTAssertFalse(channel.memberExists("user12"))
    }
}