import Foundation
import Network
import Security

/// Network callbacks only hand events to the actor owning this separate peer process.
@MainActor
final class LoopbackPeer {
	private let kind: ScenarioKind
	private let listener: NWListener
	private var connection: NWConnection?
	private var pending = Data()
	private var state: FixtureProtocol
	private var attempt = 0
	private var failure: Error?
	private var complete = false
	private var dcc: DCCFixturePeer?
	private var dccPort: UInt16 = 0
	private var burstTask: Task<Void, Never>?

	init(kind: ScenarioKind) throws {
		self.kind = kind
		state = FixtureProtocol(reject: false, messaging: kind.messaging)
		let tls: NWProtocolTLS.Options?
		if kind.secured, kind != .tlsStall {
			let options = NWProtocolTLS.Options()
			try sec_protocol_options_set_local_identity(options.securityProtocolOptions, Self.identity())
			tls = options
		} else {
			tls = nil
		}
		let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
		parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
		listener = try NWListener(using: parameters)
	}

	static func identity() throws -> sec_identity_t {
		let fixture = try URL(fileURLWithPath: HarnessFiles.required("E2E_FIXTURE"))
			.deletingLastPathComponent().deletingLastPathComponent()
			.appendingPathComponent("TLS/LoopbackTestIdentity.p12")
		let data = try Data(contentsOf: fixture)
		let options: [String: Any] = [
			kSecImportExportPassphrase as String: "glasstual",
			kSecImportToMemoryOnly as String: true,
		]
		var imported: CFArray?
		guard SecPKCS12Import(data as CFData, options as CFDictionary, &imported) == errSecSuccess,
		      let items = imported as? [[String: Any]],
		      let value = items.first?[kSecImportItemIdentity as String],
		      let identity: SecIdentity = cast(value), let result = sec_identity_create(identity)
		else { throw HarnessFailure.setup("Cannot import in-memory loopback identity") }
		return result
	}

	private static func cast<Value>(_ value: Any) -> Value? {
		value as? Value
	}

	func run() async throws {
		if kind.dcc {
			let dcc = DCCFixturePeer(cancel: kind == .dccCancel)
			self.dcc = dcc
			dccPort = try await dcc.start()
		}
		listener.newConnectionHandler = { [weak self] connection in
			Task { @MainActor in self?.accept(connection) }
		}
		listener.start(queue: .global())
		defer { burstTask?.cancel(); dcc?.stop(); connection?.cancel(); listener.cancel() }
		let startup = HarnessFiles.now + 10
		while listener.state != .ready {
			try HarnessFiles.check(startup)
			try await Task.sleep(for: .milliseconds(25))
		}
		guard let port = listener.port else { throw HarnessFailure.setup("Loopback port missing") }
		try HarnessFiles.write(String(port.rawValue), to: "port")
		let deadline = HarnessFiles.now + 230
		while !complete {
			if let failure {
				throw failure
			}
			if let failure = dcc?.failure {
				throw failure
			}
			try HarnessFiles.check(deadline)
			try await Task.sleep(for: .milliseconds(25))
		}
		try HarnessFiles.write("complete", to: "peer-complete")
	}

