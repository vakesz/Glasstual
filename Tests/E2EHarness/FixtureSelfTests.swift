import Foundation
import Network
import Security

/// Safe without a GUI session: synthetic clients talk only to an in-process loopback peer.
enum FixtureSelfTests {
	/// Runs the pure protocol checks, then one synthetic client per mode.
	/// Prints one line per mode and returns whether all passed.
	static func run(corpora: URL, only: Set<String>? = nil) async -> Bool {
		do {
			try protocolChecks()
		} catch {
			print("FAIL fixture protocol checks: \(error)")
			return false
		}
		var passed = true
		for mode in FixtureMode.allCases where only?.contains(mode.rawValue) ?? true {
			let start = ContinuousClock.now
			do {
				try await check(mode, corpora: corpora)
				print(String(format: "PASS fixture.%@ %.1fs", mode.rawValue, (ContinuousClock.now - start).inSeconds))
			} catch {
				passed = false
				print(String(format: "FAIL fixture.%@ %.1fs: %@", mode.rawValue, (ContinuousClock.now - start).inSeconds,
				             String(describing: error)))
			}
		}
		return passed
	}

	private static func check(_ mode: FixtureMode, corpora: URL) async throws {
		let peer = try LoopbackPeer(mode: mode, corpora: corpora, passiveDCC: mode.secureDCC)
		defer { peer.stop() }
		guard let port = try await NWEndpoint.Port(rawValue: peer.start()) else {
			throw HarnessFailure.assertion("Self-test port missing")
		}
		let attempts = mode == .tlsRejectRetry ? 2 : mode.rejectionCount + 1
		for attempt in 1 ... attempts {
			let rejectTLS = mode == .tlsRejectRetry && attempt == 1
			let client = Client(
				port: port,
				tls: mode.secured,
				trust: !rejectTLS,
				maximumBytes: mode == .burstResponsiveness ? 2 * 1024 * 1024 : 65536
			)
			defer { client.connection.cancel() }
			client.start()
			if mode == .tlsStall {
				try await wait(peer, "peer holds the ClientHello") { peer.evidence.tlsStalled }
				try await Task.sleep(for: .milliseconds(200))
				guard client.received.isEmpty else { throw HarnessFailure.assertion("Stall emitted bytes") }
				client.connection.cancel()
				break
			}
			if rejectTLS {
				try await wait(peer, "peer saw the rejected handshake close") { peer.evidence.tlsRejected }
				guard client.received.isEmpty else { throw HarnessFailure.assertion("Rejected TLS emitted IRC") }
				continue
			}
			try await wait(peer, "client connected") { client.connection.state == .ready }
			if mode.webSocket {
				try await FixtureExtensionChecks.webSocket(peer: peer, client: client)
				client.connection.cancel()
				continue
			}
			// Exercise line framing across writes as well as several commands in one write.
			if mode.scripted != nil {
				try await FixtureExtensionChecks.register(mode, peer: peer, client: client)
			} else if let answer = mode.saslConsent {
				try await consentRegistration(answer: answer, client: client)
			} else if mode == .banAccount {
				try await banAccountRegistration(client: client)
			} else {
				try await client.send("CAP LS ")
				try await client.send("302\r\n")
				try await wait(peer, "CAP LS reply") { client.contains(":e2e.local CAP * LS :\r\n") }
				try await client.send("NICK e2euser\r\nUSER e2euser 0 * :Synthetic E2E User\r\nCAP END\r\n")
			}
			if attempt <= mode.rejectionCount {
				try await wait(peer, "registration rejected") {
					client.contains("ERROR :E2E_REGISTRATION_REJECTED\r\n") && client.ended
				}
				continue
			}
			try await wait(peer, "welcome") { client.contains("E2E_TRANSCRIPT_READY\r\n") }
			try await client.send("PONG E2E_PING\r\n")
			if mode.messaging {
				try await client.send("JOIN #e2e\r\n")
				try await wait(peer, "channel ready") { client.contains("E2E_CHANNEL_READY\r\n") }
				try await client.send("PRIVMSG #e2e :E2E_TYPED_MESSAGE\r\n")
				try await wait(peer, "server reply") { client.contains("E2E_SERVER_REPLY\r\n") }
				try await client.send("PRIVMSG #e2e :fixture: E2E_TYPED_REPLY\r\n")
				try await wait(peer, "reply acknowledged") { client.contains("E2E_REPLY_ACK\r\n") }
			}
			if mode == .channelDenied {
				try await deniedJoinChecks(peer: peer, client: client)
			}
			if mode == .banAccount {
				try await client.send("JOIN #e2e\r\n")
				try await wait(peer, "channel with accounts") { client.contains("ACCOUNT \(BanAccountFixture.account)\r\n") }
				try await client.send(BanAccountFixture.expectedBan + "\r\n")
				try await wait(peer, "ban echoed") { client.contains(BanAccountFixture.expectedBan + "\r\n") }
				guard peer.evidence.banLine == BanAccountFixture.expectedBan else {
					throw HarnessFailure.assertion("Ban Account evidence missing")
				}
			}
			if mode.scripted != nil {
				try await FixtureExtensionChecks.exchange(mode, peer: peer, client: client)
			}
			if mode.secureDCC {
				try await FixtureExtensionChecks.secureDCC(mode, peer: peer, client: client, corpora: corpora)
			} else if mode.interactive {
				try await interactiveChecks(mode: mode, peer: peer, client: client)
			}
			try await client.send("QUIT E2E_QUIT\r\n", final: true)
			try await wait(peer, "peer saw QUIT") { peer.evidence.quitSeen }
			if let answer = mode.saslConsent {
				guard peer.evidence.consent == SASLConsentFixture(answer: answer).expectedEvidence
				else { throw HarnessFailure.assertion("Consent evidence did not match the answer") }
			}
			client.connection.cancel()
		}
		// Every path out of the loop ends here, including the TLS stall break and
		// the rejection continues, so one wait covers the peer's observed end.
		try await wait(peer, "peer complete") { peer.evidence.complete }
	}

