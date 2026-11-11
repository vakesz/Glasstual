// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import Network
import Security

nonisolated enum LoopbackServerError: Error {
	case listenerNeverBecameReady
	case peerNeverArrived
	case identityMissing
	case identityUnreadable(OSStatus)
	case timedOut(String)
	case relayRefused
}

/** A checked cast that stays checked. A conditional downcast to a
 CoreFoundation type is rejected outright; behind a generic parameter the same
 cast is the ordinary dynamic one. */
private nonisolated func dynamicCast<Value>(_ value: Any) -> Value? { // nonisolated: pure
	value as? Value
}

/// The plumbing the loopback fixtures share: awaiting a connection's
/// readiness, exact reads, sends, and copying one connection into another.
nonisolated enum LoopbackNetwork {
	/// Swift Testing suites are structs, so there is no test class to hand to
	/// `Bundle(for:)`.
	private final class Anchor {}

	/// The self-signed `127.0.0.1` and `localhost` identity in `Tests/Corpora/TLS`.
	static func loopbackIdentity() throws -> sec_identity_t {
		guard let url = Bundle(for: Anchor.self).url(forResource: "LoopbackTestIdentity", withExtension: "p12") else {
			throw LoopbackServerError.identityMissing
		}

		/* To memory only: the identity is a test fixture and has no business in
		 anyone's keychain. */
		let options: [String: Any] = [
			kSecImportExportPassphrase as String: "glasstual",
			kSecImportToMemoryOnly as String: kCFBooleanTrue as Any,
		]

		var imported: CFArray?
		let status = try SecPKCS12Import(Data(contentsOf: url) as CFData, options as CFDictionary, &imported)

		guard status == errSecSuccess,
		      let items = imported as? [[String: Any]],
		      let value = items.first?[kSecImportItemIdentity as String],
		      let secIdentity: SecIdentity = dynamicCast(value),
		      let identity = sec_identity_create(secIdentity)
		else {
			throw LoopbackServerError.identityUnreadable(status)
		}

		return identity
	}

	/// The port `listener` settled on, once it is ready.
	static func waitUntilListening(_ listener: NWListener) async throws -> UInt16 {
		for _ in 0 ..< 200 {
			if let port = listener.port?.rawValue, listener.state == .ready {
				return port
			}

			try await Task.sleep(for: .milliseconds(25), clock: .continuous)
		}

		throw LoopbackServerError.listenerNeverBecameReady
	}

	/// Starts `connection` and waits for it to become ready.
	static func start(_ connection: NWConnection) async throws {
		let (states, continuation) = AsyncStream<NWConnection.State>.makeStream()
		connection.stateUpdateHandler = { continuation.yield($0) }
		connection.start(queue: .global())

		for await state in states {
			switch state {
			case .ready:
				return
			case .failed, .cancelled, .waiting:
				throw LoopbackServerError.relayRefused
			default:
				continue
			}
		}
	}

	/// Reads exactly `count` bytes.
	static func receive(exactly count: Int, from connection: NWConnection) async throws -> Data {
		try await withCheckedThrowingContinuation { continuation in
			connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, error in
				if let data, data.count == count {
					continuation.resume(returning: data)
				} else {
					continuation.resume(throwing: error ?? LoopbackServerError.relayRefused)
				}
			}
		}
	}

	/// Reads whatever arrives next, up to 64 KiB.
	static func receiveSome(from connection: NWConnection) async throws -> Data {
		try await withCheckedThrowingContinuation { continuation in
			connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, error in
				if let data, data.isEmpty == false {
					continuation.resume(returning: data)
				} else {
					continuation.resume(throwing: error ?? LoopbackServerError.relayRefused)
				}
			}
		}
	}

	static func send(_ data: Data, on connection: NWConnection) async throws {
		try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
			connection.send(content: data, completion: .contentProcessed { error in
				if let error {
					continuation.resume(throwing: error)
				} else {
					continuation.resume()
				}
			})
		}
	}

	/// Copies everything `source` reads into `sink`, and ends `sink` with it.
	static func pump(from source: NWConnection, to sink: NWConnection) {
		source.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
			if let data, data.isEmpty == false {
				sink.send(content: data, completion: .idempotent)
			}

			guard isComplete == false, error == nil else {
				sink.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .idempotent)

				return
			}

			pump(from: source, to: sink)
		}
	}
}

