// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
@testable import Glasstual
import Network
import Security
import Testing

/// Everything the connection host reports back, in the order it sent it.
private nonisolated enum WebSocketHostEvent: Sendable {
	case willConnectToProxy(host: String, port: UInt16)
	case didConnect(host: String?)
	case didNegotiate(String?)
	case didSecure(protocolVersion: tls_protocol_version_t, cipherSuite: tls_ciphersuite_t)
	case didReceive([Data])
	case didCloseReadStream
	case didDisconnect(Error?)
	case requestTrust(TrustDecisionHandler)

	var isDisconnect: Bool {
		if case .didDisconnect = self {
			true
		} else {
			false
		}
	}
}

/// The object NSXPC exports for the host's callbacks. It holds nothing but the
/// continuation, and every callback arrives on the NSXPC queue.
private final class WebSocketHostShim: NSObject, RemoteConnectionClientProtocol {
	private let events: AsyncStream<WebSocketHostEvent>.Continuation

	init(events: AsyncStream<WebSocketHostEvent>.Continuation) {
		self.events = events

		super.init()
	}

	func willConnect(toProxy proxyHost: String, port proxyPort: UInt16) {
		events.yield(.willConnectToProxy(host: proxyHost, port: proxyPort))
	}

	func didConnect(toHost host: String?) {
		events.yield(.didConnect(host: host))
	}

	func didSecureConnection(
		withProtocolType protocolType: tls_protocol_version_t,
		cipherSuite: tls_ciphersuite_t,
		leafCertificate _: Data?
	) {
		events.yield(.didSecure(protocolVersion: protocolType, cipherSuite: cipherSuite))
	}

	func didCloseReadStream() {
		events.yield(.didCloseReadStream)
	}

	func didDisconnect(withError disconnectError: Error?) {
		events.yield(.didDisconnect(disconnectError))
	}

	func didReceive(_ lines: [Data], acknowledge: @escaping @Sendable () -> Void) {
		events.yield(.didReceive(lines))
		acknowledge()
	}

	func requestInsecureCertificateTrust(_ trustBlock: @escaping TrustDecisionHandler) {
		events.yield(.requestTrust(trustBlock))
	}

	func willSend(_: Data) {}

	func didSendData() {}

	func didNegotiateWebSocketSubprotocol(_ subprotocol: String?) {
		events.yield(.didNegotiate(subprotocol))
	}
}

/** One connection through the real XPC service, and what it reported.

 A deadline ends the event stream if a test stops hearing anything, so a
 regression fails instead of hanging. */