	/// `Wait.until` that fails at once when the peer recorded a violation.
	static func wait(
		_ peer: LoopbackPeer,
		_ description: String,
		_ condition: () throws -> Bool
	) async throws {
		try await Wait.until(description, timeout: .seconds(20)) {
			try peer.check()
			return try condition()
		}
	}

	private static func deniedJoinChecks(peer: LoopbackPeer, client: Client) async throws {
		try await client.send("JOIN #other\r\n")
		try await wait(peer, "other channel") { client.contains("E2E_OTHER_READY\r\n") }
		try await client.send("JOIN #retry\r\n")
		try await wait(peer, "denied JOIN") { client.contains("477 e2euser #retry :E2E_JOIN_DENIED") }
		try await client.send("PRIVMSG NickServ :IDENTIFY E2E_SYNTHETIC\r\n")
		try await wait(peer, "identified") { client.contains("E2E_IDENTIFIED_READY\r\n") }
		guard client.contains("900 e2euser"), client.contains("ACCOUNT e2eaccount"), client.contains("MODE e2euser :+r")
		else { throw HarnessFailure.assertion("Fixture identification signals missing") }
		try await client.send("JOIN #retry\r\n")
		try await wait(peer, "retry joined") { client.contains("E2E_RETRY_JOINED\r\n") }
	}

	private static func banAccountRegistration(client: Client) async throws {
		try await client.send("CAP LS 302\r\n")
		try await Wait.until("account-notify offered") { client.contains("CAP * LS :account-notify\r\n") }
		try await client.send("NICK e2euser\r\nUSER e2euser 0 * :Synthetic E2E User\r\nCAP REQ :account-notify\r\n")
		try await Wait.until("account-notify acknowledged") { client.contains("CAP * ACK :account-notify\r\n") }
		try await client.send("CAP END\r\n")
		try await Wait.until("account bans announced") { client.contains("ACCOUNTEXTBAN=account") }
	}

	/// A synthetic client doing what the app does once its user has answered:
	/// what the peer then has to have seen on the wire.
	private static func consentRegistration(answer: SASLConsentFixture.Answer, client: Client) async throws {
		try await client.send("CAP LS 302\r\n")
		try await Wait.until("SASL offered") { client.contains(":e2e.local CAP * LS :sasl=PLAIN\r\n") }
		switch answer {
		case .decline:
			try await client.send("NICK e2euser\r\nUSER e2euser 0 * :Synthetic E2E User\r\n")
		case .send:
			try await client.send("PASS \(SASLConsentFixture.serverSecret)\r\n")
			try await client.send("NICK e2euser\r\nUSER e2euser 0 * :Synthetic E2E User\r\n")
			try await client.send("CAP REQ :sasl\r\n")
			try await Wait.until("SASL acknowledged") { client.contains(":e2e.local CAP * ACK :sasl\r\n") }
			try await client.send("AUTHENTICATE PLAIN\r\n")
			try await Wait.until("PLAIN accepted") { client.contains("AUTHENTICATE +\r\n") }
			try await client.send("AUTHENTICATE \(SASLConsentFixture.expectedPayload)\r\n")
			try await Wait.until("SASL succeeded") { client.contains(" 903 e2euser ") }
		}
		try await client.send("CAP END\r\n")
	}

