import CryptoKit
import Foundation
import Network
import Security
import Synchronization

/// The self-tests of the WebSocket transport, the scripted fixtures and the
/// TLS DCC peer: a synthetic client doing what the application does.
enum FixtureExtensionChecks {
	typealias Client = FixtureSelfTests.Client

	// MARK: - WebSocket

	/// `channelMessaging` in WebSocket text messages, from the upgrade to the
	/// closing handshake.
	static func webSocket(peer: LoopbackPeer, client: Client) async throws {
		let key = Data((0 ..< 16).map { _ in UInt8.random(in: .min ... .max) }).base64EncodedString()
		let request = [
			"GET \(WebSocketFixture.path) HTTP/1.1", "Host: 127.0.0.1:\(peer.port)", "Upgrade: websocket",
			"Connection: Upgrade", "Sec-WebSocket-Key: \(key)", "Sec-WebSocket-Version: 13",
			"Sec-WebSocket-Protocol: text.ircv3.net, binary.ircv3.net",
		]
		try await client.send(request.joined(separator: "\r\n") + "\r\n\r\n")
		try await FixtureSelfTests.wait(peer, "upgrade accepted") {
			client.contains("Sec-WebSocket-Accept: \(WebSocketFixture.acceptValue(forKey: key))\r\n")
				&& client.contains("Sec-WebSocket-Protocol: text.ircv3.net\r\n\r\n")
		}
		// Several frames in one write, and one frame across two.
		try await client.send(maskedFrame("CAP LS 302") + maskedFrame("NICK e2euser"))
		let user = maskedFrame("USER e2euser 0 * :Synthetic E2E User")
		try await client.send(user.prefix(5))
		try await client.send(user.dropFirst(5) + maskedFrame("CAP END"))
		try await FixtureSelfTests.wait(peer, "welcome") { client.contains("E2E_TRANSCRIPT_READY") }
		guard client.contains("E2E_TRANSCRIPT_READY\r\n") == false else {
			throw HarnessFailure.assertion("A WebSocket message carried a line terminator")
		}
		for (line, answer) in [
			("PONG E2E_PING", nil), ("JOIN #e2e", "E2E_CHANNEL_READY"),
			("PRIVMSG #e2e :E2E_TYPED_MESSAGE", "E2E_SERVER_REPLY"),
			("PRIVMSG #e2e :fixture: E2E_TYPED_REPLY", "E2E_REPLY_ACK"), ("QUIT E2E_QUIT", nil),
		] {
			try await client.send(maskedFrame(line))
			if let answer {
				try await FixtureSelfTests.wait(peer, "answer to \(answer)") { client.contains(answer) }
			}
		}
		try await FixtureSelfTests.wait(peer, "peer saw QUIT") { peer.evidence.quitSeen }
		let before = client.received.count
		try await client.send(maskedFrame(Data([0x03, 0xE8]), opcode: 0x8), final: true)
		try await FixtureSelfTests.wait(peer, "close answered") {
			client.received.count == before + 4 && client.received.suffix(4) == Data([0x88, 0x02, 0x03, 0xE8])
		}
	}

	private static func maskedFrame(_ line: String) -> Data {
		maskedFrame(Data(line.utf8), opcode: 0x1)
	}

	private static func maskedFrame(_ payload: Data, opcode: UInt8) -> Data {
		precondition(payload.count < 126)
		let mask = (0 ..< 4).map { _ in UInt8.random(in: .min ... .max) }
		return Data([0x80 | opcode, 0x80 | UInt8(payload.count)] + mask)
			+ Data(payload.enumerated().map { $1 ^ mask[$0 % 4] })
	}

	// MARK: - Scripted fixtures

	private static func send(_ line: String, to client: Client, peer: LoopbackPeer, expecting marker: String?) async throws {
		try await client.send(line + "\r\n")
		if let marker {
			try await FixtureSelfTests.wait(peer, "answer \(marker)") { client.contains(marker) }
		}
	}

