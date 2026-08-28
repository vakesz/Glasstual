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
import Testing

@MainActor
@Suite("Client capability negotiation")
struct IRCClientNegotiationTests {
	@Test("A continued capability listing is not answered until the last line arrives")
	func capabilityListContinuationDefersRequests() throws {
		let client = GLTTestClient()

		try client.receiveCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * LS * :multi-prefix sasl=PLAIN,EXTERNAL",
			on: client
		))

		#expect(client.sentCapabilityCommands.count == 0)
		#expect(client.pendingCapabilityRequests.count == 0)

		try client.receiveCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * LS :server-time message-tags example.com/vendor",
			on: client
		))

		#expect(capabilityCommands(of: client) == ["REQ message-tags"])
		#expect(client.pendingCapabilityRequests == ["multi-prefix", "server-time"])
	}

	@Test("An acknowledgement enables the capability and asks for the next one")
	func acknowledgementEnablesCapabilityAndContinuesNegotiation() throws {
		let client = GLTTestClient()

		try client.receiveCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * LS :multi-prefix server-time",
			on: client
		))
		#expect(capabilityCommands(of: client) == ["REQ multi-prefix"])

		try client.receiveCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP me ACK :multi-prefix",
			on: client
		))

		#expect(client.isCapabilityEnabled(.multiPrefix))
		#expect(client.isCapabilityEnabled(.serverTime) == false)
		#expect(capabilityCommands(of: client) == ["REQ multi-prefix", "REQ server-time"])

		try client.receiveCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP me NAK :server-time",
			on: client
		))

		#expect(client.isCapabilityEnabled(.serverTime) == false)
		#expect(capabilityCommands(of: client).last == "END")
		#expect(client.enabledCapabilitiesStringValue == "multi-prefix")
	}

	@Test("A vendor spelling of server-time enables the generic capability")
	func vendorServerTimeEnablesGenericBit() throws {
		let client = GLTTestClient()

		try client.receiveCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * LS :znc.in/server-time-iso",
			on: client
		))
		try client.receiveCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP me ACK :znc.in/server-time-iso",
			on: client
		))

		#expect(client.isCapabilityEnabled(.serverTime))

		try client.receiveCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP me DEL :znc.in/server-time-iso",
			on: client
		))

		#expect(client.isCapabilityEnabled(.serverTime) == false)
	}

	@Test("SASL is requested when the client has a password to send")
	func saslIsRequestedWhenPasswordIsConfigured() throws {
		let client = makeClient(
			configuration: ["nickname": "me", "username": "me"],
			nicknamePassword: "secret"
		)

		try client.receiveCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * LS :sasl=PLAIN,EXTERNAL",
			on: client
		))
		#expect(capabilityCommands(of: client) == ["REQ sasl"])

		try client.receiveCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP me ACK :sasl",
			on: client
		))

		#expect(client.isCapabilityEnabled(.isInSASLNegotiation))
		#expect(capabilityCommands(of: client) == ["REQ sasl"])
	}

	@Test("Negotiation ends when the server offers no mechanism the client speaks")
	func saslIsSkippedWhenOnlyUnsupportedMechanismsAreOffered() throws {
		let client = makeClient(configuration: [:], nicknamePassword: "secret")

		try client.receiveCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * LS :sasl=SCRAM-SHA-512,GSSAPI",
			on: client
		))

		#expect(capabilityCommands(of: client) == ["END"])
	}

	@Test("SCRAM is preferred over PLAIN when both are offered")
	func scramIsPreferredOverPlain() {
		let client = makeClient(configuration: ["nickname": "me"], nicknamePassword: "secret")

		#expect(client.selectSASLMechanism(fromOffered: ["PLAIN", "SCRAM-SHA-256"]))
		#expect(client.saslMechanism == "SCRAM-SHA-256")
	}

	@Test("PLAIN is chosen when SCRAM is not offered")
	func plainIsChosenWhenSCRAMIsNotOffered() {
		let client = makeClient(configuration: ["nickname": "me"], nicknamePassword: "secret")

		#expect(client.selectSASLMechanism(fromOffered: ["PLAIN"]))
		#expect(client.saslMechanism == "PLAIN")
	}

	@Test("A retry moves to the next mechanism and never repeats one")
	func saslMechsRetryMovesToNextMechanism() {
		let client = makeClient(configuration: ["nickname": "me"], nicknamePassword: "secret")
		_ = client.selectSASLMechanism(fromOffered: ["PLAIN", "SCRAM-SHA-256"])

		#expect(client.saslMechanism == "SCRAM-SHA-256")
		#expect(client.retrySASLNegotiation(withMechanisms: ["PLAIN"]))
		#expect(client.saslMechanism == "PLAIN")
		#expect(client.saslTriedMechanisms.contains("SCRAM-SHA-256"))
		#expect(client.retrySASLNegotiation(withMechanisms: ["PLAIN"]) == false)
	}

	@Test("Nested batches are replayed in the order the server sent them")
	func nestedBatchesAreReplayedInOrder() throws {
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
			let parsedMessage = try message(line, on: client)

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

		#expect(bodies == ["one", "two", "three", "four"])
	}

	@Test("A message tagged with an unknown batch is delivered rather than queued")
	func messagesOutsideAnOpenBatchAreNotQueued() throws {
		let client = GLTTestClient()
		client.enableCapability(.batch)

		let filtered = try client.filterBatchCommandIncomingData(message(
			"@batch=unknown :a!u@h PRIVMSG #c :hi",
			on: client
		))

		#expect(filtered == false)
	}

	@Test("A standard reply is printed to the channel it names, or to the console")
	func standardRepliesArePrintedToConsoleOrChannel() throws {
		let client = GLTTestClient()

		try client.receiveStandardReply(message(
			":irc.example.net FAIL BOX BOXES_INVALID STACK CLOCKWISE :Given boxes are not supported",
			on: client
		))

		#expect(client.printedLines.count == 1)
		try expectPrintedLine(
			at: 0,
			on: client,
			body: "FAIL BOX/BOXES_INVALID: Given boxes are not supported",
			type: .debug,
			channel: nil
		)

		try client.receiveStandardReply(message(
			":irc.example.net NOTE * OPER_MESSAGE :The message",
			on: client
		))
		try expectPrintedLine(
			at: 1,
			on: client,
			body: "NOTE */OPER_MESSAGE: The message",
			type: .notice,
			channel: nil
		)

		let channel = try #require(client.findChannelOrCreate("#chat"))
		try client.receiveStandardReply(message(
			":irc.example.net WARN REHASH CERTS_EXPIRED #chat :Certificate has expired",
			on: client
		))
		try expectPrintedLine(
			at: 2,
			on: client,
			body: "WARN REHASH/CERTS_EXPIRED: Certificate has expired",
			type: .notice,
			channel: channel
		)

		try client.receiveStandardReply(message(
			":irc.example.net WARN REHASH CERTS_EXPIRED #other :Certificate has expired",
			on: client
		))

		let unmatched = try #require(printedLine(at: 3, on: client))

		#expect(unmatched["channel"] == nil)
	}

	@Test("A tag message is only sent once message tags are negotiated")
	func tagMessageIsOnlySentWithMessageTagsEnabled() {
		let client = GLTTestClient()
		let typing = ["+typing": "active"]

		#expect(client.sendTagMessage(typing, toTarget: "#c") == false)
		#expect(client.sentLines.count == 0)

		client.enableCapability(.messageTags)

		#expect(client.sendTagMessage(typing, toTarget: "#c"))
		#expect(sentLines(of: client) == ["@+typing=active TAGMSG #c"])
		#expect(client.sendTagMessage([:], toTarget: "#c") == false)
	}

	@Test("Tags are dropped from a command until message tags are negotiated")
	func tagsAreDroppedFromCommandsWithoutMessageTags() {
		let client = GLTTestClient()

		client.sendCommand("PRIVMSG", arguments: ["#c", "hello"], tags: ["+draft/reply": "abc"])
		#expect(sentLines(of: client) == ["PRIVMSG #c :hello"])

		client.enableCapability(.messageTags)
		client.sendCommand("PRIVMSG", arguments: ["#c", "hello"], tags: ["+draft/reply": "abc"])

		#expect(sentLines(of: client).last == "@+draft/reply=abc PRIVMSG #c :hello")
	}

	@Test("A received tag message carrying no client-only tag prints nothing")
	func receivedTagMessageWithoutClientTagsIsIgnored() throws {
		let client = GLTTestClient()

		try client.receiveTagMessage(message("@msgid=1 :a!u@h TAGMSG #c", on: client))
		try client.receiveTagMessage(message("@+typing=active;msgid=2 :a!u@h TAGMSG #c", on: client))

		#expect(client.printedLines.count == 0)
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

	private func message(_ line: String, on client: IRCClient) throws -> Message {
		try #require(Message(line: line, on: client))
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

	private func expectPrintedLine(
		at index: Int,
		on client: GLTTestClient,
		body: String,
		type: TVCLogLineType,
		channel: Channel?,
		sourceLocation: SourceLocation = #_sourceLocation
	) throws {
		let printed = try #require(printedLine(at: index, on: client), sourceLocation: sourceLocation)

		#expect(printed["messageBody"] as? String == body, sourceLocation: sourceLocation)
		#expect((printed["lineType"] as? NSNumber)?.uintValue == type.rawValue, sourceLocation: sourceLocation)
		#expect(printed["channel"] as? Channel === channel, sourceLocation: sourceLocation)
	}
}