	private static func consentChecks() throws {
		let pass = "PASS " + SASLConsentFixture.serverSecret
		let payload = "AUTHENTICATE " + SASLConsentFixture.expectedPayload
		let identity = ["NICK e2euser", "USER e2euser 0 * :Synthetic E2E User"]
		func feed(_ answer: SASLConsentFixture.Answer, _ lines: [String]) throws -> SASLConsentFixture {
			var fixture = SASLConsentFixture(answer: answer)
			for line in lines {
				_ = try fixture.receive(line)
			}
			return fixture
		}

		// Don't Send: registration without PASS or SASL.
		let declined = try feed(.decline, ["CAP LS 302"] + identity + ["CAP END"])
		guard declined.isRegistered, declined.evidence == declined.expectedEvidence
		else { throw HarnessFailure.assertion("Declined consent self-test failed") }
		var passAfterDecline = try feed(.decline, ["CAP LS 302"])
		try mustReject { _ = try passAfterDecline.receive(pass) }
		var saslAfterDecline = try feed(.decline, ["CAP LS 302"] + identity)
		try mustReject { _ = try saslAfterDecline.receive("CAP REQ :sasl") }
		var nothingBeforeCapabilities = SASLConsentFixture(answer: .decline)
		try mustReject { _ = try nothingBeforeCapabilities.receive("NICK e2euser") }

		// Send Password: PASS before NICK, then SASL PLAIN with the account secret.
		let sasl = ["CAP LS 302", pass] + identity + ["CAP REQ :sasl", "AUTHENTICATE PLAIN"]
		var sent = try feed(.send, sasl)
		try mustReject { _ = try sent.receive("AUTHENTICATE aGVsbG8=") }
		var sentAgain = try feed(.send, sasl)
		_ = try sentAgain.receive(payload)
		try mustReject { _ = try sentAgain.receive(payload) }
		var nickBeforePass = try feed(.send, ["CAP LS 302"])
		try mustReject { _ = try nickBeforePass.receive("NICK e2euser") }
		var passBeforeCapabilities = SASLConsentFixture(answer: .send)
		try mustReject { _ = try passBeforeCapabilities.receive(pass) }
		var secretOnAnotherCommand = try feed(.send, sasl)
		try mustReject { _ = try secretOnAnotherCommand.receive("PRIVMSG x :" + SASLConsentFixture.secret) }
		var serverSecretElsewhere = try feed(.send, ["CAP LS 302"])
		try mustReject { _ = try serverSecretElsewhere.receive("PRIVMSG x :" + SASLConsentFixture.serverSecret) }
		var endedTooSoon = try feed(.send, sasl)
		try mustReject { _ = try endedTooSoon.receive("CAP END") }
		let complete = try feed(.send, sasl + [payload, "CAP END"])
		guard complete.isRegistered, complete.evidence == complete.expectedEvidence
		else { throw HarnessFailure.assertion("Sent consent self-test failed") }
	}

	private static func banAccountChecks() throws {
		var fixture = BanAccountFixture()
		for line in ["CAP LS 302", "NICK e2euser", "USER e2euser 0 * :Synthetic E2E User", "CAP REQ :account-notify"] {
			_ = try fixture.register(line)
		}
		let welcome = try fixture.register("CAP END")
		guard fixture.isRegistered, welcome.contains(where: { $0.contains("ACCOUNTEXTBAN=account") })
		else { throw HarnessFailure.assertion("Ban Account registration self-test failed") }
		try mustReject { _ = try fixture.receive("JOIN #e2e", pongSeen: false) }
		_ = try fixture.receive("JOIN #e2e", pongSeen: true)
		var wrongBan = fixture
		try mustReject { _ = try wrongBan.receive("MODE #e2e +b fixture!*@*", pongSeen: true) }
		var otherAccount = fixture
		try mustReject { _ = try otherAccount.receive("MODE #e2e +b ~account:noaccount", pongSeen: true) }
		_ = try fixture.receive(BanAccountFixture.expectedBan, pongSeen: true)
		guard fixture.banned else { throw HarnessFailure.assertion("Ban Account self-test failed") }
		try mustReject { _ = try fixture.receive(BanAccountFixture.expectedBan, pongSeen: true) }
	}

