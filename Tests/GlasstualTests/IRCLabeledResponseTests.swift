/*  *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
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

@testable import Glasstual
import Testing

@MainActor
@Suite("Labeled response tracking")
struct IRCLabeledResponseTests {
	/// A label rides on a `label` tag, so labeled-response needs message-tags
	/// and nothing else: with no other response the server sends ACK, which
	/// resolves the delivery without echo-message.
	@Test("Tracking needs message-tags and labeled-response")
	func trackingRequiresBothCapabilities() {
		let client = GLTTestClient()
		client.enableCapability(.labeledResponse)

		#expect(client.labeledResponseTrackingEnabled() == false)
		#expect(client.registerPendingDelivery(for: nil) == nil)

		client.enableCapability(.messageTags)

		#expect(client.labeledResponseTrackingEnabled())
	}

	@Test("Registering a delivery hands back a label that is still pending")
	func registerCreatesPendingDeliveryWithLabel() throws {
		let client = clientWithLabeledResponse()
		let channel = try makeChannel(named: "#chat", on: client)
		let label = try #require(client.registerPendingDelivery(for: channel))

		#expect(label == "g1")
		#expect(client.deliveryState(forLabel: label) == .pending)
	}

	/// A resolved delivery is retired, so the label no longer matches anything.
	@Test(
		"An echo, a FAIL or an ACK carrying the label is consumed",
		arguments: [
			"@label=g1;msgid=abc123 :me!u@h PRIVMSG #chat :hello",
			"@label=g1 FAIL PRIVMSG ACCOUNT_REQUIRED_TO_MESSAGE :You must be registered",
			"@label=g1 ACK",
		]
	)
	func labeledResponseIsConsumed(_ line: String) throws {
		let client = clientWithLabeledResponse()
		let channel = try makeChannel(named: "#chat", on: client)
		let label = try #require(client.registerPendingDelivery(for: channel))
		let response = try message(line, on: client)

		#expect(client.resolveLabeledResponse(for: response))
		#expect(client.deliveryState(forLabel: label) == .none)
	}

	@Test("A delivery that times out is retired")
	func timeoutRetiresDelivery() throws {
		let client = clientWithLabeledResponse()
		let channel = try makeChannel(named: "#chat", on: client)
		let label = try #require(client.registerPendingDelivery(for: channel))

		client.timeoutDelivery(withLabel: label)

		#expect(client.deliveryState(forLabel: label) == .none)
	}

	@Test("A response carrying an unknown label is left to the ordinary handlers")
	func unknownLabelIsNotConsumed() throws {
		let client = clientWithLabeledResponse()
		let echo = try message("@label=unknown :me!u@h PRIVMSG #chat :hello", on: client)

		#expect(client.resolveLabeledResponse(for: echo) == false)
	}

	private func message(_ line: String, on client: IRCClient) throws -> Message {
		try #require(Message(line: line, on: client))
	}

	private func clientWithLabeledResponse() -> GLTTestClient {
		let client = GLTTestClient()
		client.enableCapability(.messageTags)
		client.enableCapability(.echoMessage)
		client.enableCapability(.labeledResponse)
		return client
	}

	private func makeChannel(named name: String, on client: GLTTestClient) throws -> Channel {
		try #require(client.findChannelOrCreate(name))
	}
}