/** A WebSocket server on loopback, plain or behind TLS with the self-signed
 test identity, that records everything the host sends it.

 The upgrade and framing are the fixture's own (``LoopbackWebSocketFraming``),
 so the request target, headers and every frame's opcode and mask are visible
 exactly as they crossed the wire. Connections are taken in arrival order, so
 ``dialsArrived()`` can count dials behind a barrier the way the legacy-suite
 listener does. */
actor LoopbackWebSocketServer {
	private let listener: NWListener
	private let arrivals: AsyncStream<NWConnection>
	private let arrivalContinuation: AsyncStream<NWConnection>.Continuation
	private let choosesSubprotocol: @Sendable ([String]) -> String?
	private let rejectionStatus: Int?

	private var accepting: Task<Void, Never>?
	private var port: UInt16 = 0
	private var connections: [NWConnection] = []
	private var arrivedFromPorts: [UInt16] = []
	private var peer: NWConnection?
	private var inbound = Data()

	/// The upgrade request's head, once it has arrived.
	private(set) var requestHead: String?
	/// Every frame the host has sent, unmasked, in order.
	private(set) var frames: [LoopbackWebSocketFraming.ClientFrame] = []

	init(
		secure: Bool,
		choosingSubprotocol choosesSubprotocol: @escaping @Sendable ([String]) -> String? = { $0.first },
		rejectingWith rejectionStatus: Int? = nil
	) throws {
		let parameters: NWParameters

		if secure {
			let options = NWProtocolTLS.Options()
			try sec_protocol_options_set_local_identity(options.securityProtocolOptions, LoopbackNetwork.loopbackIdentity())
			parameters = NWParameters(tls: options)
		} else {
			parameters = .tcp
		}

		listener = try NWListener(using: parameters)
		(arrivals, arrivalContinuation) = AsyncStream<NWConnection>.makeStream()
		self.choosesSubprotocol = choosesSubprotocol
		self.rejectionStatus = rejectionStatus
	}

	func start() async throws -> UInt16 {
		let arrivalContinuation = arrivalContinuation
		listener.newConnectionHandler = { arrivalContinuation.yield($0) }
		accepting = Task { [arrivals] in
			for await connection in arrivals {
				self.accept(connection)
			}
		}

		listener.start(queue: .global())
		port = try await LoopbackNetwork.waitUntilListening(listener)

		return port
	}

	func stop() {
		arrivalContinuation.finish()
		accepting?.cancel()
		connections.forEach { $0.cancel() }
		connections.removeAll()
		listener.cancel()
	}

	private func accept(_ connection: NWConnection) {
		if case let .hostPort(_, remotePort) = connection.endpoint {
			arrivedFromPorts.append(remotePort.rawValue)
		} else {
			arrivedFromPorts.append(0)
		}

		connections.append(connection)
		peer = connection
		inbound.removeAll()
		connection.start(queue: .global())
		receiveNext(on: connection)
	}

	private func receiveNext(on connection: NWConnection) {
		connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
			Task { await self?.received(data, on: connection, isComplete: isComplete || error != nil) }
		}
	}

	private func received(_ data: Data?, on connection: NWConnection, isComplete: Bool) {
		guard connection === peer else { return }

		if let data {
			inbound.append(data)
		}

		if requestHead == nil, let (head, remainder) = LoopbackWebSocketFraming.requestHead(in: inbound) {
			requestHead = head
			inbound = remainder

			let response = if let rejectionStatus {
				Data("HTTP/1.1 \(rejectionStatus) Refused\r\nContent-Length: 0\r\n\r\n".utf8)
			} else {
				LoopbackWebSocketFraming.upgradeResponse(
					to: head,
					subprotocol: choosesSubprotocol(LoopbackWebSocketFraming.offeredSubprotocols(in: head))
				)
			}

			connection.send(content: response, completion: .idempotent)
		}

		if requestHead != nil {
			frames.append(contentsOf: LoopbackWebSocketFraming.clientFrames(from: &inbound))
		}

		if isComplete == false {
			receiveNext(on: connection)
		}
	}

	/// Sends `data` to the upgraded peer and waits until it is written.
	func send(_ data: Data) async throws {
		_ = try await upgradeRequest()

		guard let peer else { throw LoopbackServerError.peerNeverArrived }

		try await LoopbackNetwork.send(data, on: peer)
	}

	/// The upgrade request's head, waiting for it to arrive.
	func upgradeRequest(timeout: Duration = .seconds(10)) async throws -> String {
		try await poll("the upgrade request", timeout: timeout) { requestHead }
	}

	/// The frames received once there are at least `count` of them.
	func frames(count: Int, timeout: Duration = .seconds(10)) async throws -> [LoopbackWebSocketFraming.ClientFrame] {
		try await poll("\(count) frames", timeout: timeout) { frames.count >= count ? frames : nil }
	}

	/// The first frame `matches` accepts, waiting for it to arrive.
	func frame(
		timeout: Duration = .seconds(10),
		where matches: @Sendable (LoopbackWebSocketFraming.ClientFrame) -> Bool
	) async throws -> LoopbackWebSocketFraming.ClientFrame {
		try await poll("a matching frame", timeout: timeout) { frames.first(where: matches) }
	}

	private func poll<Value>(_ description: String, timeout: Duration, _ value: () -> Value?) async throws -> Value {
		let deadline = ContinuousClock.now + timeout

		while ContinuousClock.now < deadline {
			if let value = value() {
				return value
			}

			try await Task.sleep(for: .milliseconds(10), clock: .continuous)
		}

		throw LoopbackServerError.timedOut(description)
	}

	/** How many connections reached the listener before one the test makes
	 itself, after the host has reported its last event. A connection reaches
	 the listener before any TLS handshake runs, so a refused one counts. */
	func dialsArrived() async throws -> Int {
		guard let barrierPort = NWEndpoint.Port(rawValue: port) else {
			throw LoopbackServerError.peerNeverArrived
		}

		let barrier = NWConnection(host: "127.0.0.1", port: barrierPort, using: .tcp)
		defer { barrier.cancel() }

		let (ready, readiness) = AsyncStream<UInt16>.makeStream()
		barrier.stateUpdateHandler = { state in
			if case .ready = state, case let .hostPort(_, localPort)? = barrier.currentPath?.localEndpoint {
				readiness.yield(localPort.rawValue)
			}
		}
		barrier.start(queue: .global())

		var readyPorts = ready.makeAsyncIterator()
		guard let localPort = await readyPorts.next() else {
			throw LoopbackServerError.peerNeverArrived
		}

		return try await poll("the barrier connection", timeout: .seconds(5)) {
			arrivedFromPorts.firstIndex(of: localPort)
		}
	}
}