	/// Registration the way the application negotiates it: dependencies
	/// first, each request acknowledged before the next.
	static func register(_ mode: FixtureMode, peer: LoopbackPeer, client: Client) async throws {
		let requests: [String] = switch mode {
		case .accountRegistration: ["draft/account-registration"]
		case .metadataEdit: ["batch", "draft/metadata-2"]
		case .saslSignInAgain: ["sasl"]
		case .replyPrivately: ["message-tags"]
		default: ["batch server-time message-tags", "draft/chathistory"]
		}
		try await send("CAP LS 302", to: client, peer: peer, expecting: ":e2e.local CAP * LS :")
		try await client.send("NICK e2euser\r\nUSER e2euser 0 * :Synthetic E2E User\r\n")
		for request in requests {
			try await send("CAP REQ :\(request)", to: client, peer: peer, expecting: "ACK :\(request)\r\n")
		}
		if mode == .saslSignInAgain {
			try await send("AUTHENTICATE PLAIN", to: client, peer: peer, expecting: "AUTHENTICATE +\r\n")
			try await send("AUTHENTICATE \(SASLConsentFixture.expectedPayload)", to: client, peer: peer,
			               expecting: " 904 e2euser ")
		}
		try await client.send("CAP END\r\n")
	}

	/// What the scenario makes the application send, once registered.
	static func exchange(_ mode: FixtureMode, peer: LoopbackPeer, client: Client) async throws {
		let steps: [(String, String?)]
		switch mode {
		case .accountRegistration:
			let fixture = AccountRegistrationFixture.self
			steps = [
				("REGISTER \(fixture.account) \(fixture.email) \(fixture.password)", "REGISTER VERIFICATION_REQUIRED"),
				("VERIFY \(fixture.account) \(fixture.code)", "VERIFY SUCCESS \(fixture.account)"),
			]
		case .metadataEdit:
			steps = [
				("METADATA * SUB display-name avatar color", " 770 e2euser display-name avatar color\r\n"),
				("JOIN #e2e", "E2E_CHANNEL_READY\r\n"),
				("METADATA #e2e SYNC", "BATCH -e2emeta1\r\n"),
				("METADATA * SET display-name :\(MetadataFixture.displayName)", " 761 e2euser e2euser display-name * :"),
				("METADATA * SYNC", "METADATA e2euser display-name * :\(MetadataFixture.displayName)\r\n"),
			]
		case .saslSignInAgain:
			steps = [
				("AUTHENTICATE PLAIN", nil),
				("AUTHENTICATE \(SASLConsentFixture.expectedPayload)", " 903 e2euser "),
			]
		case .replyPrivately:
			steps = [
				("JOIN #e2e", "@msgid=e2e-original :fixture!fixture@localhost PRIVMSG #e2e :E2E_ORIGINAL_MESSAGE\r\n"),
				("@+draft/reply=e2e-original;+draft/channel-context=#e2e PRIVMSG fixture :E2E_PRIVATE_REPLY",
				 "@+draft/channel-context=#e2e;msgid=e2e-private-ack :fixture!fixture@localhost PRIVMSG e2euser :E2E_PRIVATE_ACK\r\n"),
			]
		case .historyGapBanner:
			let forward = (0 ..< 10).map { page in
				("CHATHISTORY AFTER #e2e msgid=e2e-\(page * 2 + 1) 2", Optional("E2E_HISTORY_\(page * 2 + 3)_\r\n"))
			}
			steps = [("JOIN #e2e", " 366 "), ("CHATHISTORY LATEST #e2e * 2", "E2E_HISTORY_1_\r\n"), ("PART #e2e", " PART #e2e\r\n"),
			         ("JOIN #e2e", nil)] + forward + [
				("CHATHISTORY LATEST #e2e * 2", "E2E_HISTORY_29_\r\n"),
				("CHATHISTORY BETWEEN #e2e msgid=e2e-21 msgid=e2e-28 2", "E2E_HISTORY_23_\r\n"),
				("CHATHISTORY BETWEEN #e2e msgid=e2e-23 msgid=e2e-28 2", "E2E_HISTORY_25_\r\n"),
				("CHATHISTORY BETWEEN #e2e msgid=e2e-25 msgid=e2e-28 2", "E2E_HISTORY_27_\r\n"),
				(
					"CHATHISTORY BETWEEN #e2e msgid=e2e-27 msgid=e2e-28 2",
					"BATCH +e2ehistory16 chathistory #e2e\r\n:e2e.local BATCH -e2ehistory16\r\n"
				),
			]
		case .showOriginalMessage:
			steps = [
				("JOIN #e2e", " 366 "),
				(
					"CHATHISTORY LATEST #e2e * 50",
					"+draft/reply=e2e-original :fixture!fixture@localhost PRIVMSG #e2e :E2E_REPLY_MESSAGE\r\n"
				),
				(
					"@label=e2e-label CHATHISTORY AROUND #e2e msgid=e2e-original 50",
					"@label=e2e-label :e2e.local BATCH +e2ehistory2 chathistory #e2e\r\n"
				),
			]
		default:
			steps = []
		}
		for (line, marker) in steps {
			try await send(line, to: client, peer: peer, expecting: marker)
		}
		if mode == .showOriginalMessage {
			guard client.contains("E2E_CONTEXT_BEFORE\r\n"), client.contains("PRIVMSG #e2e :E2E_ORIGINAL_MESSAGE\r\n"),
			      client.contains("E2E_CONTEXT_AFTER\r\n")
			else { throw HarnessFailure.assertion("AROUND did not return the message and its neighbours") }
		}
	}

