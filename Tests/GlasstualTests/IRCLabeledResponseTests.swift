@testable import Glasstual
import XCTest

/// Preprocessor directives found in file:
/// #import <XCTest/XCTest.h>
/// #import "GLTTestClient.h"
/// #import "IRCMessage.h"
/// #import "TVCLogLine.h"
/** *********************************************************************
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
@MainActor
final class IRCLabeledResponseTests: XCTestCase {
	private func message(_ line: String, on client: IRCClient) -> Message {
		Message(line: line, on: client)!
	}

	private func clientWithLabeledResponse() -> GLTTestClient {
		let client = GLTTestClient()
		client.enableCapability(.messageTags)
		client.enableCapability(.echoMessage)
		client.enableCapability(.labeledResponse)
		return client
	}

	private func addChannel(named name: String, to client: GLTTestClient) -> Channel {
		client.findChannelOrCreate(name)!
	}

	func testTrackingRequiresBothCapabilities() {
		let client = GLTTestClient()
		client.enableCapability(.labeledResponse)

		XCTAssertFalse(client.labeledResponseTrackingEnabled())
		XCTAssertNil(client.registerPendingDelivery(for: nil))

		client.enableCapability(.echoMessage)
		XCTAssertTrue(client.labeledResponseTrackingEnabled())
	}

	func testRegisterCreatesPendingDeliveryWithLabel() throws {
		let client = clientWithLabeledResponse()
		let label = client.registerPendingDelivery(for: addChannel(named: "#chat", to: client))

		XCTAssertEqual(label, "g1")
		XCTAssertEqual(try client.deliveryState(forLabel: XCTUnwrap(label)), .pending)
	}

	func testEchoWithLabelIsConsumed() {
		assertResolution(line: "@label=g1;msgid=abc123 :me!u@h PRIVMSG #chat :hello")
	}

	func testFailWithLabelIsConsumed() {
		assertResolution(line: "@label=g1 FAIL PRIVMSG ACCOUNT_REQUIRED_TO_MESSAGE :You must be registered")
	}

	func testAckWithLabelIsConsumed() {
		assertResolution(line: "@label=g1 ACK")
	}

	func testTimeoutRetiresDelivery() throws {
		let client = clientWithLabeledResponse()
		let label = try XCTUnwrap(client.registerPendingDelivery(for: addChannel(named: "#chat", to: client)))

		client.timeoutDelivery(withLabel: label)

		XCTAssertEqual(client.deliveryState(forLabel: label), .none)
	}

	func testUnknownLabelIsNotConsumed() {
		let client = clientWithLabeledResponse()
		let echo = message("@label=unknown :me!u@h PRIVMSG #chat :hello", on: client)

		XCTAssertFalse(client.resolveLabeledResponse(for: echo))
	}

	/// A resolved delivery is retired, so the label no longer matches anything.
	private func assertResolution(line: String) {
		let client = clientWithLabeledResponse()
		let label = client.registerPendingDelivery(for: addChannel(named: "#chat", to: client))!
		let response = message(line, on: client)

		XCTAssertTrue(client.resolveLabeledResponse(for: response))
		XCTAssertEqual(client.deliveryState(forLabel: label), .none)
	}
}