/** A SOCKS5 proxy on loopback that accepts any CONNECT, records what it was
 asked for, and relays to the loopback port it was built with whatever the
 name. A name that cannot resolve therefore still connects, which is what
 shows the host never resolved it itself. */
actor LoopbackSOCKS5Relay {
	nonisolated struct Request: Equatable, Sendable {
		let addressType: UInt8
		let host: String
		let port: UInt16
	}

	private let listener: NWListener
	private let targetPort: UInt16
	private var connections: [NWConnection] = []

	private(set) var requests: [Request] = []

	init(forwardingTo targetPort: UInt16) throws {
		listener = try NWListener(using: .tcp)
		self.targetPort = targetPort
	}

	func start() async throws -> UInt16 {
		listener.newConnectionHandler = { [weak self] connection in
			Task { await self?.relay(connection) }
		}
		listener.start(queue: .global())

		return try await LoopbackNetwork.waitUntilListening(listener)
	}

	func stop() {
		connections.forEach { $0.cancel() }
		connections.removeAll()
		listener.cancel()
	}

	private func relay(_ client: NWConnection) async {
		connections.append(client)

		do {
			try await LoopbackNetwork.start(client)

			/* Greeting: version, method count, methods. No authentication. */
			let greeting = try await LoopbackNetwork.receive(exactly: 2, from: client)
			_ = try await LoopbackNetwork.receive(exactly: Int(greeting[greeting.startIndex + 1]), from: client)
			try await LoopbackNetwork.send(Data([0x05, 0x00]), on: client)

			/* Request: version, CONNECT, reserved, address type, address, port. */
			let header = try await [UInt8](LoopbackNetwork.receive(exactly: 4, from: client))
			guard header[0] == 0x05, header[1] == 0x01 else { throw LoopbackServerError.relayRefused }

			let host: String
			switch header[3] {
			case 0x01:
				host = try await LoopbackNetwork.receive(exactly: 4, from: client).map(String.init).joined(separator: ".")
			case 0x03:
				let length = try await LoopbackNetwork.receive(exactly: 1, from: client)
				let name = try await LoopbackNetwork.receive(exactly: Int(length[length.startIndex]), from: client)
				guard let decoded = String(bytes: name, encoding: .utf8) else { throw LoopbackServerError.relayRefused }
				host = decoded
			case 0x04:
				host = try await LoopbackNetwork.receive(exactly: 16, from: client).map { String($0, radix: 16) }.joined(separator: ":")
			default:
				throw LoopbackServerError.relayRefused
			}

			let portBytes = try await [UInt8](LoopbackNetwork.receive(exactly: 2, from: client))
			requests.append(Request(addressType: header[3], host: host, port: UInt16(portBytes[0]) << 8 | UInt16(portBytes[1])))

			let upstream = try await connectUpstream()
			try await LoopbackNetwork.send(Data([0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0]), on: client)

			LoopbackNetwork.pump(from: client, to: upstream)
			LoopbackNetwork.pump(from: upstream, to: client)
		} catch {
			client.cancel()
		}
	}

	private func connectUpstream() async throws -> NWConnection {
		guard let port = NWEndpoint.Port(rawValue: targetPort) else { throw LoopbackServerError.relayRefused }

		let upstream = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
		connections.append(upstream)
		try await LoopbackNetwork.start(upstream)

		return upstream
	}
}