	private static func protocolChecks() throws {
		try consentChecks()
		try banAccountChecks()
		try FixtureExtensionChecks.protocolChecks()
		let sample = Diagnostics.mainThreadSummary(Data("""
		Path: /Users/private/Glasstual
		Thread_1 DispatchQueue_1: com.apple.main-thread
		+ 10 -[NSApplication run] (in AppKit) + 123 [0x123]
		+ 10 /Users/private/source.swift (in Glasstual)
		Thread_2
		+ 10 privateBackgroundSymbol (in Foundation)
		""".utf8))
		guard sample.contains("AppKit: [NSApplication run]"), !sample.contains("private"),
		      !sample.contains("0x123")
		else {
			throw HarnessFailure.assertion("Sample privacy filter failed")
		}
		var registered = FixtureProtocol(reject: false, messaging: false)
		for line in FixtureProtocol.registration.compactMap(\.first) {
			_ = try registered.receive(line)
		}
		guard registered.registrationIndex == FixtureProtocol.registration.count
		else { throw HarnessFailure.assertion("Registration self-test failed") }
		for line in ["PASS private", "AUTHENTICATE private", "USER wrong 0 * :private", "QUIT E2E_QUIT",
		             "JOIN #wrong"]
		{
			var state = registered
			try mustReject { _ = try state.receive(line) }
		}
		var outOfOrder = FixtureProtocol(reject: false, messaging: false)
		try mustReject { _ = try outOfOrder.receive("NICK e2euser") }
		try mustReject { try registered.eof(pending: Data()) }
		_ = try registered.receive("PONG E2E_PING")
		try mustReject { _ = try registered.receive("PONG E2E_PING") }
		_ = try registered.receive("QUIT E2E_QUIT")
		try registered.eof(pending: Data())
		try mustReject { try registered.eof(pending: Data([1])) }
		try mustReject { _ = try registered.receive("MODE e2euser") }
		var channel = FixtureProtocol(reject: false, messaging: true)
		for line in FixtureProtocol.registration.compactMap(\.first) {
			_ = try channel.receive(line)
		}
		_ = try channel.receive("PONG E2E_PING")
		try mustReject { _ = try channel.receive("PRIVMSG #e2e :E2E_TYPED_MESSAGE") }
		_ = try channel.receive("JOIN #e2e")
		try mustReject { _ = try channel.receive("PRIVMSG #e2e :fixture: E2E_TYPED_REPLY") }
		_ = try channel.receive("PRIVMSG #e2e :E2E_TYPED_MESSAGE")
		try mustReject { _ = try channel.receive("QUIT E2E_QUIT") }
		_ = try channel.receive("PRIVMSG #e2e :fixture: E2E_TYPED_REPLY")
		_ = try channel.receive("QUIT E2E_QUIT")
		try channel.eof(pending: Data())
		try deniedJoinChecks()
		try snapshotChecks()
		try interactionValidatorChecks()
		var acknowledgements = FixtureACKParser()
		try acknowledgements.receive(Data([0, 0]), sent: 10)
		try acknowledgements.receive(Data([0, 5, 0, 0, 0, 10]), sent: 10)
		guard acknowledgements.acknowledged == 10,
		      acknowledgements.pending.isEmpty
		else { throw HarnessFailure.assertion("Fragmented DCC ACK parser failed") }
		try mustReject { try acknowledgements.receive(Data([0, 0, 0, 9]), sent: 10) }
		var overshoot = FixtureACKParser()
		try mustReject { try overshoot.receive(Data([0, 0, 0, 11]), sent: 10) }
	}