private nonisolated struct WebSocketHostHarness {
	let host: any RemoteConnectionServerProtocol
	private let service: NSXPCConnection
	private let shim: WebSocketHostShim
	private let deadline: Task<Void, Never>
	private var iterator: AsyncStream<WebSocketHostEvent>.AsyncIterator

	/// Every event read so far, in order.
	private(set) var log: [WebSocketHostEvent] = []

	init(config: ConnectionConfig, timeout: Duration = .seconds(30)) throws {
		let (events, continuation) = AsyncStream<WebSocketHostEvent>.makeStream()
		shim = WebSocketHostShim(events: continuation)

		service = NSXPCConnection(serviceName: "com.vakesz.glasstual.IRCConnectionHost")
		service.remoteObjectInterface = RemoteConnectionInterface.server()
		service.exportedInterface = RemoteConnectionInterface.client()
		service.exportedObject = shim
		service.resume()

		guard let host = service.remoteObjectProxy as? RemoteConnectionServerProtocol else {
			service.invalidate()
			throw LoopbackServerError.peerNeverArrived
		}

		self.host = host
		iterator = events.makeAsyncIterator()
		deadline = Task {
			try? await Task.sleep(for: timeout, clock: .continuous)
			continuation.finish()
		}

		host.open(with: ConnectionConfigEnvelope(config: config))
	}

	func finish() {
		deadline.cancel()
		host.close()
		service.invalidate()
	}

	/// Reads events up to and including the first `stop` accepts.
	@discardableResult
	mutating func events(
		until description: String,
		_ stop: (WebSocketHostEvent) -> Bool
	) async throws -> [WebSocketHostEvent] {
		var read: [WebSocketHostEvent] = []

		while let event = await iterator.next(isolation: #isolation) {
			log.append(event)
			read.append(event)

			if stop(event) {
				return read
			}
		}

		throw LoopbackServerError.timedOut(description)
	}

	/// Reads events until the upgrade is reported, answering any trust prompt
	/// with `trusting`.
	mutating func untilNegotiated(trusting: Bool = true) async throws -> String? {
		let events = try await events(until: "the upgrade") { event in
			if case let .requestTrust(answer) = event {
				answer(trusting)
			}

			return if case .didNegotiate = event {
				true
			} else {
				event.isDisconnect
			}
		}

		guard case let .didNegotiate(subprotocol)? = events.last else {
			throw LoopbackServerError.timedOut("the upgrade, before \(events)")
		}

		return subprotocol
	}

	/// The lines received until `count` have arrived, and how many batches
	/// they came in.
	mutating func lines(count: Int) async throws -> (lines: [Data], batches: Int) {
		var lines: [Data] = []
		var batches = 0

		try await events(until: "\(count) lines") { event in
			if case let .didReceive(batch) = event {
				lines.append(contentsOf: batch)
				batches += 1
			}

			return lines.count >= count || event.isDisconnect
		}

		return (lines, batches)
	}

	/// What the host reported on its way to a disconnect.
	struct Disconnection {
		var lines: [String] = []
		var error: NSError?
		var closedReadStream = false
	}

	/// Reads to the disconnect, collecting the lines received on the way and
	/// the error it carried.
	mutating func untilDisconnected() async throws -> Disconnection {
		let events = try await events(until: "the disconnect") { $0.isDisconnect }
		var outcome = Disconnection()

		for event in events {
			switch event {
			case let .didReceive(batch):
				outcome.lines.append(contentsOf: WebSocketLoopbackTests.strings(batch))
			case .didCloseReadStream:
				outcome.closedReadStream = true
			case let .didDisconnect(disconnectError):
				outcome.error = disconnectError as NSError?
			default:
				break
			}
		}

		return outcome
	}

	func send(_ line: String) {
		host.send(Data((line + "\r\n").utf8))
	}
}

/** WebSocket connections through the real XPC service against a loopback
 server that speaks RFC 6455 from its own framing, so what the host put on the
 wire is checked byte for byte. */
