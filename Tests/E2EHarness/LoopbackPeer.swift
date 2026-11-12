import Foundation
import Network
import Security

/** What the peer observed, read by scenarios and self-tests as it changes.
 Only synthetic values enter it; unexpected wire content never does. */
struct PeerEvidence {
	/// Connections accepted so far.
	var connections = 0
	/// IRC lines received over all connections.
	var linesReceived = 0
	/// The registration lines each attempt sent, by attempt number from 1.
	var registrations: [Int: String] = [:]
	var pongSeen = false
	var quitSeen = false
	var joined = false
	var messageSeen = false
	var replySeen = false
	/// The credential-consent exchange, for those modes.
	var consent: String?
	/// Every phase the denied-JOIN fixture passed through, in order.
	var deniedJoinPhases: [DeniedJoinFixture.Phase] = []
	var interactionStage = 0
	var banLine: String?
	var tlsStalled = false
	var tlsRejected = false
	var stallClosed = false
	/// How the last connection ended: `QUIT and EOF` when the client quit cleanly.
	var disconnect: String?
	var burstBatches = 0
	var burstComplete = false
	/// Set when the client's final connection has closed and nothing is pending.
	var complete = false
	/// The verb and first parameter of the last lines received, for diagnostics.
	var recent: [String] = []
}

/** The scripted IRC server a scenario points the application at, in the
 harness's own process.

 Network callbacks hand their events to the main actor, which owns the peer's
 state. A protocol violation is recorded as ``failure`` and stops the peer
 answering; scenarios check it on every wait. */
final class LoopbackPeer {
	let mode: FixtureMode
	private let listener: NWListener
	private var connection: NWConnection?
	private var pending = Data()
	private var state: FixtureProtocol
	private var burstTask: Task<Void, Never>?
	private(set) var dcc: DCCFixturePeer?
	private let usesPassiveDCC: Bool
	private(set) var evidence = PeerEvidence()
	private(set) var failure: (any Error)?
	private(set) var port: UInt16 = 0

	init(mode: FixtureMode, corpora: URL, passiveDCC: Bool = false) throws {
		self.mode = mode
		usesPassiveDCC = passiveDCC
		state = FixtureProtocol(mode: mode, attempt: 1)
		let tls: NWProtocolTLS.Options?
		if mode.secured, mode != .tlsStall {
			let options = NWProtocolTLS.Options()
			try sec_protocol_options_set_local_identity(options.securityProtocolOptions, Self.identity(corpora: corpora))
			tls = options
		} else {
			tls = nil
		}
		let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
		parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
		listener = try NWListener(using: parameters)
	}

	/// The throwaway loopback identity in `Tests/Corpora/TLS`, imported in memory.
	static func identity(corpora: URL) throws -> sec_identity_t {
		let data = try Data(contentsOf: corpora.appendingPathComponent("TLS/LoopbackTestIdentity.p12"))
		let options: [String: Any] = [
			kSecImportExportPassphrase as String: "glasstual",
			kSecImportToMemoryOnly as String: true,
		]
		var imported: CFArray?
		guard SecPKCS12Import(data as CFData, options as CFDictionary, &imported) == errSecSuccess,
		      let items = imported as? [[String: Any]],
		      let value = items.first?[kSecImportItemIdentity as String],
		      let identity: SecIdentity = cast(value), let result = sec_identity_create(identity)
		else { throw HarnessFailure.setup("Cannot import the in-memory loopback identity") }
		return result
	}

	private static func cast<Value>(_ value: Any) -> Value? {
		value as? Value
	}

	/// Starts listening and returns the port.
	func start() async throws -> UInt16 {
		if mode.dcc {
			let dcc = DCCFixturePeer(cancel: mode == .dccCancel)
			self.dcc = dcc
			_ = try await dcc.start()
		}
		listener.newConnectionHandler = { [weak self] connection in
			Task { @MainActor in self?.accept(connection) }
		}
		listener.start(queue: .global())
		try await Wait.until("loopback listener ready", timeout: .seconds(10)) { self.listener.state == .ready }
		guard let port = listener.port?.rawValue else { throw HarnessFailure.setup("Loopback port missing") }
		self.port = port
		return port
	}

	func stop() {
		burstTask?.cancel()
		dcc?.stop()
		connection?.cancel()
		listener.cancel()
	}

	/// Throws the first protocol violation the peer or its DCC side recorded.
	func check() throws {
		if let failure {
			throw failure
		}
		if let failure = dcc?.failure {
			throw failure
		}
	}

	private func accept(_ peer: NWConnection) {
		guard connection == nil, !evidence.complete else {
			peer.cancel()
			record(HarnessFailure.assertion("Unexpected concurrent or extra connection"))
			return
		}
		evidence.connections += 1
		connection = peer
		pending = Data()
		let interaction = mode.interactive ? InteractiveFixture(
			mode: mode,
			dccPort: dcc?.port ?? 0,
			usesPassiveDCC: usesPassiveDCC,
			dccFilename: dcc?.filename ?? "e2e-transfer.bin"
		) : nil
		state = FixtureProtocol(mode: mode, attempt: evidence.connections, interaction: interaction)
		peer.stateUpdateHandler = { [weak self] status in
			Task { @MainActor in
				guard let self, self.connection === peer else { return }
				if case .failed = status {
					self.ended(peer, transportFailure: true)
				}
			}
		}
		peer.start(queue: .global())
		receive(peer)
	}