	/// What a scripted fixture must refuse, without a connection.
	static func protocolChecks() throws {
		func registered<Fixture: ScriptedFixture>(_ fixture: Fixture, requesting requests: [String]) throws -> Fixture {
			var fixture = fixture
			for line in ["CAP LS 302", "NICK e2euser", "USER e2euser 0 * :Synthetic E2E User"] + requests.map({ "CAP REQ :" + $0 }) {
				_ = try fixture.register(line)
			}
			return fixture
		}
		let mustReject = FixtureSelfTests.mustReject

		var unoffered = AccountRegistrationFixture()
		_ = try unoffered.register("CAP LS 302")
		try mustReject { _ = try unoffered.register("CAP REQ :sasl") }
		var unrequested = try registered(AccountRegistrationFixture(), requesting: [])
		try mustReject { _ = try unrequested.register("CAP END") }
		var account = try registered(AccountRegistrationFixture(), requesting: ["draft/account-registration"])
		_ = try account.register("CAP END")
		try mustReject { _ = try account.receive(ClientLine("VERIFY e2eaccount E2E-CODE-4242"), pongSeen: true) }
		try mustReject { _ = try account.receive(ClientLine("REGISTER * * private"), pongSeen: true) }
		try mustReject {
			_ = try account.receive(ClientLine("PRIVMSG x :" + AccountRegistrationFixture.password), pongSeen: true)
		}

		var sasl = try registered(SASLSignInFixture(), requesting: ["sasl"])
		var scram = sasl
		try mustReject { _ = try scram.register("AUTHENTICATE SCRAM-SHA-256") }
		_ = try sasl.register("AUTHENTICATE PLAIN")
		try mustReject { _ = try sasl.register("AUTHENTICATE cHJpdmF0ZQ==") }

		var reply = try registered(PrivateReplyFixture(), requesting: ["message-tags"])
		_ = try reply.register("CAP END")
		_ = try reply.receive(ClientLine("JOIN #e2e"), pongSeen: true)
		try mustReject { _ = try reply.receive(ClientLine("PRIVMSG fixture :E2E_PRIVATE_REPLY"), pongSeen: true) }
		let typing = ClientLine("@+typing=active TAGMSG #e2e")
		guard typing.isTypingNotification, ClientLine("@+draft/react=x TAGMSG #e2e").isTypingNotification == false else {
			throw HarnessFailure.assertion("Typing notification self-test failed")
		}

		var history = try registered(HistoryFixture(.gap), requesting: ["batch server-time message-tags", "draft/chathistory"])
		_ = try history.register("CAP END")
		try mustReject { _ = try history.receive(ClientLine("CHATHISTORY LATEST #e2e * 2"), pongSeen: true) }
		_ = try history.receive(ClientLine("JOIN #e2e"), pongSeen: true)
		try mustReject { _ = try history.receive(ClientLine("CHATHISTORY AFTER #e2e msgid=private 2"), pongSeen: true) }
		try mustReject { _ = try history.receive(ClientLine("CHATHISTORY AROUND #e2e msgid=e2e-1 2"), pongSeen: true) }
	}