	private static func interactionValidatorChecks() throws {
		var burst = InteractiveFixture(mode: .burstResponsiveness)
		try mustReject { _ = try burst.receive("PRIVMSG fixture :E2E_BURST_SWITCH_1", joined: true) }
		_ = try burst.receive("PRIVMSG fixture :E2E_BURST_START", joined: true)
		try mustReject { _ = try burst.receive("PRIVMSG fixture :E2E_BURST_SWITCH_2", joined: true) }
		// A chat offer is answered as a chat: the token it named, and no file.
		for answer in ["DCC SCHAT chat 2130706433 5000 424242", "DCC SSEND e2e-transfer.bin 2130706433 5000 100003 424241",
		               "DCC CHAT chat 2130706433 5000 424241", "DCC SCHAT chat 2130706433 0 424241"]
		{
			var chat = InteractiveFixture(mode: .dccSecureChat, usesPassiveDCC: true)
			_ = try chat.receive("PRIVMSG fixture :E2E_DCC_OFFER", joined: false)
			try mustReject { _ = try chat.receive("PRIVMSG fixture :\u{01}\(answer)\u{01}", joined: false) }
		}
	}

	private static func interactiveChecks(mode: FixtureMode, peer: LoopbackPeer, client: Client) async throws {
		if mode.usesChannel {
			try await client.send("JOIN #e2e\r\n")
			try await wait(peer, "channel ready") { client.contains("E2E_CHANNEL_READY\r\n") }
		}
		if mode == .burstResponsiveness {
			try await client.send("PRIVMSG fixture :E2E_BURST_START\r\n")
			for index in 1 ... 3 {
				try await client.send("PRIVMSG fixture :E2E_BURST_SWITCH_\(index)\r\n")
				try await wait(peer, "switch \(index) acknowledged") { client.contains("E2E_BURST_SWITCH_\(index)_ACK\r\n") }
			}
			try await wait(peer, "burst complete") { client.contains("E2E_BURST_END\r\n") && peer.evidence.burstComplete }
			let text = String(data: client.received, encoding: .utf8) ?? ""
			guard text.components(separatedBy: "E2E_BURST_MESSAGE_").count - 1 == 5000
			else { throw HarnessFailure.assertion("Burst message count mismatch") }
			let names = text.components(separatedBy: "\r\n").filter { $0.contains(" 353 ") }
				.flatMap { $0.components(separatedBy: " :").last?.split(separator: " ").map(String.init) ?? [] }
				.filter { $0.hasPrefix("member") }
			guard names.count == 10000,
			      Set(names).count == 10000 else { throw HarnessFailure.assertion("Burst NAMES count mismatch") }
		} else if mode.dcc, let dcc = peer.dcc {
			if mode == .xdccRequest {
				try await client.send("PRIVMSG fixture :XDCC SEND #1\r\n")
				try await wait(peer, "XDCC offer held") { peer.evidence.offerHeld }
				guard client.contains("DCC SEND") == false else {
					throw HarnessFailure.assertion("The XDCC offer went out before it was released")
				}
				try peer.releaseHeldOffer()
			} else {
				try await client.send("PRIVMSG fixture :E2E_DCC_OFFER\r\n")
			}
			try await wait(peer, "DCC offer") { client.contains("DCC SEND \(dcc.filename) 2130706433") }
			guard let port = NWEndpoint.Port(rawValue: dcc.port) else {
				throw HarnessFailure.assertion("DCC fixture port missing")
			}
			let receiver = Client(port: port, tls: false, trust: false, maximumBytes: DCCFixturePeer.size + 1)
			receiver.start()
			defer { receiver.connection.cancel() }
			let expected = mode == .dccCancel ? DCCFixturePeer.partialSize : DCCFixturePeer.size
			try await wait(peer, "DCC bytes") { receiver.received.count == expected }
			guard receiver.received == DCCFixturePeer.bytes.prefix(expected)
			else { throw HarnessFailure.assertion("DCC fixture bytes mismatch") }
			var acknowledgement = UInt32(expected).bigEndian
			try await receiver.send(withUnsafeBytes(of: &acknowledgement) { Data($0) })
			receiver.connection.cancel()
			try await wait(peer, "DCC peer complete") { dcc.outcome != nil }
			try await client.send("PRIVMSG fixture :E2E_DCC_DONE\r\n")
		}
	}

