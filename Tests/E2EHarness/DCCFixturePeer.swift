import CryptoKit
import Foundation
import Network
import Security

/// The harness's own cumulative-acknowledgement reader for the fixture receiver.
/// Named apart from the app's `DCCAcknowledgements`: this one validates what the
/// app under test sends, and the two must not be confused for each other.
struct FixtureACKParser {
	var pending = Data()
	var acknowledged: UInt32 = 0
	mutating func receive(_ data: Data, sent: UInt32) throws {
		pending.append(data)
		guard pending.count <= 4096 else { throw HarnessFailure.assertion("Oversized DCC acknowledgement input") }
		while pending.count >= 4 {
			let count = pending.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
			guard count >= acknowledged,
			      count <= sent else { throw HarnessFailure.assertion("Invalid cumulative DCC acknowledgement") }
			acknowledged = count
			pending.removeFirst(4)
		}
	}
}

/// What the DCC peer presents when the offer was a `DCC SSEND`.
struct DCCFixtureTLS {
	/// The identity the first connection presents.
	let identity: sec_identity_t
	/// The identity every later connection presents instead, for a peer whose
	/// certificate changed between two transfers.
	let rotated: sec_identity_t?

	/// `rotatesCertificate` makes the second connection present a different
	/// certificate from the first.
	init(corpora: URL, rotatesCertificate: Bool) throws {
		identity = try LoopbackPeer.identity(corpora: corpora)
		rotated = rotatesCertificate ? try LoopbackPeer.identity(corpora: corpora, named: "ClientChainTestIdentity") : nil
	}

	func identity(forConnection number: Int) -> sec_identity_t {
		number > 1 ? rotated ?? identity : identity
	}
}

/** The other end of a DCC SEND: it offers the fixture bytes and checks the
 application's cumulative acknowledgements.

 In chat mode it is the other end of a passive `DCC SCHAT` instead: once the
 application has let it in, it says one line, waits for the one line the
 scenario types back, and hangs up.

 It can offer several files one after another, each over a connection of its
 own. With ``DCCFixtureTLS`` it speaks TLS and presents a certificate, as the
 peer of a `DCC SSEND` does. A connection the application refuses over the peer's
 certificate ends with the outcome ``refused`` and nothing acknowledged. */
final class DCCFixturePeer {
	static let size = 100_003
	static let partialSize = 37003
	static let refused = "refused over the certificate"
	/// The line the peer says in a direct chat, the line it expects back, and
	/// how a chat that carried both ended.
	static let chatGreeting = "E2E_SCHAT_FROM_PEER"
	static let chatReply = "E2E_SCHAT_FROM_APP"
	static let chatted = "exchanged a line each way"
	static var bytes: Data {
		Data((0 ..< size).map { UInt8(truncatingIfNeeded: $0 * 31 + 7) })
	}

	static func hash(_ data: Data) -> String {
		SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
	}

	let cancel: Bool
	/// One name per file offered, in order.
	let filenames: [String]
	let tls: DCCFixtureTLS?
	/// Whether the peer chats instead of sending a file.
	let chat: Bool
	/// What the application has said in the chat so far.
	private var chatInput = Data()
	private var listener: NWListener?
	private var connection: NWConnection?
	private var acknowledgements = FixtureACKParser()
	private(set) var failure: Error?
	private(set) var port: UInt16 = 0
	/// Connections made so far, one per file.
	private(set) var connections = 0
	/// The byte count the application acknowledged in full on the current
	/// connection, once it has.
	private(set) var acknowledged: Int?
	/// How each transfer ended, from the peer's side, in order.
	private(set) var outcomes: [String] = []
	/// Whether the current connection completed its TLS handshake and sent.
	private var sending = false

	var filename: String {
		filenames[0]
	}

	/// How the latest transfer ended, once it has.
	var outcome: String? {
		outcomes.count == connections ? outcomes.last : nil
	}

	/// Whether every file was offered and its transfer ended.
	var complete: Bool {
		outcomes.count == filenames.count
	}

	init(cancel: Bool, transfers: Int = 1, tls: DCCFixtureTLS? = nil, chat: Bool = false) {
		self.cancel = cancel
		self.tls = tls
		self.chat = chat
		filenames = (0 ..< transfers).map { _ in "e2e-transfer-\(UUID().uuidString).bin" }
	}

	func start() async throws -> UInt16 {
		let parameters = NWParameters(tls: tlsOptions(forConnection: 1), tcp: NWProtocolTCP.Options())
		parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
		let listener = try NWListener(using: parameters)
		self.listener = listener
		listener.newConnectionHandler = { [weak self] connection in
			Task { @MainActor in self?.accept(connection) }
		}
		listener.start(queue: .global())
		try await Wait.until("DCC listener ready", timeout: .seconds(8)) { listener.state == .ready }
		guard let port = listener.port else { throw HarnessFailure.assertion("DCC listener has no port") }
		self.port = port.rawValue
		return port.rawValue
	}

	func stop() {
		connection?.cancel(); listener?.cancel()
	}

	/// TLS presenting the identity for connection `number`, accepting whatever
	/// the application presents: its certificate is its own, made for DCC.
	private func tlsOptions(forConnection number: Int) -> NWProtocolTLS.Options? {
		guard let tls else { return nil }
		let options = NWProtocolTLS.Options()
		sec_protocol_options_set_local_identity(options.securityProtocolOptions, tls.identity(forConnection: number))
		sec_protocol_options_set_verify_block(options.securityProtocolOptions, { @Sendable _, _, complete in
			complete(true)
		}, .global())
		return options
	}

