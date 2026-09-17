// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
@testable import Glasstual
import Network
import Security
import Synchronization
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
	private let readsTraffic: Bool

	init(readsTraffic: Bool = true) throws {
		self.readsTraffic = readsTraffic
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

	func sendToClient(_ chunks: [Data], finishing: Bool = true) async throws {
		for _ in 0 ..< 200 where peer == nil {
			try await Task.sleep(for: .milliseconds(10))
		}
		guard let peer else { throw LoopbackTCPServerError.peerNeverArrived }
		for (index, chunk) in chunks.enumerated() {
			let final = finishing && index == chunks.count - 1
			try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
				peer.send(
					content: chunk,
					contentContext: final ? .finalMessage : .defaultMessage,
					isComplete: true,
					completion: .contentProcessed { error in
						if let error {
							continuation.resume(throwing: error)
						} else {
							continuation.resume()
						}
					}
				)
			}
			if final == false {
				try await Task.sleep(for: .milliseconds(1))
			}
		}
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

		if readsTraffic {
			receiveNextChunk()
		}
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
	case received(Data)
	/// A read the shim left unanswered, for a test that answers it itself.
	/// `overlapped` is set when the host delivered it before the previous read
	/// was answered.
	case withheldRead(overlapped: Bool, acknowledge: @Sendable () -> Void)
	case closedReadStream
}

/// The object NSXPC exports for the host's callbacks, holding nothing but the
/// continuation the suite reads.
private final class SendOrderingClientShim: NSObject, RemoteConnectionClientProtocol {
	private let events: AsyncStream<ConnectionEvent>.Continuation
	private let withholdsAcknowledgements: Bool
	/// Whether a read is out and not yet answered.
	private let readOutstanding = Mutex(false)

	init(events: AsyncStream<ConnectionEvent>.Continuation, withholdsAcknowledgements: Bool = false) {
		self.events = events
		self.withholdsAcknowledgements = withholdsAcknowledgements

		super.init()
	}

	func ircConnectionWillConnect(toProxy _: String, port _: UInt16) {}

	func ircConnectionDidConnect(toHost _: String?) {
		events.yield(.didConnect)
	}

	func ircConnectionDidSecureConnection(withProtocolType _: tls_protocol_version_t,
	                                      cipherSuite _: tls_ciphersuite_t) {}

	func ircConnectionDidCloseReadStream() {
		events.yield(.closedReadStream)
	}

	func ircConnectionDidDisconnectWithError(_ disconnectError: Error?) {
		events.yield(.didDisconnect(disconnectError))
	}