	// MARK: - TLS DCC

	/// The certificates a TLS listener was shown. The handshake asks on a
	/// queue of its own and needs its answer there, so the list is guarded.
	private final nonisolated class CertificateLog: Sendable { // nonisolated: guarded
		private let seen = Mutex<[String]>([])

		var digests: [String] {
			seen.withLock { $0 }
		}

		/// Records `digest` and reports whether every certificate so far is it.
		func admit(_ digest: String) -> Bool {
			seen.withLock {
				$0.append(digest)
				return $0.allSatisfy { $0 == digest }
			}
		}
	}

	/** The receiver's side of a passive `DCC SSEND`: it listens with TLS, asks
	 the fixture for its certificate, and refuses a connection whose
	 certificate differs from the first one it saw, as the application does
	 when its user declines. */
	private final class SecureReceiver {
		let listener: NWListener
		var connection: NWConnection?
		var received = Data()
		private let log = CertificateLog()
		var closed = false

		/// The certificates presented so far, one digest per handshake.
		var certificates: [String] {
			log.digests
		}

		init(corpora: URL) throws {
			let options = NWProtocolTLS.Options()
			try sec_protocol_options_set_local_identity(options.securityProtocolOptions, LoopbackPeer.identity(corpora: corpora))
			sec_protocol_options_set_peer_authentication_required(options.securityProtocolOptions, true)
			let log = log
			sec_protocol_options_set_verify_block(options.securityProtocolOptions, { @Sendable _, trust, complete in
				let chain = SecTrustCopyCertificateChain(sec_trust_copy_ref(trust).takeRetainedValue()) as? [SecCertificate]
				guard let leaf = chain?.first else { return complete(false) }
				complete(log.admit(SHA256.hash(data: SecCertificateCopyData(leaf) as Data).description))
			}, .global())
			let parameters = NWParameters(tls: options, tcp: NWProtocolTCP.Options())
			parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
			listener = try NWListener(using: parameters)
			listener.newConnectionHandler = { [weak self] connection in
				Task { @MainActor in self?.accept(connection) }
			}
			listener.start(queue: .main)
		}

		private func accept(_ peer: NWConnection) {
			connection = peer
			received = Data()
			closed = false
			peer.start(queue: .main)
			receive(peer)
		}

		private func receive(_ peer: NWConnection) {
			peer.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, error in
				Task { @MainActor in
					guard let self, self.connection === peer else { return }
					if let data {
						self.received.append(data)
					}
					if done || error != nil {
						self.closed = true
					} else {
						self.receive(peer)
					}
				}
			}
		}

		func say(_ line: String) {
			connection?.send(content: Data((line + "\n").utf8), completion: .idempotent)
		}