	private func accept(_ peer: NWConnection) {
		guard connection == nil, !complete else {
			peer.cancel()
			failure = HarnessFailure.assertion("Unexpected concurrent or extra connection")
			return
		}
		attempt += 1
		connection = peer
		pending = Data()
		state = FixtureProtocol(reject: attempt <= kind.rejectionCount, messaging: kind.messaging,
		                        deniedJoin: kind == .channelDenied ? DeniedJoinFixture() : nil,
		                        interaction: kind.interactive ? InteractiveFixture(kind: kind, dccPort: dccPort) : nil)
		do {
			try HarnessFiles.write(String(attempt), to: "connection-count")
		} catch { failure = error }
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
				guard let self, self.connection === peer else { return }
				do {
					if let data, !data.isEmpty {
						if self.kind == .tlsStall {
							// Consume but never answer ClientHello. No TLS bytes enter artifacts.
							try HarnessFiles.write("ClientHello bytes received", to: "tls-stalled")
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
				} catch { self.failure = error }
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
			if line == "PRIVMSG fixture :E2E_DCC_DONE", dcc?.complete != true {
				throw HarnessFailure.assertion("DCC completion command preceded actual transfer closure")
			}
			let responses = try state.receive(line)
			if line == "PRIVMSG fixture :E2E_BURST_START" {
				startBurst(on: peer)
			}
			for response in responses {
				peer.send(content: Data((response + "\r\n").utf8), completion: .contentProcessed { [weak self] error in
					Task { @MainActor in
						guard let self else { return }
						if error != nil {
							self.failure = HarnessFailure.assertion("Fixture send failed")
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
			if state.registrationIndex == FixtureProtocol.registration.count {
				try HarnessFiles.write(FixtureProtocol.registration.compactMap(\.first).joined(separator: "; "),
				                       to: "registration-\(attempt)")
			}
			for (observed, text, file) in [
				(state.pongSeen, "PONG E2E_PING", "pong-wire"),
				(state.quitSeen, "QUIT E2E_QUIT", "quit-wire"),
				(state.joined, "JOIN #e2e", "join-wire"),
				(state.messageSeen, "PRIVMSG #e2e :E2E_TYPED_MESSAGE", "message-wire"),
				(state.replySeen, "PRIVMSG #e2e :fixture: E2E_TYPED_REPLY", "reply-wire"),
			] where observed {
				try HarnessFiles.write(text, to: file)
			}
			if let phase = state.deniedJoin?.phase {
				try HarnessFiles.write(String(describing: phase), to: "denied-join-phase")
				if phase == .denied {
					try HarnessFiles.write("JOIN #retry denied 477", to: "denied-join-wire")
				}
				if phase == .identified {
					try HarnessFiles.write(
						"NickServ IDENTIFY; 900 ACCOUNT MODE +r",
						to: "identify-wire"
					)
				}
				if phase ==
					.joined
				{
					try HarnessFiles.write("JOIN #retry after identification", to: "retry-join-wire")
				}
			}
			if let interaction = state.interaction {
				try HarnessFiles.write(String(interaction.stage), to: "interaction-stage")
			}
		}
	}

	private func startBurst(on peer: NWConnection) {
		burstTask = Task { @MainActor [weak self] in
			guard let self else { return }
			do {
				for index in 0 ..< 100 {
					try Task.checkCancellation()
					for response in InteractiveFixture.burstBatch(index) {
						peer.send(
							content: Data((response + "\r\n").utf8),
							completion: .contentProcessed { [weak self] error in
								Task { @MainActor in
									if error != nil {
										self?.failure = HarnessFailure.assertion("Burst send failed")
									}
								}
							}
						)
					}
					try HarnessFiles.write(String(index + 1), to: "burst-batches")
					try await Task.sleep(for: .milliseconds(150))
				}
				try HarnessFiles.write("10000 names; 5000 messages", to: "burst-complete")
			} catch { failure = error }
		}
	}

	private func ended(_ peer: NWConnection, transportFailure: Bool) {
		do {
			if kind == .tlsRejectRetry, attempt == 1 {
				guard state.registrationIndex == 0, pending.isEmpty else {
					throw HarnessFailure.assertion("Rejected TLS delivered application data")
				}
				try HarnessFiles.write("TLS closed without IRC registration", to: "tls-rejected")
			} else if kind == .tlsStall {
				guard try HarnessFiles.exists("tls-stalled") else {
					throw HarnessFailure.assertion("Stall did not receive ClientHello")
				}
				try HarnessFiles.write("Stalled TLS closed", to: "stall-closed")
				complete = true
			} else {
				guard !transportFailure else { throw HarnessFailure.assertion("Transport failed instead of clean EOF") }
				try state.eof(pending: pending)
				try HarnessFiles.write("QUIT E2E_QUIT and EOF", to: "disconnect-wire")
				complete = true
			}
			connection = nil
			peer.cancel()
		} catch { failure = error }
	}
}
