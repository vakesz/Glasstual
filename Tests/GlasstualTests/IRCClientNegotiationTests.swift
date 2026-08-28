/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
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

@testable import Glasstual
import XCTest

@MainActor
final class IRCClientNegotiationTests: XCTestCase {
	func testCapabilityListContinuationDefersRequests() {
		let client = GLTTestClient()

		client.receiveCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * LS * :multi-prefix sasl=PLAIN,EXTERNAL",
			on: client
		))

		XCTAssertEqual(client.sentCapabilityCommands.count, 0)
		XCTAssertEqual(client.pendingCapabilityRequests.count, 0)

		client.receiveCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * LS :server-time message-tags example.com/vendor",
			on: client
		))

		XCTAssertEqual(capabilityCommands(of: client), ["REQ message-tags"])
		XCTAssertEqual(client.pendingCapabilityRequests, ["multi-prefix", "server-time"])
	}

	func testAcknowledgementEnablesCapabilityAndContinuesNegotiation() {
		let client = GLTTestClient()

		client.receiveCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * LS :multi-prefix server-time",
			on: client
		))
		XCTAssertEqual(capabilityCommands(of: client), ["REQ multi-prefix"])

		client.receiveCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP me ACK :multi-prefix",
			on: client
		))

		XCTAssertTrue(client.isCapabilityEnabled(.multiPrefix))
		XCTAssertFalse(client.isCapabilityEnabled(.serverTime))
		XCTAssertEqual(capabilityCommands(of: client), ["REQ multi-prefix", "REQ server-time"])

		client.receiveCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP me NAK :server-time",
			on: client
		))

		XCTAssertFalse(client.isCapabilityEnabled(.serverTime))
		XCTAssertEqual(capabilityCommands(of: client).last, "END")
		XCTAssertEqual(client.enabledCapabilitiesStringValue, "multi-prefix")
	}

	func testVendorServerTimeEnablesGenericBit() {
		let client = GLTTestClient()

		client.receiveCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * LS :znc.in/server-time-iso",
			on: client
		))
		client.receiveCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP me ACK :znc.in/server-time-iso",
			on: client
		))

		XCTAssertTrue(client.isCapabilityEnabled(.serverTime))

		client.receiveCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP me DEL :znc.in/server-time-iso",
			on: client
		))

		XCTAssertFalse(client.isCapabilityEnabled(.serverTime))
	}

	func testSASLIsRequestedWhenPasswordIsConfigured() {
		let client = makeClient(
			configuration: ["nickname": "me", "username": "me"],
			nicknamePassword: "secret"
		)

		client.receiveCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * LS :sasl=PLAIN,EXTERNAL",
			on: client
		))
		XCTAssertEqual(capabilityCommands(of: client), ["REQ sasl"])

		client.receiveCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP me ACK :sasl",
			on: client
		))

		XCTAssertTrue(client.isCapabilityEnabled(.isInSASLNegotiation))
		XCTAssertEqual(capabilityCommands(of: client), ["REQ sasl"])
	}

	func testSASLIsSkippedWhenOnlyUnsupportedMechanismsAreOffered() {
		let client = makeClient(configuration: [:], nicknamePassword: "secret")

		client.receiveCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * LS :sasl=SCRAM-SHA-512,GSSAPI",
			on: client
		))

		XCTAssertEqual(capabilityCommands(of: client), ["END"])
	}

	func testSCRAMIsPreferredOverPlain() {
		let client = makeClient(configuration: ["nickname": "me"], nicknamePassword: "secret")

		XCTAssertTrue(client.selectSASLMechanism(fromOffered: ["PLAIN", "SCRAM-SHA-256"]))
		XCTAssertEqual(client.saslMechanism, "SCRAM-SHA-256")
	}

	func testPlainIsChosenWhenSCRAMIsNotOffered() {
		let client = makeClient(configuration: ["nickname": "me"], nicknamePassword: "secret")

		XCTAssertTrue(client.selectSASLMechanism(fromOffered: ["PLAIN"]))
		XCTAssertEqual(client.saslMechanism, "PLAIN")
	}

	func testSASLMechsRetryMovesToNextMechanism() {
		let client = makeClient(configuration: ["nickname": "me"], nicknamePassword: "secret")
		_ = client.selectSASLMechanism(fromOffered: ["PLAIN", "SCRAM-SHA-256"])

		XCTAssertEqual(client.saslMechanism, "SCRAM-SHA-256")
		XCTAssertTrue(client.retrySASLNegotiation(withMechanisms: ["PLAIN"]))
		XCTAssertEqual(client.saslMechanism, "PLAIN")
		XCTAssertTrue(client.saslTriedMechanisms.contains("SCRAM-SHA-256"))
		XCTAssertFalse(client.retrySASLNegotiation(withMechanisms: ["PLAIN"]))
	}

	func testNestedBatchesAreReplayedInOrder() {
		let client = GLTTestClient()
		client.enableCapability(.batch)
		let lines = [
			":irc.example.net BATCH +outer example.com/outer",
			"@batch=outer :irc.example.net BATCH +inner example.com/inner",
			"@batch=inner :a!u@h PRIVMSG #c :one",
			"@batch=outer :b!u@h PRIVMSG #c :two",
			"@batch=inner :c!u@h PRIVMSG #c :three",
			":irc.example.net BATCH -inner",
			"@batch=outer :d!u@h PRIVMSG #c :four",
			":irc.example.net BATCH -outer",
		]

		for line in lines {
			let parsedMessage = message(line, on: client)

			if client.filterBatchCommandIncomingData(parsedMessage) {
				continue
			}

			if parsedMessage.command == "BATCH" {
				client.receiveBatch(parsedMessage)
			} else {
				client.processIncomingMessage(parsedMessage)
			}
		}

		let bodies = (client.processedMessages as NSArray).compactMap {
			($0 as? Message)?.sequence
		}

		XCTAssertEqual(bodies, ["one", "two", "three", "four"])
	}

	func testMessagesOutsideAnOpenBatchAreNotQueued() {
		let client = GLTTestClient()
		client.enableCapability(.batch)

		XCTAssertFalse(client.filterBatchCommandIncomingData(message(
			"@batch=unknown :a!u@h PRIVMSG #c :hi",
			on: client
		)))
	}

	func testStandardRepliesArePrintedToConsoleOrChannel() throws {
		let client = GLTTestClient()

		client.receiveStandardReply(message(
			":irc.example.net FAIL BOX BOXES_INVALID STACK CLOCKWISE :Given boxes are not supported",
			on: client
		))

		XCTAssertEqual(client.printedLines.count, 1)
		assertPrintedLine(
			at: 0,
			on: client,
			body: "FAIL BOX/BOXES_INVALID: Given boxes are not supported",
			type: .debug,
			channel: nil
		)

		client.receiveStandardReply(message(
			":irc.example.net NOTE * OPER_MESSAGE :The message",
			on: client
		))
		assertPrintedLine(
			at: 1,
			on: client,
			body: "NOTE */OPER_MESSAGE: The message",
			type: .notice,
			channel: nil
		)

		let channel = try XCTUnwrap(client.findChannelOrCreate("#chat"))
		client.receiveStandardReply(message(
			":irc.example.net WARN REHASH CERTS_EXPIRED #chat :Certificate has expired",
			on: client
		))
		assertPrintedLine(
			at: 2,
			on: client,
			body: "WARN REHASH/CERTS_EXPIRED: Certificate has expired",
			type: .notice,
			channel: channel
		)

		client.receiveStandardReply(message(
			":irc.example.net WARN REHASH CERTS_EXPIRED #other :Certificate has expired",
			on: client
		))
		XCTAssertNil(printedLine(at: 3, on: client)?["channel"])
	}

	func testTagMessageIsOnlySentWithMessageTagsEnabled() {
		let client = GLTTestClient()
		let typing = ["+typing": "active"]

		XCTAssertFalse(client.sendTagMessage(typing, toTarget: "#c"))
		XCTAssertEqual(client.sentLines.count, 0)

		client.enableCapability(.messageTags)

		XCTAssertTrue(client.sendTagMessage(typing, toTarget: "#c"))
		XCTAssertEqual(sentLines(of: client), ["@+typing=active TAGMSG #c"])
		XCTAssertFalse(client.sendTagMessage([:], toTarget: "#c"))
	}

	func testTagsAreDroppedFromCommandsWithoutMessageTags() {
		let client = GLTTestClient()

		client.sendCommand("PRIVMSG", arguments: ["#c", "hello"], tags: ["+draft/reply": "abc"])
		XCTAssertEqual(sentLines(of: client), ["PRIVMSG #c :hello"])

		client.enableCapability(.messageTags)
		client.sendCommand("PRIVMSG", arguments: ["#c", "hello"], tags: ["+draft/reply": "abc"])

		XCTAssertEqual(sentLines(of: client).last, "@+draft/reply=abc PRIVMSG #c :hello")
	}

	func testReceivedTagMessageWithoutClientTagsIsIgnored() {
		let client = GLTTestClient()

		client.receiveTagMessage(message("@msgid=1 :a!u@h TAGMSG #c", on: client))
		client.receiveTagMessage(message("@+typing=active;msgid=2 :a!u@h TAGMSG #c", on: client))

		XCTAssertEqual(client.printedLines.count, 0)
	}

	private func makeClient(configuration: NSDictionary, nicknamePassword: String) -> GLTTestClient {
		guard let configuration = configuration as? [String: Any] else {
			preconditionFailure("Test configuration must bridge to a Swift dictionary")
		}

		return GLTTestClient(
			configDictionary: configuration,
			nicknamePassword: nicknamePassword
		)
	}

	private func message(_ line: String, on client: IRCClient) -> Message {
		Message(line: line, on: client)!
	}

	private func capabilityCommands(of client: GLTTestClient) -> [String] {
		(client.sentCapabilityCommands as NSArray).compactMap { $0 as? String }
	}

	private func sentLines(of client: GLTTestClient) -> [String] {
		(client.sentLines as NSArray).compactMap { $0 as? String }
	}

	private func printedLine(at index: Int, on client: GLTTestClient) -> [String: Any]? {
		client.printedLines[index] as? [String: Any]
	}

	private func assertPrintedLine(
		at index: Int,
		on client: GLTTestClient,
		body: String,
		type: TVCLogLineType,
		channel: Channel?,
		file: StaticString = #filePath,
		line: UInt = #line
	) {
		let printed = printedLine(at: index, on: client)

		XCTAssertEqual(printed?["messageBody"] as? String, body, file: file, line: line)
		XCTAssertEqual((printed?["lineType"] as? NSNumber)?.uintValue, type.rawValue, file: file, line: line)

		if let channel {
			XCTAssertTrue(printed?["channel"] as? Channel === channel, file: file, line: line)
		} else {
			XCTAssertNil(printed?["channel"], file: file, line: line)
		}
	}
}
