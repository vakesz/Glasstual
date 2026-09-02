/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import CocoaExtensions
import Foundation
@testable import Glasstual
import Network
import Security
import Testing

private enum LoopbackTCPServerError: Error {
	case listenerNeverBecameReady
	case peerNeverArrived
}

/// A plain TCP listener on loopback that keeps everything the client wrote, in
/// the order the socket delivered it.
private actor LoopbackTCPServer {
	private let listener: NWListener
	private var peer: NWConnection?
	private var received = Data()

	init() throws {
		listener = try NWListener(using: .tcp)
	}

	/// The port the listener settled on, once it is ready.
	func start() async throws -> UInt16 {
		listener.newConnectionHandler = { [weak self] connection in
			Task { await self?.accept(connection) }
		}

		listener.start(queue: .global())

		for _ in 0 ..< 200 {
			if let port = listener.port?.rawValue, listener.state == .ready {
				return port
			}

			try await Task.sleep(for: .milliseconds(25), clock: .continuous)
		}

		throw LoopbackTCPServerError.listenerNeverBecameReady
	}

	func stop() {
		peer?.cancel()
		peer = nil
		listener.cancel()
	}

	/// The complete lines received so far, terminators removed.
	var lines: [String] {
		let text = String(bytes: received, encoding: .utf8) ?? ""
		let components = text.components(separatedBy: "\r\n")

		/* The text after the last terminator is a line still arriving, or the
		 empty remainder after a complete one. Either way it is not a line. */
		return Array(components.dropLast())
	}

	/// Waits for `count` lines, then returns everything that arrived. A short
	/// settling read follows so an extra line — one that arrived out of order,
	/// or twice — is part of what the test sees rather than being cut off.
	func lines(waitingFor count: Int) async throws -> [String] {
		for _ in 0 ..< 400 {
			if lines.count >= count {
				break
			}

			try await Task.sleep(for: .milliseconds(25), clock: .continuous)
		}

		try await Task.sleep(for: .milliseconds(250), clock: .continuous)

		return lines
	}

	private func accept(_ connection: NWConnection) {
		peer = connection

		connection.start(queue: .global())

		receiveNextChunk()
	}

	private func receiveNextChunk() {
		guard let peer else { return }

		peer.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
			Task { await self?.received(content, isComplete: isComplete, failed: error != nil) }
		}
	}

	private func received(_ content: Data?, isComplete: Bool, failed: Bool) {
		if let content, content.isEmpty == false {
			received.append(content)
		}

		guard failed == false, isComplete == false else { return }

		receiveNextChunk()
	}
}

/// The connection events this suite waits on.
private enum ConnectionEvent: Sendable {
	case didConnect
	case didDisconnect(Error?)
}

/// The object NSXPC exports for the host's callbacks, holding nothing but the
/// continuation the suite reads.
private final class SendOrderingClientShim: NSObject, RemoteConnectionClientProtocol {
	private let events: AsyncStream<ConnectionEvent>.Continuation

	init(events: AsyncStream<ConnectionEvent>.Continuation) {
		self.events = events

		super.init()
	}

	func ircConnectionWillConnect(toProxy _: String, port _: UInt16) {}

	func ircConnectionDidConnect(toHost _: String?) {
		events.yield(.didConnect)
	}

	func ircConnectionDidSecureConnection(withProtocolType _: tls_protocol_version_t,
	                                      cipherSuite _: tls_ciphersuite_t) {}

	func ircConnectionDidCloseReadStream() {}

	func ircConnectionDidDisconnectWithError(_ disconnectError: Error?) {
		events.yield(.didDisconnect(disconnectError))
	}

	func ircConnectionDidReceive(_: Data) {}

	func ircConnectionRequestInsecureCertificateTrust(_ trustBlock: @escaping TrustDecisionHandler) {
		trustBlock(false)
	}

	func ircConnectionWillSend(_: Data) {}

	func ircConnectionDidSendData() {}
}

/** What the application hands the connection host has to reach the wire, all of
 it and in the order it was handed over.

 The host answers NSXPC on a serial queue but does its work on an actor, and
 only one write is in flight at a time. Both of those seams have dropped or
 reordered lines before: an unstructured `Task` per exported method left the
 global executor to order the messages, and a write that collided with one
 already running was discarded without telling the sender. */
@Suite("Connection host send ordering", .serialized)
nonisolated struct ConnectionHostSendOrderingTests { // nonisolated: value
	static let lineCount = 64

	@Test("Lines handed over one after another reach the wire in that order")
	@concurrent
	func sequentialSendsKeepWireOrder() async throws {
		let sent = Self.testLines
		let received = try await Self.driveConnection { host in
			for line in sent {
				host.send(Data((line + "\r\n").utf8))
			}
		}

		#expect(received == sent, "the lines did not arrive, or did not arrive in order")
	}

	@Test("Lines handed over from many tasks at once all reach the wire")
	@concurrent
	func concurrentSendsAreNeverDropped() async throws {
		let sent = Self.testLines
		let received = try await Self.driveConnection { host in
			await withTaskGroup(of: Void.self) { group in
				for line in sent {
					group.addTask {
						host.send(Data((line + "\r\n").utf8))
					}
				}
			}
		}

		#expect(received.count == sent.count, "a line was dropped or sent twice")
		#expect(Set(received) == Set(sent), "the lines that arrived are not the lines that were sent")
	}

	// MARK: - The harness

	static var testLines: [String] {
		(0 ..< lineCount).map { "PRIVMSG #order :line \($0)" }
	}

	/** Connects the real service to a loopback listener, runs `send` once the
	 host reports the connection up, and returns the lines the listener read. */
	static func driveConnection(
		_ send: @Sendable (any RemoteConnectionServerProtocol) async -> Void
	) async throws -> [String] {
		let server = try LoopbackTCPServer()
		let port = try await server.start()

		var config = IRCConnectionConfig()
		config.serverAddress = "127.0.0.1"
		config.serverPort = port
		config.connectionPrefersSecuredConnection = false

		let (events, continuation) = AsyncStream<ConnectionEvent>.makeStream()
		let shim = SendOrderingClientShim(events: continuation)

		let service = NSXPCConnection(serviceName: "com.vakesz.glasstual.IRCConnectionHost")
		service.remoteObjectInterface = NSXPCInterface(with: RemoteConnectionServerProtocol.self)
		service.exportedInterface = NSXPCInterface(with: RemoteConnectionClientProtocol.self)
		service.exportedObject = shim
		service.resume()

		defer {
			service.invalidate()

			Task { await server.stop() }
		}

		let host = try #require(
			service.remoteObjectProxy as? RemoteConnectionServerProtocol,
			"the connection host did not vend its proxy"
		)

		/* A test that hangs tells nobody anything, so the stream ends on its own
		 if the connection never gets anywhere. */
		let deadline = Task {
			try? await Task.sleep(for: .seconds(30), clock: .continuous)

			continuation.finish()
		}

		defer { deadline.cancel() }

		host.open(with: ConnectionConfigEnvelope(config: config))

		var connected = false

		for await event in events {
			switch event {
			case .didConnect:
				connected = true
			case let .didDisconnect(error):
				throw error ?? LoopbackTCPServerError.peerNeverArrived
			}

			if connected {
				break
			}
		}

		try #require(connected, "the connection host never reported the connection up")

		await send(host)

		let received = try await server.lines(waitingFor: lineCount)

		host.close()

		return received
	}
}