@Suite("WebSocket transport over loopback", .serialized)
nonisolated struct WebSocketLoopbackTests {
	static func config(
		port: UInt16,
		secure: Bool = false,
		address: String = "127.0.0.1",
		path: String = "/",
		offering subprotocols: [WebSocketSubprotocol] = [.text, .binary]
	) -> ConnectionConfig {
		var config = ConnectionConfig()
		config.serverAddress = address
		config.serverPort = port
		config.connectionPrefersSecuredConnection = secure
		config.connectionShouldValidateCertificateChain = true
		config.transport = .webSocket(WebSocketTransportOptions(path: path, subprotocols: subprotocols))

		return config
	}

	static func strings(_ lines: [Data]) -> [String] {
		lines.map { String(bytes: $0, encoding: .utf8) ?? "<not UTF-8: \($0.count) bytes>" }
	}

	static func closeCode(of frame: LoopbackWebSocketFraming.ClientFrame) -> UInt16? {
		guard frame.opcode == 0x8, frame.payload.count >= 2 else { return nil }

		return UInt16(frame.payload[frame.payload.startIndex]) << 8 | UInt16(frame.payload[frame.payload.startIndex + 1])
	}

	static func isClose(_ frame: LoopbackWebSocketFraming.ClientFrame) -> Bool {
		frame.opcode == 0x8
	}

	// MARK: - Subprotocols and framing

	@Test("text.ircv3.net: a minimal upgrade, one masked text message per line, and lines without terminators")
	@concurrent
	func textSubprotocol() async throws {
		let server = try LoopbackWebSocketServer(secure: false)
		let port = try await server.start()
		var harness = try WebSocketHostHarness(config: Self.config(port: port, path: "/irc?x=1"))
		defer {
			harness.finish()
			Task { await server.stop() }
		}

		#expect(try await harness.untilNegotiated() == "text.ircv3.net")

		let opening = harness.log.compactMap { event -> String? in
			switch event {
			case .didConnect: "connect"
			case .didNegotiate: "negotiate"
			case .didReceive: "receive"
			default: nil
			}
		}
		#expect(opening == ["connect", "negotiate"])

		let head = try await server.upgradeRequest()
		#expect(head.hasPrefix("GET /irc?x=1 HTTP/1.1\r\n"))
		#expect(LoopbackWebSocketFraming.header("Host", in: head) == "127.0.0.1:\(port)")
		#expect(LoopbackWebSocketFraming.offeredSubprotocols(in: head) == ["text.ircv3.net", "binary.ircv3.net"])
		#expect(LoopbackWebSocketFraming.header("Sec-WebSocket-Extensions", in: head) == nil)
		#expect(LoopbackWebSocketFraming.header("Origin", in: head) == nil)
		#expect(LoopbackWebSocketFraming.header("Cookie", in: head) == nil)

		harness.send("NICK tester")
		harness.send("USER tester 0 * :Tester")

		let frames = try await server.frames(count: 2)
		#expect(frames.map(\.opcode) == [0x1, 0x1])
		#expect(frames.allSatisfy { $0.isMasked && $0.isFinal })
		#expect(Self.strings(frames.map(\.payload)) == ["NICK tester", "USER tester 0 * :Tester"])

		try await server.send(LoopbackWebSocketFraming.text(":s 001 tester :one") + LoopbackWebSocketFraming.text(":s 002 tester :two\r\n"))

		let received = try await harness.lines(count: 2)
		#expect(Self.strings(received.lines) == [":s 001 tester :one", ":s 002 tester :two"])
	}

	@Test("binary.ircv3.net: bytes in either direction are passed through untouched")
	@concurrent
	func binarySubprotocol() async throws {
		let server = try LoopbackWebSocketServer(secure: false)
		let port = try await server.start()
		var harness = try WebSocketHostHarness(config: Self.config(port: port, offering: [.binary, .text]))
		defer {
			harness.finish()
			Task { await server.stop() }
		}

		#expect(try await harness.untilNegotiated() == "binary.ircv3.net")

		let latin1 = Data("PRIVMSG #a :caf".utf8) + Data([0xE9])
		harness.host.send(latin1 + Data([0x0D, 0x0A]))

		let frame = try #require(try await server.frames(count: 1).first)
		#expect(frame.opcode == 0x2)
		#expect(frame.payload == latin1)

		try await server.send(LoopbackWebSocketFraming.serverFrame(0x2, Data(":s NOTICE a :".utf8) + Data([0xE9, 0xFF])))

		let received = try await harness.lines(count: 1)
		#expect(received.lines == [Data(":s NOTICE a :".utf8) + Data([0xE9, 0xFF])])
	}

	@Test("No subprotocol: the callback reports none, messages are split into lines, and lines go out as text without CRLF")
	@concurrent
	func noSubprotocol() async throws {
		let server = try LoopbackWebSocketServer(secure: false, choosingSubprotocol: { _ in nil })
		let port = try await server.start()
		var harness = try WebSocketHostHarness(config: Self.config(port: port))
		defer {
			harness.finish()
			Task { await server.stop() }
		}

		#expect(try await harness.untilNegotiated() == nil)
		#expect(harness.log.contains {
			if case .didNegotiate(nil) = $0 {
				true
			} else {
				false
			}
		})

		harness.send("NICK tester")

		let frame = try #require(try await server.frames(count: 1).first)
		#expect(frame.opcode == 0x1)
		#expect(Self.strings([frame.payload]) == ["NICK tester"])

		try await server.send(LoopbackWebSocketFraming.text(":s 001 tester :one\r\n:s 002 tester :two\r\n"))

		let received = try await harness.lines(count: 2)
		#expect(Self.strings(received.lines) == [":s 001 tester :one", ":s 002 tester :two"])
	}

	@Test("A server ping is answered with a pong carrying its payload")
	@concurrent
	func pingIsAnswered() async throws {
		let server = try LoopbackWebSocketServer(secure: false)
		let port = try await server.start()
		var harness = try WebSocketHostHarness(config: Self.config(port: port))
		defer {
			harness.finish()
			Task { await server.stop() }
		}

		_ = try await harness.untilNegotiated()
		try await server.send(LoopbackWebSocketFraming.serverFrame(0x9, Data("token".utf8)))

		let pong = try await server.frame { $0.opcode == 0xA }
		#expect(pong.payload == Data("token".utf8))
		#expect(pong.isMasked)
	}

	// MARK: - TLS

	@Test("wss: the trust prompt guards the upgrade, and an accepted certificate reports what was negotiated")
	@concurrent
	func secureTrustAccepted() async throws {
		let server = try LoopbackWebSocketServer(secure: true)
		let port = try await server.start()
		var harness = try WebSocketHostHarness(config: Self.config(port: port, secure: true, address: "localhost"))
		defer {
			harness.finish()
			Task { await server.stop() }
		}

		#expect(try await harness.untilNegotiated(trusting: true) == "text.ircv3.net")
		#expect(harness.log.contains {
			if case .requestTrust = $0 {
				true
			} else {
				false
			}
		})

		let events = try await harness.events(until: "the secured event") {
			if case .didSecure = $0 {
				true
			} else {
				$0.isDisconnect
			}
		}
		guard case let .didSecure(protocolVersion, cipherSuite)? = events.last else {
			Issue.record("the connection never reported itself secured")
			return
		}

		#expect(protocolVersion.rawValue >= SecureTransportSupport.minimumProtocolType.rawValue)
		#expect(cipherSuite != tlsCipherSuiteUnknown)
		#expect(try await LoopbackWebSocketFraming.header("Host", in: server.upgradeRequest()) == "localhost:\(port)")
	}

	@Test("wss: a declined certificate fails the dial before any upgrade request is sent")
	@concurrent
	func secureTrustDeclined() async throws {
		let server = try LoopbackWebSocketServer(secure: true)
		let port = try await server.start()
		var harness = try WebSocketHostHarness(config: Self.config(port: port, secure: true))
		defer {
			harness.finish()
			Task { await server.stop() }
		}

		_ = try await harness.events(until: "the trust prompt") { event in
			if case let .requestTrust(answer) = event {
				answer(false)
				return true
			}
			return event.isDisconnect
		}

		let outcome = try await harness.untilDisconnected()
		let error = try #require(outcome.error)
		#expect(error.domain == connectionErrorDomain)
		#expect(error.code == Int(ConnectionErrorCode.badCertificate.rawValue))
		#expect(harness.log.contains {
			if case .didConnect = $0 {
				true
			} else {
				false
			}
		} == false)
		#expect(await server.requestHead == nil)
	}

	@Test("wss under STS: an untrusted certificate fails without a prompt and without a second dial")
	@concurrent
	func secureUnderSTS() async throws {
		let server = try LoopbackWebSocketServer(secure: true)
		let port = try await server.start()
		var config = Self.config(port: port, secure: true)
		config.connectionRequiresTrustedCertificate = true
		var harness = try WebSocketHostHarness(config: config)
		defer {
			harness.finish()
			Task { await server.stop() }
		}

		let outcome = try await harness.untilDisconnected()
		let error = try #require(outcome.error)
		#expect(error.code == Int(ConnectionErrorCode.badCertificate.rawValue))
		#expect(harness.log.contains {
			if case .requestTrust = $0 {
				true
			} else {
				false
			}
		} == false)
		#expect(await server.requestHead == nil)
		#expect(try await server.dialsArrived() == 1)
	}

	@Test("wss: a configured client identity that cannot be found fails closed")
	@concurrent
	func missingClientIdentityFailsClosed() async throws {
		let server = try LoopbackWebSocketServer(secure: true)
		let port = try await server.start()
		var config = Self.config(port: port, secure: true)
		config.identityClientSideCertificate = Data([0, 1, 2])
		var harness = try WebSocketHostHarness(config: config)
		defer {
			harness.finish()
			Task { await server.stop() }
		}

		let outcome = try await harness.untilDisconnected()
		#expect(outcome.error != nil)
		#expect(harness.log.contains {
			if case .didConnect = $0 {
				true
			} else {
				false
			}
		} == false)
		#expect(await server.requestHead == nil)
	}

	// MARK: - Closing

	@Test("A normal close delivers every line sent before it, then disconnects cleanly and is answered")
	@concurrent
	func normalCloseDeliversEarlierLines() async throws {
		let server = try LoopbackWebSocketServer(secure: false)
		let port = try await server.start()
		var harness = try WebSocketHostHarness(config: Self.config(port: port))
		defer {
			harness.finish()
			Task { await server.stop() }
		}

		_ = try await harness.untilNegotiated()

		var burst = Data()
		for index in 0 ..< 200 {
			burst.append(LoopbackWebSocketFraming.text(":s NOTICE * :line \(index)"))
		}
		burst.append(LoopbackWebSocketFraming.text("ERROR :Closing link"))
		burst.append(LoopbackWebSocketFraming.close(code: 1000))
		try await server.send(burst)

		let outcome = try await harness.untilDisconnected()
		#expect(outcome.lines == (0 ..< 200).map { ":s NOTICE * :line \($0)" } + ["ERROR :Closing link"])
		#expect(outcome.closedReadStream)
		#expect(outcome.error == nil)

		let answer = try await server.frame(where: Self.isClose)
		#expect(Self.closeCode(of: answer) == 1000)
	}

	@Test("An error close reports its code and a sanitized reason")
	@concurrent
	func errorCloseReportsCodeAndReason() async throws {
		let server = try LoopbackWebSocketServer(secure: false)
		let port = try await server.start()
		var harness = try WebSocketHostHarness(config: Self.config(port: port))
		defer {
			harness.finish()
			Task { await server.stop() }
		}

		_ = try await harness.untilNegotiated()
		try await server.send(LoopbackWebSocketFraming.text("before") + LoopbackWebSocketFraming.close(
			code: 4000,
			reason: "bye\u{202E}\r\n!"
		))

		let outcome = try await harness.untilDisconnected()
		#expect(outcome.lines == ["before"])
		#expect(outcome.closedReadStream == false)

		let error = try #require(outcome.error)
		#expect(error.domain == connectionErrorDomain)
		#expect(error.code == Int(ConnectionErrorCode.other.rawValue))
		#expect(error.localizedDescription.contains("4000"))
		#expect(error.localizedDescription.contains("bye!"))
		#expect(error.localizedDescription.contains("\u{202E}") == false)
		#expect(error.localizedDescription.contains("\n") == false)

		let answer = try await server.frame(where: Self.isClose)
		#expect(Self.closeCode(of: answer) == 4000)
	}

	@Test("A message over 16 KiB fails the connection after the lines before it, with close code 1009")
	@concurrent
	func oversizedMessageFailsTheConnection() async throws {
		let server = try LoopbackWebSocketServer(secure: false)
		let port = try await server.start()
		var harness = try WebSocketHostHarness(config: Self.config(port: port))
		defer {
			harness.finish()
			Task { await server.stop() }
		}

		_ = try await harness.untilNegotiated()
		try await server.send(
			LoopbackWebSocketFraming.text("before")
				+ LoopbackWebSocketFraming.serverFrame(0x1, Data(repeating: 0x61, count: 16 * 1024 + 1))
		)

		let outcome = try await harness.untilDisconnected()
		#expect(outcome.lines == ["before"])
		#expect(try #require(outcome.error).code == Int(ConnectionErrorCode.other.rawValue))
		#expect(try await Self.closeCode(of: server.frame(where: Self.isClose)) == 1009)
	}

	@Test("A negotiated message carrying two lines fails the connection after the lines before it, with close code 1002")
	@concurrent
	func smuggledLineFailsTheConnection() async throws {
		let server = try LoopbackWebSocketServer(secure: false)
		let port = try await server.start()
		var harness = try WebSocketHostHarness(config: Self.config(port: port))
		defer {
			harness.finish()
			Task { await server.stop() }
		}

		_ = try await harness.untilNegotiated()
		try await server.send(
			LoopbackWebSocketFraming.text("one") + LoopbackWebSocketFraming.text("two")
				+ LoopbackWebSocketFraming.text("PING :x\nQUIT :smuggled")
		)

		let outcome = try await harness.untilDisconnected()
		#expect(outcome.lines == ["one", "two"])
		#expect(try #require(outcome.error).code == Int(ConnectionErrorCode.other.rawValue))
		#expect(try await Self.closeCode(of: server.frame(where: Self.isClose)) == 1002)
	}

	@Test("A refused upgrade names the HTTP status and never reports a connection")
	@concurrent
	func refusedUpgrade() async throws {
		let server = try LoopbackWebSocketServer(secure: false, rejectingWith: 404)
		let port = try await server.start()
		var harness = try WebSocketHostHarness(config: Self.config(port: port))
		defer {
			harness.finish()
			Task { await server.stop() }
		}

		let outcome = try await harness.untilDisconnected()
		let error = try #require(outcome.error)
		#expect(error.code == Int(ConnectionErrorCode.other.rawValue))
		#expect(error.localizedDescription.contains("404"))
		#expect(harness.log.contains {
			if case .didConnect = $0 {
				true
			} else {
				false
			}
		} == false)
	}

	@Test("Closing an open WebSocket sends a normal close within two seconds and disconnects cleanly")
	@concurrent
	func ownerCloseSendsNormalClosure() async throws {
		let server = try LoopbackWebSocketServer(secure: false)
		let port = try await server.start()
		var harness = try WebSocketHostHarness(config: Self.config(port: port))
		defer {
			harness.finish()
			Task { await server.stop() }
		}

		_ = try await harness.untilNegotiated()
		harness.host.close()

		let close = try await server.frame(timeout: .seconds(2), where: Self.isClose)
		#expect(Self.closeCode(of: close) == 1000)
		#expect(close.isMasked)

		let outcome = try await harness.untilDisconnected()
		#expect(outcome.error == nil)
	}

	// MARK: - Flow control

	@Test("A 5,000-line burst arrives in order and in far fewer batches than lines")
	@concurrent
	func burstIsBatched() async throws {
		let server = try LoopbackWebSocketServer(secure: false)
		let port = try await server.start()
		var harness = try WebSocketHostHarness(config: Self.config(port: port))
		defer {
			harness.finish()
			Task { await server.stop() }
		}

		_ = try await harness.untilNegotiated()

		let expected = (0 ..< 5000).map { ":s PRIVMSG #a :burst \($0)" }
		var burst = Data()
		for line in expected {
			burst.append(LoopbackWebSocketFraming.text(line))
		}
		try await server.send(burst)

		let received = try await harness.lines(count: expected.count)
		#expect(Self.strings(received.lines) == expected)
		#expect(received.batches < expected.count / 10, "\(received.batches) batches for \(expected.count) lines")
	}

	// MARK: - Proxies

	@Test("Through SOCKS5 the proxy is given the name, never a locally resolved address")
	@concurrent
	func socks5PassesTheHostname() async throws {
		let server = try LoopbackWebSocketServer(secure: false)
		let port = try await server.start()
		let relay = try LoopbackSOCKS5Relay(forwardingTo: port)
		let relayPort = try await relay.start()

		var config = Self.config(port: port, address: "irc.websocket.invalid")
		config.proxyType = .socks5
		config.proxyAddress = "127.0.0.1"
		config.proxyPort = relayPort
		var harness = try WebSocketHostHarness(config: config)
		defer {
			harness.finish()
			Task {
				await relay.stop()
				await server.stop()
			}
		}

		#expect(try await harness.untilNegotiated() == "text.ircv3.net")
		#expect(harness.log.contains {
			if case .willConnectToProxy("127.0.0.1", relayPort) = $0 {
				true
			} else {
				false
			}
		})
		#expect(await relay.requests == [LoopbackSOCKS5Relay.Request(addressType: 0x03, host: "irc.websocket.invalid", port: port)])
		#expect(try await LoopbackWebSocketFraming.header("Host", in: server.upgradeRequest()) == "irc.websocket.invalid:\(port)")

		try await server.send(LoopbackWebSocketFraming.text(":s 001 tester :through"))
		#expect(try await Self.strings(harness.lines(count: 1).lines) == [":s 001 tester :through"])
	}

	@Test("Through an HTTP CONNECT proxy the tunnel is requested for the configured name and port")
	@concurrent
	func httpConnectTunnels() async throws {
		let server = try LoopbackWebSocketServer(secure: false)
		let port = try await server.start()
		let relay = try LoopbackHTTPConnectRelay(forwardingTo: port)
		let relayPort = try await relay.start()

		var config = Self.config(port: port, address: "irc.websocket.invalid")
		config.proxyType = .HTTP
		config.proxyAddress = "127.0.0.1"
		config.proxyPort = relayPort
		var harness = try WebSocketHostHarness(config: config)
		defer {
			harness.finish()
			Task {
				await relay.stop()
				await server.stop()
			}
		}

		#expect(try await harness.untilNegotiated() == "text.ircv3.net")
		#expect(await relay.requestLines == ["CONNECT irc.websocket.invalid:\(port) HTTP/1.1"])

		harness.send("NICK tester")
		#expect(try await Self.strings(server.frames(count: 1).map(\.payload)) == ["NICK tester"])
	}
}