	func ircConnectionDidReceive(_ lines: [Data], acknowledge: @escaping @Sendable () -> Void) {
		for line in lines {
			events.yield(.received(line))
		}
		guard withholdsAcknowledgements else {
			acknowledge()
			return
		}
		let overlapped = readOutstanding.withLock { outstanding in
			defer { outstanding = true }
			return outstanding
		}
		events.yield(.withheldRead(overlapped: overlapped, acknowledge: { [self] in
			readOutstanding.withLock { $0 = false }
			acknowledge()
		}))
	}

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
nonisolated struct ConnectionHostSendOrderingTests {
	static let lineCount = 64

	@Test("Lines handed over one after another reach the wire in that order")
	@concurrent
	func sequentialSendsKeepWireOrder() async throws {
		let sent = Self.testLines
		let received = try await Self.driveConnection { host, _ in
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
		let received = try await Self.driveConnection { host, _ in
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

	@Test("Registration traffic cannot consume the post-registration flood allowance")
	@concurrent
	func registrationHasSeparateFloodBudget() async throws {
		let received = try await Self.driveConnection(waitingFor: 3) { host, server in
			host.send(Data("CAP LS 302\r\n".utf8))
			host.send(Data("NICK tester\r\n".utf8))
			let registration = try await server.lines(waitingFor: 2)
			try #require(registration.count == 2)
			host.enforceFloodControl()
			host.send(Data("PRIVMSG NickServ :IDENTIFY test-only\r\n".utf8))
		}
		#expect(received == ["CAP LS 302", "NICK tester", "PRIVMSG NickServ :IDENTIFY test-only"])
	}

	@Test("Connect commands precede automatic JOIN on the real XPC wire")
	@MainActor
	func connectCommandsPrecedeJoinOnWire() async throws {
		let server = try LoopbackTCPServer()
		let port = try await server.start()
		let client = TestClient(configDictionary: [
			"nickname": "tester",
			"onConnectCommands": ["raw MODE tester +i", "msg NickServ IDENTIFY test-only", "raw WHOIS tester"],
		])
		client.forwardsSentLines = true
		client.forwardsProcessedMessages = true
		_ = try #require(client.findChannelOrCreate("#order"))
		var config = ConnectionConfig()
		config.serverAddress = "127.0.0.1"
		config.serverPort = port
		config.diagnostics = ConnectionDiagnostics()
		let connection = Connection(config: config, onClient: client)
		client.socket = connection
		defer {
			connection.close()
			client.stopAllTimers()
			client.cancelPendingSessionTasks()
			Task { await server.stop() }
		}
		connection.open()
		let registration = try await server.lines(waitingFor: 3)
		try #require(registration.count == 3)
		try await server.sendToClient([Data(":irc.example.org CAP * LS :\r\n".utf8)], finishing: false)
		let capabilities = try await server.lines(waitingFor: 4)
		try #require(capabilities.last == "CAP END")
		try await server.sendToClient([Data(":irc.example.org 001 tester :Welcome\r\n".utf8)], finishing: false)
		let commands = try await server.lines(waitingFor: 7)
		#expect(Array(commands.suffix(3)) == ["MODE tester +i", "PRIVMSG NickServ :IDENTIFY test-only", "WHOIS tester"])
		#expect(!commands.contains { $0.hasPrefix("JOIN ") })
		#expect(client.startup.authentication == .waiting)
		try await server.sendToClient([
			Data(":NickServ!NickServ@services. NOTICE tester :You are now identified\r\n".utf8),
		], finishing: false)
		let joined = try await server.lines(waitingFor: 8)
		#expect(joined.last == "JOIN #order")
		#expect(client.startup.authenticationTask == nil)
	}

	@Test("Queued PONGs bypass an exhausted flood window and retain their own order")
	@concurrent
	func queuedPongsBypassFloodControl() async throws {
		let primingLine = "PRIVMSG #order :consume flood allowance"
		let received = try await Self.driveConnection(waitingFor: 3) { host, server in
			host.enforceFloodControl()
			host.send(Data((primingLine + "\r\n").utf8))
			// Confirm the valid one-message allowance is exhausted before testing bypass writes.
			let primingLines = try await server.lines(waitingFor: 1)
			try #require(primingLines == [primingLine])
			for line in Self.testLines {
				host.send(Data((line + "\r\n").utf8))
			}
			host.send(Data("PONG :one\r\n".utf8), bypassQueue: true)
			host.send(Data("PONG :two\r\n".utf8), bypassQueue: true)
		}
		#expect(received == [primingLine, "PONG :one", "PONG :two"])
	}

	@Test("Close and certificate export pass queued writes during a stalled TLS handshake")
	@concurrent
	func stalledHandshakeDoesNotBlockControl() async throws {
		let server = try LoopbackTCPServer()
		let port = try await server.start()
		var config = ConnectionConfig()
		config.serverAddress = "127.0.0.1"
		config.serverPort = port
		config.connectionPrefersSecuredConnection = true
		let (events, continuation) = AsyncStream<ConnectionEvent>.makeStream()
		let service = NSXPCConnection(serviceName: "com.vakesz.glasstual.IRCConnectionHost")
		service.remoteObjectInterface = RemoteConnectionInterface.server()
		service.exportedInterface = RemoteConnectionInterface.client()
		service.exportedObject = SendOrderingClientShim(events: continuation)
		service.resume()
		let deadline = Task {
			try? await Task.sleep(for: .seconds(5))
			continuation.finish()
		}
		defer {
			deadline.cancel()
			service.invalidate()
			Task { await server.stop() }
		}
		let host = try #require(service.remoteObjectProxy as? RemoteConnectionServerProtocol)
		host.open(with: ConnectionConfigEnvelope(config: config))
		host.send(Data("CAP LS 302\r\n".utf8))
		host.send(Data("NICK tester\r\n".utf8))
		host.exportSecureConnectionInformation { _ in host.close() }
		var disconnected = false
		for await event in events {
			switch event {
			case .didConnect:
				Issue.record("A stalled TLS handshake was reported connected")
			case .didDisconnect:
				disconnected = true
				continuation.finish()
			case .received, .withheldRead, .closedReadStream:
				break
			}
		}
		#expect(disconnected, "queued sends blocked certificate export or close")
	}

	@Test("An established connection with a backpressured writer still exports and closes")
	@concurrent
	func backpressuredWriterDoesNotBlockControl() async throws {
		let server = try LoopbackTCPServer(readsTraffic: false)
		let port = try await server.start()
		var config = ConnectionConfig()
		config.serverAddress = "127.0.0.1"
		config.serverPort = port
		config.connectionPrefersSecuredConnection = false
		let (events, continuation) = AsyncStream<ConnectionEvent>.makeStream()
		let service = NSXPCConnection(serviceName: "com.vakesz.glasstual.IRCConnectionHost")
		service.remoteObjectInterface = RemoteConnectionInterface.server()
		service.exportedInterface = RemoteConnectionInterface.client()
		service.exportedObject = SendOrderingClientShim(events: continuation)
		service.resume()
		let deadline = Task {
			try? await Task.sleep(for: .seconds(5))
			continuation.finish()
		}
		defer {
			deadline.cancel()
			service.invalidate()
			Task { await server.stop() }
		}
		let host = try #require(service.remoteObjectProxy as? RemoteConnectionServerProtocol)
		host.open(with: ConnectionConfigEnvelope(config: config))
		var connected = false
		var disconnected = false
		for await event in events {
			switch event {
			case .didConnect:
				connected = true
				// More than the TCP window can hold while the peer never reads.
				host.send(Data(repeating: 0x78, count: 32 * 1024 * 1024))
				host.send(Data("NICK tester\r\n".utf8))
				host.exportSecureConnectionInformation { _ in host.close() }
			case .didDisconnect:
				disconnected = true
				continuation.finish()
			case .received, .withheldRead, .closedReadStream:
				break
			}
		}
		#expect(connected)
		#expect(disconnected, "the writer held the command drain behind a network completion")
	}

	/** The host reads the next chunk only once the application has answered
	 for the last one.

	 The application used to be told about lines over a one-way call while the
	 host went straight on reading, so a server that sent faster than the main
	 actor could keep up filled a queue between the processes until the
	 application gave up and disconnected. The reply is the flow control now: a
	 read that arrives while the previous one is unanswered is the regression.
	 The first answer is held until the server has written everything, which is
	 when an unthrottled host would already have delivered more. */
	@Test("The host delivers no further read until the application acknowledges the last")
	@concurrent
	func readsWaitForTheApplicationsAcknowledgement() async throws {
		let burst = (0 ..< 4000).map { "NOTICE me :line \($0)" }
		let chunks = stride(from: 0, to: burst.count, by: 500).map { start in
			Data(burst[start ..< min(start + 500, burst.count)].map { $0 + "\r\n" }.joined().utf8)
		}
		let server = try LoopbackTCPServer()
		let port = try await server.start()
		var config = ConnectionConfig()
		config.serverAddress = "127.0.0.1"
		config.serverPort = port
		let (events, continuation) = AsyncStream<ConnectionEvent>.makeStream()
		let service = NSXPCConnection(serviceName: "com.vakesz.glasstual.IRCConnectionHost")
		service.remoteObjectInterface = RemoteConnectionInterface.server()
		service.exportedInterface = RemoteConnectionInterface.client()
		service.exportedObject = SendOrderingClientShim(events: continuation, withholdsAcknowledgements: true)
		service.resume()
		let deadline = Task {
			try? await Task.sleep(for: .seconds(20))
			continuation.finish()
		}
		defer {
			deadline.cancel()
			service.invalidate()
			Task { await server.stop() }
		}
		let host = try #require(service.remoteObjectProxy as? RemoteConnectionServerProtocol)
		let sending = Task { try await server.sendToClient(chunks) }
		defer { sending.cancel() }
		host.open(with: ConnectionConfigEnvelope(config: config))

		var lines: [String] = []
		var reads = 0
		var overlaps = 0
		for await event in events {
			switch event {
			case let .received(data):
				try lines.append(#require(String(bytes: data, encoding: .utf8)))
			case let .withheldRead(overlapped, acknowledge):
				reads += 1
				if overlapped {
					overlaps += 1
				}
				if reads == 1 {
					try await sending.value
				}
				acknowledge()
			case .didDisconnect:
				continuation.finish()
			case .didConnect, .closedReadStream:
				break
			}
		}

		#expect(overlaps == 0, "a read was delivered before the previous one was acknowledged")
		#expect(reads >= 2)
		#expect(lines == burst)
	}

	// MARK: - The harness

	@Test("Real host framing preserves fragments, burst order, CRLF splits and final ERROR with EOF")
	@concurrent
	func inboundFramingPreservesWireOrder() async throws {
		let burst = (0 ..< 12000).map { "NOTICE me :line \($0)" }
		let result = try await Self.receiveFromPeer([
			Data("PING :frag".utf8), Data("mented\r".utf8), Data("\n".utf8),
			Data((burst.joined(separator: "\n") + "\nERROR :final rejection\r\n").utf8),
		])
		if case .didConnect = result.first {} else {
			Issue.record("First server bytes preceded readiness")
		}
		let lines = result.compactMap { event -> String? in
			guard case let .received(data) = event else { return nil }
			return String(data: data, encoding: .utf8)
		}
		#expect(lines == ["PING :fragmented"] + burst + ["ERROR :final rejection"])
		let terminal = result.suffix(3)
		#expect(terminal.count == 3)
		if terminal.count == 3 {
			guard case .received = terminal[terminal.startIndex],
			      case .closedReadStream = terminal[terminal.index(after: terminal.startIndex)],
			      case .didDisconnect(nil) = terminal[terminal.index(before: terminal.endIndex)]
			else {
				Issue.record("Final line, EOF and successful disconnect did not arrive in order")
				return
			}
		}
	}

	/** Every CR at the end of a line belongs to the terminator.

	 A server whose MOTD file has CRLF line endings writes each of those lines
	 as `CR CR LF`. Stripping a single CR left one on the end of the trailing
	 parameter, where nothing downstream may carry it. Both framing paths are
	 covered: the line that arrives whole inside one read, and the line that had
	 to wait in the buffer for its terminator. */
	@Test("A doubled terminator leaves no carriage return on the line")
	@concurrent
	func doubledCarriageReturnsAreTerminators() async throws {
		let result = try await Self.receiveFromPeer([
			Data(":server 372 me :- whole\r\r\n".utf8),
			Data(":server 372 me :- frag".utf8),
			Data("mented\r\r".utf8),
			Data("\nERROR :finished\r\n".utf8),
		])
		let lines = result.compactMap { event -> String? in
			guard case let .received(data) = event else { return nil }
			return String(data: data, encoding: .utf8)
		}

		#expect(lines == [":server 372 me :- whole", ":server 372 me :- fragmented", "ERROR :finished"])
	}

	@Test("Host rejects an oversized line whether or not its last chunk includes a newline", arguments: [true, false])
	@concurrent
	func oversizedLineFailsExplicitly(_ terminated: Bool) async throws {
		var chunks = Array(repeating: Data(repeating: 0x78, count: 65536), count: 16)
		chunks.append(Data((terminated ? "x\n" : "x").utf8))
		let result = try await Self.receiveFromPeer(chunks)
		#expect(result.contains {
			if case .didDisconnect(.some) = $0 {
				true
			} else {
				false
			}
		})
		#expect(result.contains {
			if case .received = $0 {
				true
			} else {
				false
			}
		} == false)
	}

	@Test("A line exactly at the host byte ceiling is delivered without truncation")
	@concurrent
	func exactLineCeilingIsAccepted() async throws {
		let chunk = Data(repeating: 0x78, count: 65536)
		var chunks = Array(repeating: chunk, count: 16)
		chunks.append(Data("\nERROR :finished\n".utf8))
		let result = try await Self.receiveFromPeer(chunks)
		let received = result.compactMap { event -> Data? in
			guard case let .received(data) = event else { return nil }
			return data
		}
		#expect(received == [Data(repeating: 0x78, count: 1024 * 1024), Data("ERROR :finished".utf8)])
		#expect(result.contains {
			if case .didDisconnect(nil) = $0 {
				true
			} else {
				false
			}
		})
	}

	@Test("EOF with an unterminated line reports a protocol error instead of silent loss")
	@concurrent
	func truncatedLineFailsExplicitly() async throws {
		let result = try await Self.receiveFromPeer([Data("PING :valid\r\nERROR :truncated".utf8)])
		#expect(result
			.contains {
				if case let .received(data) = $0 {
					data == Data("PING :valid".utf8)
				} else {
					false
				}
			})
		#expect(result.contains {
			if case .didDisconnect(.some) = $0 {
				true
			} else {
				false
			}
		})
	}

	private static func receiveFromPeer(_ chunks: [Data]) async throws -> [ConnectionEvent] {
		let server = try LoopbackTCPServer()
		let port = try await server.start()
		var config = ConnectionConfig()
		config.serverAddress = "127.0.0.1"
		config.serverPort = port
		let (events, continuation) = AsyncStream<ConnectionEvent>.makeStream()
		let service = NSXPCConnection(serviceName: "com.vakesz.glasstual.IRCConnectionHost")
		service.remoteObjectInterface = RemoteConnectionInterface.server()
		service.exportedInterface = RemoteConnectionInterface.client()
		service.exportedObject = SendOrderingClientShim(events: continuation)
		service.resume()
		let deadline = Task {
			try? await Task.sleep(for: .seconds(10))
			continuation.finish()
		}
		defer {
			deadline.cancel()
			service.invalidate()
			Task { await server.stop() }
		}
		let host = try #require(service.remoteObjectProxy as? RemoteConnectionServerProtocol)
		let sending = Task { try await server.sendToClient(chunks) }
		defer { sending.cancel() }
		host.open(with: ConnectionConfigEnvelope(config: config))
		var result: [ConnectionEvent] = []
		for await event in events {
			result.append(event)
			switch event {
			case .didConnect:
				break
			case .didDisconnect:
				continuation.finish()
			case .received, .withheldRead, .closedReadStream:
				break
			}
		}
		#expect(
			result.contains {
				if case .didDisconnect = $0 {
					true
				} else {
					false
				}
			},
			"Host never disconnected before the deadline"
		)
		return result
	}

	static var testLines: [String] {
		(0 ..< lineCount).map { "PRIVMSG #order :line \($0)" }
	}

	/** Connects the real service to a loopback listener, runs `send` once the
	 host reports the connection up, and returns the lines the listener read. */
	private static func driveConnection(
		waitingFor count: Int = lineCount,
		_ send: @Sendable (any RemoteConnectionServerProtocol, LoopbackTCPServer) async throws -> Void
	) async throws -> [String] {
		let server = try LoopbackTCPServer()
		let port = try await server.start()

		var config = ConnectionConfig()
		config.serverAddress = "127.0.0.1"
		config.serverPort = port
		config.connectionPrefersSecuredConnection = false
		config.floodControlMaximumMessages = 1
		// Keep refills outside the fixture's bounded connection and receive waits.
		config.floodControlDelayInterval = 60

		let (events, continuation) = AsyncStream<ConnectionEvent>.makeStream()
		let shim = SendOrderingClientShim(events: continuation)

		let service = NSXPCConnection(serviceName: "com.vakesz.glasstual.IRCConnectionHost")
		service.remoteObjectInterface = RemoteConnectionInterface.server()
		service.exportedInterface = RemoteConnectionInterface.client()
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
			case .received, .withheldRead, .closedReadStream:
				break
			}

			if connected {
				break
			}
		}

		try #require(connected, "the connection host never reported the connection up")

		try await send(host, server)

		let received = try await server.lines(waitingFor: count)

		host.close()

		return received
	}
}