	private func receive(_ peer: NWConnection) {
		peer.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, done, error in
			Task { @MainActor in
				guard let self, self.connection === peer, self.failure == nil else { return }
				do {
					if let data, !data.isEmpty {
						if self.mode == .tlsStall {
							// Consume but never answer the ClientHello.
							self.evidence.tlsStalled = true
						} else {
							try self.received(data, on: peer)
						}
					}
					guard self.connection === peer else { return }
					if done || error != nil {
						self.ended(peer, transportFailure: error != nil)
					} else {
						self.receive(peer)
					}
				} catch { self.record(error) }
			}
		}
	}

	private func received(_ data: Data, on peer: NWConnection) throws {
		pending.append(data)
		guard pending.count <= 65536 else { throw HarnessFailure.assertion("Oversized IRC input") }
		while let range = pending.range(of: Data("\r\n".utf8)) {
			guard let line = String(data: pending[..<range.lowerBound], encoding: .utf8) else {
				throw HarnessFailure.assertion("Non-UTF8 IRC input")
			}
			pending.removeSubrange(..<range.upperBound)
			evidence.linesReceived += 1
			evidence.recent = Array((evidence.recent + [line.split(separator: " ").prefix(2).joined(separator: " ")])
				.suffix(12))
			if line == "PRIVMSG fixture :E2E_DCC_DONE", dcc?.complete != true {
				throw HarnessFailure.assertion("DCC completion command preceded actual transfer closure")
			}
			let responses = try state.receive(line)
			if line == "PRIVMSG fixture :E2E_BURST_START" {
				startBurst(on: peer)
			}
			send(responses, on: peer)
			observe()
			if let port = state.interaction?.dccListeningPort {
				dcc?.connect(to: port)
			}
		}
	}

	private func send(_ responses: [String], on peer: NWConnection) {
		for response in responses {
			peer.send(content: Data((response + "\r\n").utf8), completion: .contentProcessed { [weak self] error in
				Task { @MainActor in
					guard let self else { return }
					if error != nil {
						self.record(HarnessFailure.assertion("Fixture send failed"))
					}
					if response == "ERROR :E2E_REGISTRATION_REJECTED" {
						peer.cancel()
						if self.connection === peer {
							self.connection = nil
						}
					}
				}
			})
		}
	}

	/// Copies what the protocol state has seen into the evidence.
	private func observe() {
		if state.registrationIndex == FixtureProtocol.registration.count {
			evidence.registrations[evidence.connections] = FixtureProtocol.registration.compactMap(\.first)
				.joined(separator: "; ")
		}
		evidence.pongSeen = evidence.pongSeen || state.pongSeen
		evidence.quitSeen = evidence.quitSeen || state.quitSeen
		evidence.joined = evidence.joined || state.joined || state.banAccount?.joined == true
		evidence.messageSeen = evidence.messageSeen || state.messageSeen
		evidence.replySeen = evidence.replySeen || state.replySeen
		if let consent = state.consent {
			evidence.consent = consent.evidence
		}
		if let phase = state.deniedJoin?.phase, evidence.deniedJoinPhases.last != phase {
			evidence.deniedJoinPhases.append(phase)
		}
		if let interaction = state.interaction {
			evidence.interactionStage = interaction.stage
		}
		if let ban = state.banAccount?.banLine {
			evidence.banLine = ban
		}
	}

	/// Sends the burst at its own pace, off the main actor: the harness's
	/// Accessibility reads must not slow the server down.
	private func startBurst(on peer: NWConnection) {
		burstTask = Task.detached { [weak self] in
			for index in 0 ..< 100 {
				guard Task.isCancelled == false else { return }
				for line in InteractiveFixture.burstBatch(index) {
					peer.send(content: Data((line + "\r\n").utf8), completion: .contentProcessed { error in
						if error != nil {
							Task { @MainActor in self?.record(HarnessFailure.assertion("Burst send failed")) }
						}
					})
				}
				Task { @MainActor in self?.evidence.burstBatches = index + 1 }
				try? await Task.sleep(for: .milliseconds(150))
			}
			Task { @MainActor in self?.evidence.burstComplete = true }
		}
	}

	private func ended(_ peer: NWConnection, transportFailure: Bool) {
		do {
			if mode == .tlsRejectRetry, evidence.connections == 1 {
				guard state.registrationIndex == 0, pending.isEmpty, evidence.linesReceived == 0 else {
					throw HarnessFailure.assertion("Rejected TLS delivered application data")
				}
				evidence.tlsRejected = true
			} else if mode == .tlsStall {
				guard evidence.tlsStalled else { throw HarnessFailure.assertion("Stall did not receive ClientHello") }
				evidence.stallClosed = true
				evidence.complete = true
			} else {
				guard !transportFailure else { throw HarnessFailure.assertion("Transport failed instead of clean EOF") }
				try state.eof(pending: pending)
				evidence.disconnect = "QUIT and EOF"
				evidence.complete = true
			}
			connection = nil
			peer.cancel()
		} catch { record(error) }
	}

	private func record(_ error: any Error) {
		if failure == nil {
			failure = error
		}
	}
}