		func acknowledge(_ count: Int) {
			var value = UInt32(count).bigEndian
			// The final message closes this side once the acknowledgement is out.
			connection?.send(content: withUnsafeBytes(of: &value) { Data($0) }, contentContext: .finalMessage,
			                 isComplete: true, completion: .idempotent)
		}
	}

	static func secureDCC(_ mode: FixtureMode, peer: LoopbackPeer, client: Client, corpora: URL) async throws {
		guard mode.directChat == false else {
			return try await secureChat(peer: peer, client: client, corpora: corpora)
		}
		guard let dcc = peer.dcc else { throw HarnessFailure.assertion("The TLS DCC peer did not start") }
		let receiver = try SecureReceiver(corpora: corpora)
		defer {
			receiver.connection?.cancel()
			receiver.listener.cancel()
		}
		try await FixtureSelfTests.wait(peer, "TLS receiver ready") { receiver.listener.state == .ready }
		guard let port = receiver.listener.port?.rawValue else { throw HarnessFailure.assertion("TLS receiver has no port") }
		for (index, filename) in dcc.filenames.enumerated() {
			let token = "42424\(index + 1)"
			try await send("PRIVMSG fixture :\(index == 0 ? "E2E_DCC_OFFER" : "E2E_DCC_OFFER_AGAIN")", to: client, peer: peer,
			               expecting: "\u{01}DCC SSEND \(filename) 2130706433 0 100003 \(token)\u{01}\r\n")
			try await client.send("PRIVMSG fixture :\u{01}DCC SSEND \(filename) 2130706433 \(port) 100003 \(token)\u{01}\r\n")
			if index == 0 {
				try await FixtureSelfTests.wait(peer, "TLS DCC bytes") { receiver.received.count == DCCFixturePeer.size }
				guard receiver.received == DCCFixturePeer.bytes else { throw HarnessFailure.assertion("TLS DCC bytes mismatch") }
				receiver.acknowledge(DCCFixturePeer.size)
			}
			try await FixtureSelfTests.wait(peer, "TLS DCC transfer \(index + 1) ended") { dcc.outcomes.count == index + 1 }
		}
		let expected = mode == .dccSecureChanged ? ["completed 100003 bytes", DCCFixturePeer.refused] : ["completed 100003 bytes"]
		guard dcc.outcomes == expected, receiver.certificates.count == expected.count,
		      Set(receiver.certificates).count == expected.count
		else { throw HarnessFailure.assertion("The TLS DCC peer did not present the certificates the mode calls for") }
		try await client.send("PRIVMSG fixture :E2E_DCC_DONE\r\n")
	}

	/// The application's side of a passive `DCC SCHAT`: it listens with TLS,
	/// hears the peer's line, says its own, and the peer hangs up.
	private static func secureChat(peer: LoopbackPeer, client: Client, corpora: URL) async throws {
		guard let dcc = peer.dcc else { throw HarnessFailure.assertion("The TLS DCC peer did not start") }
		let receiver = try SecureReceiver(corpora: corpora)
		defer {
			receiver.connection?.cancel()
			receiver.listener.cancel()
		}
		try await FixtureSelfTests.wait(peer, "TLS chat listener ready") { receiver.listener.state == .ready }
		guard let port = receiver.listener.port?.rawValue else { throw HarnessFailure.assertion("TLS chat listener has no port") }
		try await send("PRIVMSG fixture :E2E_DCC_OFFER", to: client, peer: peer,
		               expecting: "\u{01}DCC SCHAT CHAT 2130706433 0 424241\u{01}\r\n")
		try await client.send("PRIVMSG fixture :\u{01}DCC SCHAT chat 2130706433 \(port) 424241\u{01}\r\n")
		try await FixtureSelfTests.wait(peer, "the peer's chat line") {
			receiver.received == Data((DCCFixturePeer.chatGreeting + "\n").utf8)
		}
		guard dcc.outcome == nil else { throw HarnessFailure.assertion("The chat ended before the application's line") }
		receiver.say(DCCFixturePeer.chatReply)
		try await FixtureSelfTests.wait(peer, "the peer hung up") { dcc.outcome != nil }
		guard dcc.outcomes == [DCCFixturePeer.chatted], receiver.certificates.count == 1
		else { throw HarnessFailure.assertion("The TLS chat did not carry a line each way under one certificate") }
		try await client.send("PRIVMSG fixture :E2E_DCC_DONE\r\n")
	}
}
