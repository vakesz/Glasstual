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

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Client capability negotiation")
struct IRCClientNegotiationTests {
	@Test("Grouped requests fit the wire budget and preserve order")
	func groupedRequestsRespectByteLimit() {
		let names = (0 ..< 80).map { "vendor/capability-\($0)" }
		let groups = CapabilityRequestBatching.groups(names)
		#expect(groups.count > 1)
		#expect(groups.flatMap(\.self) == names)
		#expect(groups.allSatisfy { "CAP REQ :\($0.joined(separator: " "))\r\n".utf8.count <= 512 })
	}

	@Test("Disabling SASL skips negotiation while retaining the password for NickServ")
	func disabledSASLKeepsPassword() throws {
		let client = makeClient(configuration: ["usesSASL": false], nicknamePassword: "secret")
		try client.handleCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * LS :sasl=PLAIN,SCRAM-SHA-256,EXTERNAL",
			on: client
		))
		#expect(capabilityCommands(of: client) == ["END"])
		#expect(client.saslMechanism == nil)
		#expect(client.config.nicknamePassword == "secret")
	}

	@Test("A continued capability listing is not answered until the last line arrives")
	func capabilityListContinuationDefersRequests() throws {
		let client = GLTTestClient()

		try client.handleCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * LS * :multi-prefix sasl=PLAIN,EXTERNAL",
			on: client
		))

		#expect(client.sentCapabilityCommands.count == 0)
		#expect(client.capabilityNegotiation.outstandingRequests.isEmpty)

		try client.handleCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * LS :server-time message-tags example.com/vendor",
			on: client
		))

		/* Every request the completed listing makes eligible goes out at once,
		 so one that is never answered cannot hold back the rest. */
		#expect(capabilityCommands(of: client) == ["REQ message-tags multi-prefix server-time"])
		#expect(client.capabilityNegotiation.outstandingRequests == ["message-tags", "multi-prefix", "server-time"])
	}

	@Test("An acknowledgement enables the capability and asks for the next one")
	func acknowledgementEnablesCapabilityAndContinuesNegotiation() throws {
		let client = GLTTestClient()

		try client.handleCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * LS :multi-prefix server-time",
			on: client
		))
		#expect(capabilityCommands(of: client) == ["REQ multi-prefix server-time"])

		try client.handleCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP me ACK :multi-prefix",
			on: client
		))

		#expect(client.isCapabilityEnabled(.multiPrefix))
		#expect(client.isCapabilityEnabled(.serverTime) == false)
		// One answer arriving does not close a negotiation the other still holds.
		#expect(client.capabilityNegotiation.outstandingRequests == ["server-time"])

		try client.handleCapabilityOrAuthenticationRequest(message(
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

		try client.handleCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * LS :znc.in/server-time-iso",
			on: client
		))
		try client.handleCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP me ACK :znc.in/server-time-iso",
			on: client
		))

		#expect(client.isCapabilityEnabled(.serverTime))

		try client.handleCapabilityOrAuthenticationRequest(message(
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

		try client.handleCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * LS :sasl=PLAIN,EXTERNAL",
			on: client
		))
		#expect(capabilityCommands(of: client) == ["REQ sasl"])

		try client.handleCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP me ACK :sasl",
			on: client
		))

		#expect(client.isCapabilityEnabled(.isInSASLNegotiation))
		#expect(capabilityCommands(of: client) == ["REQ sasl"])
	}

	@Test("Negotiation ends when the server offers no mechanism the client speaks")
	func saslIsSkippedWhenOnlyUnsupportedMechanismsAreOffered() throws {
		let client = makeClient(configuration: [:], nicknamePassword: "secret")

		try client.handleCapabilityOrAuthenticationRequest(message(
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

	// MARK: - SASL bounds

	/** `AUTHENTICATE` has no reply the protocol obliges the server to send, so a
	 server that acknowledges `sasl` and then says nothing left capability
	 negotiation paused with `CAP END` unsent. Nothing noticed until the
	 four-minute retry timer took the whole connection down, which reads to the
	 user as the network being broken rather than as authentication failing. */
	@Test("Acknowledging SASL starts a deadline, and answering it stops one")
	func saslNegotiationIsBounded() throws {
		let client = makeClient(configuration: ["usesSASL": true], nicknamePassword: "secret")
		defer { client.stopAllTimers() }
		client.isConnected = true

		try client.handleCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * LS :sasl=PLAIN",
			on: client
		))
		try client.handleCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * ACK :sasl",
			on: client
		))

		#expect(client.isCapabilityEnabled(.isInSASLNegotiation))
		#expect(client.saslTimeoutTimer.isActive)

		client.finishSASLNegotiation(failed: false)

		#expect(client.saslTimeoutTimer.isActive == false)
	}

	/** The deadline bounds the wait for the server's next word, not the exchange
	 as a whole. SCRAM is three challenges, each of which the client answers and
	 then waits again; armed once, the last round got whatever was left of the
	 thirty seconds the first one had already spent. */
	@Test("Every AUTHENTICATE the server sends re-arms the deadline")
	func eachSASLRoundIsBounded() throws {
		let client = makeClient(configuration: ["usesSASL": true], nicknamePassword: "secret")
		defer { client.stopAllTimers() }
		client.isConnected = true

		try client.handleCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * LS :sasl=PLAIN",
			on: client
		))
		try client.handleCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * ACK :sasl",
			on: client
		))

		#expect(client.saslTimeoutTimer.isActive)

		/* Stopped so that the next round having its own deadline is what the
		 assertion sees, rather than the one the request already armed. */
		client.stopSASLTimeoutTimer()

		#expect(client.saslTimeoutTimer.isActive == false)

		try client.handleCapabilityOrAuthenticationRequest(message(
			":irc.example.net AUTHENTICATE +",
			on: client
		))

		#expect(client.isCapabilityEnabled(.isInSASLNegotiation))
		#expect(client.saslTimeoutTimer.isActive)
	}

	/// Giving up has to leave registration able to finish: the deadline aborts
	/// the exchange and lets capability negotiation run to `CAP END`.
	@Test("The deadline aborts SASL and lets registration continue")
	func saslDeadlineAbortsAndContinues() throws {
		let client = makeClient(configuration: ["usesSASL": true], nicknamePassword: "secret")
		defer { client.stopAllTimers() }
		client.isConnected = true
		try client.handleCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * LS :sasl=PLAIN",
			on: client
		))
		try client.handleCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * ACK :sasl",
			on: client
		))

		client.onSASLTimeoutTimer()

		#expect(client.isCapabilityEnabled(.isInSASLNegotiation) == false)
		#expect(client.isCapabilityEnabled(.isIdentifiedWithSASL) == false)
		#expect(client.saslTimeoutTimer.isActive == false)
		#expect(sentLines(of: client).contains { $0.hasPrefix("AUTHENTICATE") && $0.hasSuffix("*") })
		#expect(capabilityCommands(of: client).contains("END"))
		expectPrintedLineContaining(ConnectionSafetyStrings.SASL.timedOut, on: client)
	}

	/// A server that offered no mechanism this client can speak gets no
	/// deadline either, because nothing was ever asked of it.
	@Test("No deadline runs when SASL was never requested")
	func noDeadlineWithoutSASL() throws {
		let client = makeClient(configuration: ["usesSASL": false], nicknamePassword: "secret")
		defer { client.stopAllTimers() }

		try client.handleCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * LS :sasl=PLAIN",
			on: client
		))

		#expect(client.saslTimeoutTimer.isActive == false)
	}

	/** PLAIN is three fields separated by U+0000. A field containing one splits
	 somewhere else on the server, which either authenticates as a name the user
	 did not type or sends the tail of the password as a separate field. */
	@Test("A credential containing a null character is refused rather than sent")
	func nullCharactersInCredentialsAbortSASL() throws {
		let client = makeClient(configuration: ["usesSASL": true], nicknamePassword: "hunter\u{0}2")
		defer { client.stopAllTimers() }
		client.isConnected = true
		try client.handleCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * LS :sasl=PLAIN",
			on: client
		))
		try client.handleCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * ACK :sasl",
			on: client
		))

		try client.handleCapabilityOrAuthenticationRequest(message("AUTHENTICATE +", on: client))

		let lines = sentLines(of: client)

		#expect(lines.contains { $0.contains("hunter") } == false)
		#expect(lines.contains { $0.hasPrefix("AUTHENTICATE") && $0.hasSuffix("*") })
		#expect(client.isCapabilityEnabled(.isInSASLNegotiation) == false)
		expectPrintedLineContaining(
			ConnectionSafetyStrings.SASL.credentialsContainNullCharacter, on: client
		)
	}

	/** Asking whether SASL can be requested is a question. It is asked again on
	 every `CAP NEW` and `CAP DEL`, so choosing the mechanism inside it let a
	 late advertisement replace the mechanism of an exchange already in flight —
	 and the reply the client then sent belonged to neither. */
	@Test("A late SASL advertisement does not replace an in-flight mechanism")
	func aLateAdvertisementDoesNotReplaceTheMechanism() throws {
		let client = makeClient(
			configuration: ["usesSASL": true, "saslMechanismPreference": "SCRAM-SHA-256"],
			nicknamePassword: "secret"
		)
		defer { client.stopAllTimers() }
		try client.handleCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * LS :sasl=SCRAM-SHA-256,PLAIN",
			on: client
		))
		try client.handleCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * ACK :sasl",
			on: client
		))

		let chosen = client.saslMechanism

		#expect(chosen == SCRAMClient.mechanismName)

		try client.handleCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * NEW :sasl=PLAIN",
			on: client
		))

		#expect(client.saslMechanism == chosen)
	}

	private func expectPrintedLineContaining(_ text: String, on client: GLTTestClient) {
		let bodies = (client.printedLines as NSArray).compactMap {
			($0 as? [String: Any])?["messageBody"] as? String
		}

		#expect(bodies.contains { $0.contains(text) })
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
		type: LogLineType,
		channel: Channel?,
		sourceLocation: SourceLocation = #_sourceLocation
	) throws {
		let printed = try #require(printedLine(at: index, on: client), sourceLocation: sourceLocation)

		#expect(printed["messageBody"] as? String == body, sourceLocation: sourceLocation)
		#expect((printed["lineType"] as? NSNumber)?.uintValue == type.rawValue, sourceLocation: sourceLocation)
		#expect(printed["channel"] as? Channel === channel, sourceLocation: sourceLocation)
	}
}