/** An HTTP CONNECT proxy on loopback that records each request line and relays
 to the loopback port it was built with, whatever the requested name. */
actor LoopbackHTTPConnectRelay {
	private let listener: NWListener
	private let targetPort: UInt16
	private var connections: [NWConnection] = []

	private(set) var requestLines: [String] = []

	init(forwardingTo targetPort: UInt16) throws {
		listener = try NWListener(using: .tcp)
		self.targetPort = targetPort
	}

	func start() async throws -> UInt16 {
		listener.newConnectionHandler = { [weak self] connection in
			Task { await self?.relay(connection) }
		}
		listener.start(queue: .global())

		return try await LoopbackNetwork.waitUntilListening(listener)
	}

	func stop() {
		connections.forEach { $0.cancel() }
		connections.removeAll()
		listener.cancel()
	}

	private func relay(_ client: NWConnection) async {
		connections.append(client)

		do {
			try await LoopbackNetwork.start(client)

			var buffer = Data()
			var head: (head: String, remainder: Data)?
			while head == nil {
				try await buffer.append(LoopbackNetwork.receiveSome(from: client))
				head = LoopbackWebSocketFraming.requestHead(in: buffer)
			}

			guard let head, let requestLine = head.head.components(separatedBy: "\r\n").first else {
				throw LoopbackServerError.relayRefused
			}

			requestLines.append(requestLine)

			guard let port = NWEndpoint.Port(rawValue: targetPort) else { throw LoopbackServerError.relayRefused }

			let upstream = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
			connections.append(upstream)
			try await LoopbackNetwork.start(upstream)

			try await LoopbackNetwork.send(Data("HTTP/1.1 200 Connection Established\r\n\r\n".utf8), on: client)
			if head.remainder.isEmpty == false {
				try await LoopbackNetwork.send(head.remainder, on: upstream)
			}

			LoopbackNetwork.pump(from: client, to: upstream)
			LoopbackNetwork.pump(from: upstream, to: client)
		} catch {
			client.cancel()
		}
	}
}
