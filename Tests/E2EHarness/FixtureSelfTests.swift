import Foundation
import Network
import Security

/// Safe without a GUI account: synthetic clients talk only to this helper's loopback listener.
@MainActor
enum FixtureSelfTests {
	/// One monotonic bound for the whole fixture run, so `make e2e-fixtures` needs
	/// no external `timeout` command to stop a mode that stops making progress.
	private static var runDeadline = Double.infinity

	static func run() async throws {
		runDeadline = HarnessFiles.now + 90
		try protocolChecks()
		let kind = try ScenarioKind.current
		guard kind.hasFixtureTest else { throw HarnessFailure.setup("This scenario has no network fixture self-test") }
		let peer = try LoopbackPeer(kind: kind)
		let task = Task { try await peer.run() }
		defer { task.cancel() }
		try await wait { try HarnessFiles.exists("port") }
		guard let rawPort = try UInt16(HarnessFiles.read("port")), let port = NWEndpoint.Port(rawValue: rawPort) else {
			throw HarnessFailure.assertion("Self-test port missing")
		}
		let attempts = kind == .tlsRejectRetry ? 2 : kind.rejectionCount + 1
		for attempt in 1 ... attempts {
			let rejectTLS = kind == .tlsRejectRetry && attempt == 1
			let client = Client(
				port: port,
				tls: kind.secured,
				trust: !rejectTLS,
				maximumBytes: kind == .burstResponsiveness ? 2 * 1024 * 1024 : 65536
			)
			defer { client.connection.cancel() }
			client.start()
			if kind == .tlsStall {
				try await wait { try HarnessFiles.exists("tls-stalled") }
				try await Task.sleep(for: .milliseconds(200))
				guard client.received.isEmpty else { throw HarnessFailure.assertion("Stall emitted bytes") }
				client.connection.cancel()
				break
			}
			if rejectTLS {
				try await wait { try HarnessFiles.exists("tls-rejected") }
				guard client.received.isEmpty else { throw HarnessFailure.assertion("Rejected TLS emitted IRC") }
				continue
			}
			try await wait { client.connection.state == .ready }
			// Exercise line framing across writes as well as several commands in one write.
			try await client.send("CAP LS ")
			try await client.send("302\r\n")
			try await wait { client.contains(":e2e.local CAP * LS :\r\n") }
			try await client.send("NICK e2euser\r\nUSER e2euser 0 * :Synthetic E2E User\r\nCAP END\r\n")
			if attempt <= kind.rejectionCount {
				try await wait { client.contains("ERROR :E2E_REGISTRATION_REJECTED\r\n") && client.ended }
				continue
			}
			try await wait { client.contains("E2E_TRANSCRIPT_READY\r\n") }
			try await client.send("PONG E2E_PING\r\n")
			if kind.messaging {
				try await client.send("JOIN #e2e\r\n")
				try await wait { client.contains("E2E_CHANNEL_READY\r\n") }
				try await client.send("PRIVMSG #e2e :E2E_TYPED_MESSAGE\r\n")
				try await wait { client.contains("E2E_SERVER_REPLY\r\n") }
				try await client.send("PRIVMSG #e2e :fixture: E2E_TYPED_REPLY\r\n")
				try await wait { client.contains("E2E_REPLY_ACK\r\n") }
			}
			if kind == .channelDenied {
				try await client.send("JOIN #other\r\n")
				try await wait { client.contains("E2E_OTHER_READY\r\n") }
				try await client.send("JOIN #retry\r\n")
				try await wait { client.contains("477 e2euser #retry :E2E_JOIN_DENIED") }
				try await client.send("PRIVMSG NickServ :IDENTIFY E2E_SYNTHETIC\r\n")
				try await wait { client.contains("E2E_IDENTIFIED_READY\r\n") }
				guard client.contains("900 e2euser"), client.contains("ACCOUNT e2eaccount"),
				      client.contains("MODE e2euser :+r")
				else {
					throw HarnessFailure.assertion("Fixture identification signals missing")
				}
				try await client.send("JOIN #retry\r\n")
				try await wait { client.contains("E2E_RETRY_JOINED\r\n") }
			}
			if kind.interactive {
				try await interactiveChecks(kind: kind, client: client)
			}
			try await client.send("QUIT E2E_QUIT\r\n", final: true)
			try await wait { try HarnessFiles.exists("quit-wire") }
			client.connection.cancel()
		}
		// Every path out of the loop ends here, including the TLS stall break and
		// the rejection continues, so one wait covers the peer's observed exit.
		try await wait { try HarnessFiles.exists("peer-complete") }
		try await task.value
		try HarnessFiles.write("protocol and local network assertions passed", to: "fixture-selftests-passed")
	}