	private static func snapshotChecks() throws {
		var snapshot: [String: Any] = ["format": "GlasstualConfiguration", "version": 1,
		                               "preferences": ["Connection -> Confirm Quit": true], "unset": [String](),
		                               "clients": [["connectionName": "E2E", "nickname": "e2euser",
		                                            "serverList": [["serverAddress": "127.0.0.1"]]]]]
		func encoded() throws -> Data {
			try PropertyListSerialization.data(
				fromPropertyList: snapshot,
				format: .xml,
				options: 0
			)
		}
		try ConfigurationSnapshotFixture.validate(encoded())
		snapshot["version"] = 2
		try mustReject { try ConfigurationSnapshotFixture.validate(encoded()) }
		snapshot["version"] = 1
		snapshot["preferences"] = ["Connection -> Confirm Quit": false]
		try mustReject { try ConfigurationSnapshotFixture.validate(encoded()) }
		snapshot["preferences"] = ["Connection -> Confirm Quit": true]
		snapshot["clients"] = [["connectionName": "private", "nickname": "private"]]
		try mustReject { try ConfigurationSnapshotFixture.validate(encoded()) }
	}

	private static func deniedJoinChecks() throws {
		var state = FixtureProtocol(reject: false, messaging: false, deniedJoin: DeniedJoinFixture())
		for line in FixtureProtocol.registration.compactMap(\.first) {
			_ = try state.receive(line)
		}
		_ = try state.receive("PONG E2E_PING")
		try mustReject { _ = try state.receive("JOIN #retry") }
		_ = try state.receive("JOIN #other")
		let denial = try state.receive("JOIN #retry")
		guard denial.first?.contains("477 e2euser #retry") == true
		else { throw HarnessFailure.assertion("Expected 477") }
		try mustReject { _ = try state.receive("JOIN #retry") }
		try mustReject { _ = try state.receive("PRIVMSG NickServ :IDENTIFY private") }
		_ = try state.receive("PRIVMSG NickServ :IDENTIFY E2E_SYNTHETIC")
		try mustReject { _ = try state.receive("JOIN #other") }
		try mustReject { _ = try state.receive("QUIT E2E_QUIT") }
		_ = try state.receive("JOIN #retry")
		try mustReject { _ = try state.receive("JOIN #retry") }
		_ = try state.receive("QUIT E2E_QUIT")
		try state.eof(pending: Data())
	}

	static func mustReject(_ operation: () throws -> Void) throws {
		do {
			try operation()
		} catch let HarnessFailure.assertion(message) {
			guard !message.contains("private")
			else { throw HarnessFailure.assertion("Fixture diagnostic leaked input") }
			return
		}
		throw HarnessFailure.assertion("Invalid fixture input was accepted")
	}

	final class Client {
		let connection: NWConnection
		let maximumBytes: Int
		var received = Data()
		var ended = false
		var sendFinished = false
		var sendFailed = false

		init(port: NWEndpoint.Port, tls: Bool, trust: Bool, maximumBytes: Int = 65536) {
			self.maximumBytes = maximumBytes
			let options = tls ? NWProtocolTLS.Options() : nil
			if let options {
				// Only the self-test client opts into this fixture decision, never the app.
				sec_protocol_options_set_verify_block(options.securityProtocolOptions, { @Sendable _, _, complete in
					complete(trust)
				}, .global())
			}
			connection = NWConnection(host: "127.0.0.1", port: port, using: NWParameters(tls: options))
		}

		func start() {
			connection.start(queue: .global())
			receive()
		}

		func contains(_ marker: String) -> Bool {
			received.range(of: Data(marker.utf8)) != nil
		}

		func receive() {
			connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, done, error in
				Task { @MainActor in
					guard let self else { return }
					if let data {
						self.received.append(data)
					}
					self.ended = done || error != nil || self.received.count > self.maximumBytes
					if !self.ended {
						self.receive()
					}
				}
			}
		}

		func send(_ text: String, final: Bool = false) async throws {
			try await send(Data(text.utf8), final: final)
		}

		func send(_ data: Data, final: Bool = false) async throws {
			sendFinished = false
			sendFailed = false
			connection.send(content: data, contentContext: final ? .finalMessage : .defaultMessage,
			                isComplete: true, completion: .contentProcessed { [weak self] error in
			                	Task { @MainActor in
			                		self?.sendFailed = error != nil
			                		self?.sendFinished = true
			                	}
			                })
			try await Wait.until("self-test send", timeout: .seconds(8)) { self.sendFinished }
			guard !sendFailed else { throw HarnessFailure.assertion("Self-test send failed") }
		}
	}
}
