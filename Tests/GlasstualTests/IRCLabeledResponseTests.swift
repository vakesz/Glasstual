import XCTest

// Preprocessor directives found in file:
// #import <XCTest/XCTest.h>
// #import "GLTTestClient.h"
// #import "IRCChannelPrivate.h"
// #import "IRCMessage.h"
// #import "IRCTreeItemPrivate.h"
// #import "TVCLogLine.h"
/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
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
class IRCLabeledResponseTests: XCTestCase {
    @objc
    func message(_ line: String, onClient client: UnsafeMutablePointer<IRCClient>) -> UnsafeMutablePointer<IRCMessage> {
        let message: UnsafeMutablePointer<IRCMessage>! = IRCMessage(line: line, onClient: client)

        XCTAssertNotNil(message, "Failed to parse: %@", line)

        return message
    }
    @objc
    func clientWithLabeledResponse() -> UnsafeMutablePointer<GLTTestClient> {
        let client: UnsafeMutablePointer<GLTTestClient>! = GLTTestClient.testClient()

        client.enableCapability(ClientIRCv3SupportedCapabilityMessageTags)
        client.enableCapability(ClientIRCv3SupportedCapabilityEchoMessage)
        client.enableCapability(ClientIRCv3SupportedCapabilityLabeledResponse)

        return client
    }
    @objc
    func addChannelNamed(_ name: String, toClient client: UnsafeMutablePointer<GLTTestClient>) -> UnsafeMutablePointer<IRCChannel> {
        var channel: UnsafeMutablePointer<IRCChannel>! = IRCChannel(configDictionary: ["channelName": name])

        channel.associatedClient = client
        client.addChannel(channel)

        return channel
    }
    @objc
    func testTrackingRequiresBothCapabilities() {
        let client: UnsafeMutablePointer<GLTTestClient>! = GLTTestClient.testClient()

        client.enableCapability(ClientIRCv3SupportedCapabilityLabeledResponse)

        XCTAssertFalse(client.labeledResponseTrackingEnabled())

        XCTAssertNil(client.registerPendingDeliveryForChannel(nil))

        client.enableCapability(ClientIRCv3SupportedCapabilityEchoMessage)

        XCTAssertTrue(client.labeledResponseTrackingEnabled())
    }
    @objc
    func testRegisterCreatesPendingDeliveryWithLabel() {
        let client = self.clientWithLabeledResponse()
        let channel = self.addChannelNamed("#chat", toClient: client)
        let label: String! = client.registerPendingDeliveryForChannel(channel)

        XCTAssertEqualObjects(label, "g1") // First label of the session
        XCTAssertEqual(client.deliveryStateForLabel(label), TVCLogLineDeliveryStatePending)
    }
    @objc
    func testEchoWithLabelMarksDelivered() {
        let client = self.clientWithLabeledResponse()
        let channel = self.addChannelNamed("#chat", toClient: client)
        let label: String! = client.registerPendingDeliveryForChannel(channel)
        let echo = self.message("@label=g1;msgid=abc123 :me!u@h PRIVMSG #chat :hello", onClient: client)

        XCTAssertTrue(client.resolveLabeledResponseForMessage(echo))
        XCTAssertEqual(client.deliveryStateForLabel(label), TVCLogLineDeliveryStateDelivered)
    }
    @objc
    func testFailWithLabelMarksFailed() {
        let client = self.clientWithLabeledResponse()
        let channel = self.addChannelNamed("#chat", toClient: client)
        let label: String! = client.registerPendingDeliveryForChannel(channel)
        let fail = self.message("@label=g1 FAIL PRIVMSG ACCOUNT_REQUIRED_TO_MESSAGE :You must be registered", onClient: client)

        XCTAssertTrue(client.resolveLabeledResponseForMessage(fail))
        XCTAssertEqual(client.deliveryStateForLabel(label), TVCLogLineDeliveryStateFailed)
    }
    @objc
    func testAckWithLabelMarksDelivered() {
        let client = self.clientWithLabeledResponse()
        let channel = self.addChannelNamed("#chat", toClient: client)
        let label: String! = client.registerPendingDeliveryForChannel(channel)
        let ack = self.message("@label=g1 ACK", onClient: client)

        XCTAssertTrue(client.resolveLabeledResponseForMessage(ack))
        XCTAssertEqual(client.deliveryStateForLabel(label), TVCLogLineDeliveryStateDelivered)
    }
    @objc
    func testTimeoutMarksFailed() {
        let client = self.clientWithLabeledResponse()
        let channel = self.addChannelNamed("#chat", toClient: client)
        let label: String! = client.registerPendingDeliveryForChannel(channel)

        client.timeoutDeliveryWithLabel(label)
        XCTAssertEqual(client.deliveryStateForLabel(label), TVCLogLineDeliveryStateFailed)
    }
    @objc
    func testUnknownLabelIsNotConsumed() {
        let client = self.clientWithLabeledResponse()
        let echo = self.message("@label=unknown :me!u@h PRIVMSG #chat :hello", onClient: client)

        XCTAssertFalse(client.resolveLabeledResponseForMessage(echo))
    }
}