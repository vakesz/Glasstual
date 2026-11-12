import CryptoKit
import Foundation
import Network

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

/// The other end of a DCC SEND: it offers the fixture bytes and checks the
/// application's cumulative acknowledgements.
final class DCCFixturePeer {
	static let size = 100_003
	static let partialSize = 37003
	static var bytes: Data {
		Data((0 ..< size).map { UInt8(truncatingIfNeeded: $0 * 31 + 7) })
	}

	static func hash(_ data: Data) -> String {
		SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
	}

	let cancel: Bool
	let filename: String
	private var listener: NWListener?
	private var connection: NWConnection?
	private var acknowledgements = FixtureACKParser()
	private(set) var complete = false
	private(set) var failure: Error?
	private(set) var port: UInt16 = 0
	/// The byte count the application acknowledged in full, once it has.
	private(set) var acknowledged: Int?
	/// How the transfer ended, from the peer's side.
	private(set) var outcome: String?

	init(cancel: Bool, filename: String = "e2e-transfer-\(UUID().uuidString).bin") {
		self.cancel = cancel
		self.filename = filename
	}

	func start() async throws -> UInt16 {
		let parameters = NWParameters.tcp
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

	/// Passive DCC makes the application listen, so the synthetic peer dials
	/// the port returned over IRC instead of asking the application to dial a
	/// peer-supplied loopback address.
	func connect(to port: UInt16) {
		guard connection == nil, let port = NWEndpoint.Port(rawValue: port) else { return }
		let peer = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
		connection = peer
		peer.stateUpdateHandler = { [weak self] state in
			Task { @MainActor in
				guard let self, self.connection === peer else { return }
				switch state {
				case .ready:
					self.sendPayload(on: peer)
				case .failed:
					self.failure = HarnessFailure.assertion("Passive DCC fixture connection failed")
				default:
					break
				}
			}
		}
		peer.start(queue: .global())
	}

	private func accept(_ peer: NWConnection) {
		guard connection == nil else {
			peer.cancel()
			failure = HarnessFailure.assertion("Unexpected second DCC receiver")
			return
		}
		connection = peer
		peer.start(queue: .global())
		sendPayload(on: peer)
	}

	private func sendPayload(on peer: NWConnection) {
		let payload = Self.bytes.prefix(cancel ? Self.partialSize : Self.size)
		peer.send(content: payload, completion: .contentProcessed { [weak self] error in
			Task { @MainActor in
				if error != nil {
					self?.failure = HarnessFailure.assertion("DCC fixture send failed")
				}
			}
		})
		receive(peer)
	}

	private func receive(_ peer: NWConnection) {
		peer.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, done, error in
			Task { @MainActor in
				guard let self else { return }
				do {
					let expected = self.cancel ? Self.partialSize : Self.size
					if let data {
						try self.acknowledgements.receive(data, sent: UInt32(expected))
					}
					if self.acknowledgements.acknowledged == expected {
						self.acknowledged = expected
					}
					if done || error != nil {
						guard self.acknowledgements.acknowledged == expected, self.acknowledgements.pending.isEmpty,
						      self.cancel || error == nil
						else { throw HarnessFailure.assertion("DCC closed before expected bytes/ACK") }
						self.complete = true
						self.outcome = self.cancel ? "cancelled after 37003 bytes" : "completed 100003 bytes"
					} else {
						self.receive(peer)
					}
				} catch { self.failure = error }
			}
		}
	}
}