	/// Passive DCC makes the application listen, so the synthetic peer dials
	/// the port returned over IRC instead of asking the application to dial a
	/// peer-supplied loopback address.
	func connect(to port: UInt16) {
		guard connections == outcomes.count, connections < filenames.count, let port = NWEndpoint.Port(rawValue: port) else {
			failure = HarnessFailure.assertion("Unexpected passive DCC listener")
			return
		}
		begin()
		let parameters = NWParameters(tls: tlsOptions(forConnection: connections), tcp: NWProtocolTCP.Options())
		let peer = NWConnection(host: "127.0.0.1", port: port, using: parameters)
		connection = peer
		peer.stateUpdateHandler = { [weak self] state in
			Task { @MainActor in
				guard let self, self.connection === peer else { return }
				switch state {
				case .ready:
					if self.chat {
						self.startChat(on: peer)
					} else {
						self.sendPayload(on: peer)
					}
				case .waiting where self.tls == nil:
					break
				case .failed, .waiting:
					/* The application ends a handshake whose certificate its user
					 refused. That is an outcome only where TLS was asked for and
					 nothing had been sent. */
					if self.sending == false {
						if self.tls != nil {
							self.outcomes.append(Self.refused)
						} else {
							self.failure = HarnessFailure.assertion("Passive DCC fixture connection failed")
						}
						peer.cancel()
					}
				// Once bytes are going out, the read decides how the transfer ended.
				default:
					break
				}
			}
		}
		peer.start(queue: .global())
	}

	private func begin() {
		connections += 1
		acknowledgements = FixtureACKParser()
		acknowledged = nil
		sending = false
		chatInput = Data()
	}

	private func accept(_ peer: NWConnection) {
		// The application refuses to dial loopback for a chat, so a chat is passive.
		guard chat == false, connections == outcomes.count, connections < filenames.count else {
			peer.cancel()
			failure = HarnessFailure.assertion("Unexpected second DCC receiver")
			return
		}
		begin()
		connection = peer
		peer.start(queue: .global())
		sendPayload(on: peer)
	}

	private func sendPayload(on peer: NWConnection) {
		sending = true
		let payload = Self.bytes.prefix(cancel ? Self.partialSize : Self.size)
		peer.send(content: payload, completion: .contentProcessed { [weak self] error in
			Task { @MainActor in
				// A refused certificate fails the send too; the read reports that.
				if error != nil, self?.tls == nil {
					self?.failure = HarnessFailure.assertion("DCC fixture send failed")
				}
			}
		})
		receive(peer)
	}

	/// Says the peer's line and waits for the application's.
	private func startChat(on peer: NWConnection) {
		sending = true
		peer.send(content: Data((Self.chatGreeting + "\n").utf8), completion: .contentProcessed { _ in })
		receiveChat(peer)
	}

	/** Reads the chat until the application's line is whole, then hangs up.

	 Anything but that one line fails the peer, and so does a chat that ends
	 before it. A connection the application refused over the certificate
	 fails its first read with nothing received, as a transfer's does. */
	private func receiveChat(_ peer: NWConnection) {
		peer.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, done, error in
			Task { @MainActor in
				guard let self, self.connection === peer, self.outcomes.count < self.connections else { return }
				self.chatInput.append(data ?? Data())
				if let end = self.chatInput.firstIndex(of: 0x0A) {
					// The application ends a line with CR LF; a bare LF is as good.
					let line = self.chatInput[..<end]
					let text = line.last == 0x0D ? line.dropLast() : line
					if Data(text) == Data(Self.chatReply.utf8), end == self.chatInput.index(before: self.chatInput.endIndex) {
						self.outcomes.append(Self.chatted)
					} else {
						self.failure = HarnessFailure.assertion("Unexpected direct chat line; payload withheld")
					}
					peer.cancel()
				} else if done || error != nil || self.chatInput.count > 512 {
					if self.tls != nil, error != nil, self.chatInput.isEmpty {
						self.outcomes.append(Self.refused)
					} else {
						self.failure = HarnessFailure.assertion("The direct chat ended before the application's line")
					}
					peer.cancel()
				} else {
					self.receiveChat(peer)
				}
			}
		}
	}

	private func receive(_ peer: NWConnection) {
		peer.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, done, error in
			Task { @MainActor in
				guard let self, self.connection === peer, self.outcomes.count < self.connections else { return }
				do {
					let expected = self.cancel ? Self.partialSize : Self.size
					if let data {
						try self.acknowledgements.receive(data, sent: UInt32(expected))
					}
					if self.acknowledgements.acknowledged == expected {
						self.acknowledged = expected
						/* A TLS close is not reliably seen as an end of stream, so
						 the sender of a secure transfer ends it once every byte is
						 acknowledged. */
						if self.tls != nil, self.acknowledgements.pending.isEmpty {
							self.outcomes.append("completed 100003 bytes")
							peer.cancel()
							return
						}
					}
					if done || error != nil {
						/* TLS 1.3 lets a client send before the server has judged its
						 certificate, so a refusal arrives as an error on the first read. */
						if self.tls != nil, error != nil, self.acknowledgements.acknowledged == 0, self.acknowledgements.pending.isEmpty {
							self.outcomes.append(Self.refused)
							peer.cancel()
							return
						}
						guard self.acknowledgements.acknowledged == expected, self.acknowledgements.pending.isEmpty,
						      self.cancel || error == nil || self.tls != nil
						else { throw HarnessFailure.assertion("DCC closed before expected bytes/ACK") }
						self.outcomes.append(self.cancel ? "cancelled after 37003 bytes" : "completed 100003 bytes")
						peer.cancel()
					} else {
						self.receive(peer)
					}
				} catch { self.failure = error }
			}
		}
	}
}