	private static func protocolChecks() throws {
		let sample = ProcessDiagnostics.summary(Data("""
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
		var smiley = InteractiveFixture(kind: .pluginSmiley)
		try mustReject { _ = try smiley.receive("PRIVMSG fixture :E2E_SMILEY_OFF", joined: false) }
		try mustReject { _ = try smiley.receive("PRIVMSG fixture :E2E_SMILEY_ON", joined: true) }
		for token in ["E2E_SMILEY_OFF", "E2E_SMILEY_ON", "E2E_SMILEY_OFF_AGAIN"] {
			_ = try smiley.receive("PRIVMSG fixture :" + token, joined: true)
		}
		guard smiley.finished else { throw HarnessFailure.assertion("Smiley fixture never finished") }
		try mustReject { _ = try smiley.receive("PRIVMSG fixture :E2E_SMILEY_OFF_AGAIN", joined: true) }
		var burst = InteractiveFixture(kind: .burstResponsiveness)
		try mustReject { _ = try burst.receive("PRIVMSG fixture :E2E_BURST_SWITCH_1", joined: true) }
		_ = try burst.receive("PRIVMSG fixture :E2E_BURST_START", joined: true)
		try mustReject { _ = try burst.receive("PRIVMSG fixture :E2E_BURST_SWITCH_2", joined: true) }
	}

	private static func interactiveChecks(kind: ScenarioKind, client: Client) async throws {
		if kind.usesChannel {
			try await client.send("JOIN #e2e\r\n")
			try await wait { client.contains("E2E_CHANNEL_READY\r\n") }
		}
		if kind == .pluginSmiley {
			for marker in ["E2E_SMILEY_OFF", "E2E_SMILEY_ON", "E2E_SMILEY_OFF_AGAIN"] {
				try await client.send("PRIVMSG fixture :\(marker)\r\n")
				try await wait { client.contains(marker + " :-)\r\n") }
			}
		} else if kind == .burstResponsiveness {
			try await client.send("PRIVMSG fixture :E2E_BURST_START\r\n")
			for index in 1 ... 3 {
				try await client.send("PRIVMSG fixture :E2E_BURST_SWITCH_\(index)\r\n")
				try await wait { client.contains("E2E_BURST_SWITCH_\(index)_ACK\r\n") }
			}
			try await wait(seconds: 20) {
				try client.contains("E2E_BURST_END\r\n") && (HarnessFiles.exists("burst-complete"))
			}
			let text = String(data: client.received, encoding: .utf8) ?? ""
			guard text.components(separatedBy: "E2E_BURST_MESSAGE_").count - 1 == 5000
			else { throw HarnessFailure.assertion("Burst message count mismatch") }
			let names = text.components(separatedBy: "\r\n").filter { $0.contains(" 353 ") }
				.flatMap { $0.components(separatedBy: " :").last?.split(separator: " ").map(String.init) ?? [] }
				.filter { $0.hasPrefix("member") }
			guard names.count == 10000,
			      Set(names).count == 10000 else { throw HarnessFailure.assertion("Burst NAMES count mismatch") }
		} else if kind.dcc {
			try await client.send("PRIVMSG fixture :E2E_DCC_OFFER\r\n")
			try await wait { client.contains("DCC SEND e2e-transfer.bin 2130706433") }
			guard let raw = try UInt16(HarnessFiles.read("dcc-port")),
			      let port = NWEndpoint.Port(rawValue: raw)
			else { throw HarnessFailure.assertion("DCC fixture port missing") }
			let receiver = Client(port: port, tls: false, trust: false, maximumBytes: DCCFixturePeer.size + 1)
			receiver.start()
			defer { receiver.connection.cancel() }
			let expected = kind == .dccCancel ? DCCFixturePeer.partialSize : DCCFixturePeer.size
			try await wait { receiver.received.count == expected }
			guard receiver.received == DCCFixturePeer.bytes.prefix(expected)
			else { throw HarnessFailure.assertion("DCC fixture bytes mismatch") }
			var acknowledgement = UInt32(expected).bigEndian
			try await receiver.send(withUnsafeBytes(of: &acknowledgement) { Data($0) })
			receiver.connection.cancel()
			try await wait { try HarnessFiles.exists("dcc-peer-complete") }
			try await client.send("PRIVMSG fixture :E2E_DCC_DONE\r\n")
		}
	}

	private static func snapshotChecks() throws {
		var snapshot: [String: Any] = ["format": "GlasstualConfiguration", "version": 1,
		                               "preferences": ["ConfirmApplicationQuit": true], "unset": [String](),
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
		snapshot["preferences"] = ["ConfirmApplicationQuit": false]
		try mustReject { try ConfigurationSnapshotFixture.validate(encoded()) }
		snapshot["preferences"] = ["ConfirmApplicationQuit": true]
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

	private static func mustReject(_ operation: () throws -> Void) throws {
		do {
			try operation()
		} catch let HarnessFailure.assertion(message) {
			guard !message.contains("private")
			else { throw HarnessFailure.assertion("Fixture diagnostic leaked input") }
			return
		}
		throw HarnessFailure.assertion("Invalid fixture input was accepted")
	}

	private static func wait(seconds: Double = 8, _ condition: () throws -> Bool) async throws {
		let deadline = min(HarnessFiles.now + seconds, runDeadline)
		while try !condition() {
			try HarnessFiles.check(deadline)
			try await Task.sleep(for: .milliseconds(25))
		}
	}

	private final class Client {
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
			try await FixtureSelfTests.wait { self.sendFinished }
			guard !sendFailed else { throw HarnessFailure.assertion("Self-test send failed") }
		}
	}
}
