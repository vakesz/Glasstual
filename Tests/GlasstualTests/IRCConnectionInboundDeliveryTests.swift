/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import Foundation
@testable import Glasstual
import Security
import Testing

@Suite("Inbound connection delivery", .timeLimit(.minutes(1)))
@MainActor
struct IRCConnectionInboundDeliveryTests {
	@Test("A missing XPC service ends startup explicitly")
	func unavailableConnectionService() async throws {
		let client = TestClient()
		client.isConnecting = true
		let connection = Connection(config: IRCConnectionConfig(), onClient: client, closeClock: .continuous,
		                            makeService: { NSXPCConnection(serviceName: "test.glasstual.unavailable-service") })
		client.socket = connection
		connection.open()
		let deadline = ContinuousClock.now + .seconds(5)
		while client.socket != nil, ContinuousClock.now < deadline {
			try await Task.sleep(for: .milliseconds(10))
		}
		#expect(client.socket == nil)
		#expect(!client.isConnecting)
	}

	@Test("TLS publishes sidebar and title before 001, even for unknown cipher descriptions")
	func securityCallbackRefreshesBeforeRegistration() async {
		let (client, connection) = connectedClient()
		connection.callbackReceiver.ircConnectionDidSecureConnection(
			withProtocolType: tlsProtocolVersionUnknown,
			cipherSuite: tlsCipherSuiteUnknown
		)
		for _ in 0 ..< 100 where client.recordedOutput.reloadedItems.isEmpty {
			await Task.yield()
		}
		#expect(connection.isSecured)
		#expect(client.isLoggedIn == false)
		#expect(client.recordedOutput.reloadedItems.contains { $0 === client })
		#expect(client.recordedOutput.titleUpdates.contains { $0 === client })
	}

	@Test("Final ERROR prints before the ordered EOF and disconnect callbacks")
	func finalErrorBeforeEOF() async throws {
		let (client, connection) = connectedClient()
		let receiver = connection.callbackReceiver
		try await observe(.IRCClientDidDisconnect, from: client) {
			receiver.ircConnectionDidReceive([Data("ERROR :Final rejection".utf8)]) {}
			receiver.ircConnectionDidCloseReadStream()
			receiver.ircConnectionDidDisconnectWithError(nil)
		}
		let bodies = client.printedLines.compactMap { ($0 as? [String: Any])?["messageBody"] as? String }
		#expect(bodies.first?.contains("Final rejection") == true)
		#expect(client.socket == nil)
	}

	/// The application used to hold a bounded queue of its own between the host
	/// and the main actor, and a burst past 8,192 lines — a `/LIST` on a large
	/// network, a bouncer's playback — overflowed it and tore the connection
	/// down. The host now waits for each read to be acknowledged, so however
	/// much arrives, all of it is handled and the connection stays up.
	@Test("A burst larger than the old application queue is handled in full without a disconnect")
	func largeBurstIsDeliveredWithoutOverload() async throws {
		let (client, connection) = connectedClient()
		let burst = (0 ..< 10000).map { Data("PING :\($0)".utf8) }

		try await deliver(burst, to: connection.callbackReceiver)

		#expect(client.sentLines as? [String] == (0 ..< 10000).map { "PONG \($0)" })
		#expect(client.socket === connection)
	}

	@Test("A read is acknowledged only after every one of its lines was handled")
	func acknowledgementFollowsTheLastLine() async throws {
		let (client, connection) = connectedClient()
		let receiver = connection.callbackReceiver

		try await deliver((0 ..< 200).map { Data("PING :first-\($0)".utf8) }, to: receiver)
		#expect(client.sentLines.count == 200)

		try await deliver([Data("PING :second".utf8)], to: receiver)
		#expect(client.sentLines.lastObject as? String == "PONG second")
	}

	/// The host reads nothing more until it hears back, so a read that lands
	/// after the client moved on must still be answered.
	@Test("A read for a connection the client no longer owns is acknowledged without being handled")
	func retiredConnectionStillAcknowledges() async throws {
		let (client, _) = connectedClient()
		let retired = Connection(config: IRCConnectionConfig(), onClient: client)

		try await deliver([Data("PING :stale".utf8)], to: retired.callbackReceiver)

		#expect(client.sentLines.count == 0)
	}

	@Test("Wire STS preserves pending and keychain PASS through reset", arguments: [true, false])
	func stsPreservesEndpointPassword(_ storedInKeychain: Bool) async throws {
		let (client, _) = connectedClient()
		defer { client.stopAllTimers() }
		var origin = Server(serverAddress: "sts-test.invalid", pendingServerPassword: .set("endpoint-secret"))
		defer { origin.keychainItem.delete() }
		if storedInKeychain {
			origin.writeServerPasswordToKeychain()
			try #require(origin.serverPasswordFromKeychain == "endpoint-secret")
		}
		client.config.serverList = [origin]
		client.server = origin
		var config = IRCConnectionConfig()
		config.serverAddress = origin.serverAddress
		config.serverPort = 6667
		let plain = Connection(config: config, onClient: client)
		client.socket = plain
		try await observe(.IRCClientDidConnect, from: client) {
			plain.callbackReceiver.ircConnectionDidConnect(toHost: origin.serverAddress)
		}
		try #require(plain.isConnected)
		client.sentLines.removeAllObjects()
		client.ircConnection(plain, didReceiveData: "CAP * LS :sts=port=6697")
		try #require(client.isDisconnecting)
		#expect(plain.isDisconnecting)
		// Invoke the actual registered action while connect is guarded. This
		// exercises its captured origin without launching a network service.
		client.invokeDisconnectCallbacks()
		let pending = try #require(client.pendingEndpoint)
		#expect(pending.reason == .stsUpgrade)
		#expect(pending.origin?.uniqueIdentifier == origin.uniqueIdentifier)
		client.retiredServerKeychainItems.insert(origin.keychainItem)
		client.resetAllPropertyValues()
		let endpoint = try #require(client.takeConnectionEndpoint())
		#expect(endpoint.serverAddress == origin.serverAddress)
		#expect(endpoint.serverPort == 6697)
		#expect(endpoint.connectionPrefersSecuredConnection)
		#expect(client.server?.uniqueIdentifier == origin.uniqueIdentifier)
		let secured = Connection(config: endpoint, onClient: client)
		client.socket = secured
		try await observe(.IRCClientDidConnect, from: client) {
			secured.callbackReceiver.ircConnectionDidConnect(toHost: endpoint.serverAddress)
		}
		let passwords = client.sentLines.compactMap { $0 as? String }.filter { $0.hasPrefix("PASS ") }
		let expectedPassword = try SendingMessage.string(command: "PASS", arguments: ["endpoint-secret"])
		#expect(passwords == [expectedPassword])
	}

	@Test("Same-host STS requires an origin match and /conn never inherits endpoint secrets")
	func endpointCredentialPolicies() {
		let origin = Server(serverAddress: "origin.invalid", pendingServerPassword: .set("secret"))
		#expect(PendingIRCEndpoint(host: "ORIGIN.invalid", port: 6697, secured: true, origin: origin, reason: .stsUpgrade)
			.credentialEndpoint == origin)
		#expect(PendingIRCEndpoint(host: "other.invalid", port: 6697, secured: true, origin: origin, reason: .stsUpgrade)
			.credentialEndpoint == nil)
		#expect(PendingIRCEndpoint(host: "origin.invalid", port: 6667, secured: false, origin: origin, reason: .userCommand)
			.credentialEndpoint == nil)
	}

	@Test("Redirect and /conn endpoint policies never carry another endpoint's PASS")
	func redirectCredentialsStaySeparate() async throws {
		let (client, socket) = connectedClient()
		defer { client.stopAllTimers() }
		let origin = Server(serverAddress: "origin.invalid", pendingServerPassword: .set("do-not-forward"))
		client.config.serverList = [origin]
		client.server = origin
		try await observe(.IRCClientDidConnect, from: client) {
			socket.callbackReceiver.ircConnectionDidConnect(toHost: origin.serverAddress)
		}
		try #require(socket.isConnected)
		#expect(client.sentLines.compactMap { $0 as? String }.contains { $0.hasPrefix("PASS ") })
		client.sentLines.removeAllObjects()
		client.ircConnection(socket, didReceiveData: ":server 010 me redirect.invalid 6668 :Try another server")
		try #require(client.isDisconnecting)
		#expect(socket.isDisconnecting)
		client.invokeDisconnectCallbacks()
		let pending = try #require(client.pendingEndpoint)
		#expect(pending.reason == .serverRedirect)
		client.resetAllPropertyValues()
		let endpoint = try #require(client.takeConnectionEndpoint())
		#expect(endpoint.serverAddress == "redirect.invalid")
		#expect(endpoint.serverPort == 6668)
		#expect(client.server == nil)
		let redirected = Connection(config: endpoint, onClient: client)
		client.socket = redirected
		try await observe(.IRCClientDidConnect, from: client) {
			redirected.callbackReceiver.ircConnectionDidConnect(toHost: endpoint.serverAddress)
		}
		#expect(client.sentLines.compactMap { $0 as? String }.contains { $0.hasPrefix("PASS ") } == false)
	}

	/// Once the upgrade is decided the plaintext socket is being abandoned, and
	/// anything negotiated on it goes to a server the client resolved not to
	/// talk to in clear.
	@Test("An STS upgrade negotiates nothing more on the plaintext socket")
	func stsUpgradeAbandonsNegotiation() async throws {
		let (client, _) = connectedClient()
		defer { client.stopAllTimers() }
		let origin = Server(serverAddress: "sts-abandon-test.invalid")
		client.config.serverList = [origin]
		client.server = origin
		var config = IRCConnectionConfig()
		config.serverAddress = origin.serverAddress
		config.serverPort = 6667
		let plain = Connection(config: config, onClient: client)
		client.socket = plain
		try await observe(.IRCClientDidConnect, from: client) {
			plain.callbackReceiver.ircConnectionDidConnect(toHost: origin.serverAddress)
		}
		client.sentCapabilityCommands.removeAllObjects()

		client.ircConnection(plain, didReceiveData: "CAP * LS :sts=port=6697 multi-prefix server-time")

		try #require(client.isDisconnecting)
		#expect(client.sentCapabilityCommands.count == 0)
	}

	/// A redirect is server-controlled input; one that could turn TLS off would
	/// hand the registration credentials to whoever answers in clear.
	@Test("A redirect is as encrypted as the session it replaces", arguments: [true, false])
	func redirectKeepsTransportSecurity(_ secured: Bool) async throws {
		let (client, _) = connectedClient()
		defer { client.stopAllTimers() }
		let origin = Server(serverAddress: "origin.invalid", prefersSecuredConnection: secured)
		client.config.serverList = [origin]
		var config = IRCConnectionConfig()
		config.serverAddress = origin.serverAddress
		config.connectionPrefersSecuredConnection = secured
		let socket = Connection(config: config, onClient: client)
		client.socket = socket
		try await observe(.IRCClientDidConnect, from: client) {
			socket.callbackReceiver.ircConnectionDidConnect(toHost: origin.serverAddress)
		}

		client.ircConnection(socket, didReceiveData: ":server 010 me redirect.invalid 6667 :Try another server")
		try #require(client.isDisconnecting)
		client.invokeDisconnectCallbacks()

		let pending = try #require(client.pendingEndpoint)
		#expect(pending.secured == secured)
		client.resetAllPropertyValues()
		let endpoint = try #require(client.takeConnectionEndpoint())
		#expect(endpoint.serverAddress == "redirect.invalid")
		#expect(endpoint.connectionPrefersSecuredConnection == secured)
	}

	/// After 001 the client has a session worth keeping; a 010 then is shown,
	/// not obeyed.
	@Test("A redirect after registration is not followed")
	func redirectAfterRegistrationIsIgnored() {
		let (client, socket) = connectedClient()
		client.markAsLoggedIn()

		client.ircConnection(socket, didReceiveData: ":server 010 me redirect.invalid 6697 :Try another server")

		#expect(client.isDisconnecting == false)
		#expect(client.pendingEndpoint == nil)
		#expect(client.disconnectType != .serverRedirect)
	}

	@Test("/conn keeps the encryption of the session it replaces", arguments: [true, false])
	func connectCommandKeepsTransportSecurity(_ secured: Bool) {
		let client = TestClient()
		var config = IRCConnectionConfig()
		config.connectionPrefersSecuredConnection = secured
		client.socket = Connection(config: config, onClient: client)

		let endpoint = client.connectCommandEndpoint(host: "other.invalid")

		#expect(endpoint.secured == secured)
		#expect(endpoint.port == (secured ? IRCConnectionDefaults.serverPortSecure : IRCConnectionDefaults.serverPort))
		#expect(endpoint.credentialEndpoint == nil)
	}

	@Test("With no socket, /conn follows the server entry the client connects to", arguments: [true, false])
	func connectCommandFollowsTheServerEntry(_ secured: Bool) {
		let client = TestClient()
		client.config.serverList = [Server(serverAddress: "origin.invalid", prefersSecuredConnection: secured)]

		#expect(client.connectCommandEndpoint(host: "other.invalid").secured == secured)
	}

	private func connectedClient() -> (TestClient, Connection) {
		let client = TestClient()
		client.forwardsProcessedMessages = true
		client.isConnected = true
		let connection = Connection(config: IRCConnectionConfig(), onClient: client)
		client.socket = connection
		return (client, connection)
	}

	/// Hands `lines` to `receiver` as one read and waits for the reply the host
	/// would be waiting on.
	private func deliver(_ lines: [Data], to receiver: any RemoteConnectionClientProtocol) async throws {
		let (acknowledgements, acknowledge) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingOldest(1))
		receiver.ircConnectionDidReceive(lines) {
			acknowledge.yield()
			acknowledge.finish()
		}
		var acknowledged = false
		for await _ in acknowledgements {
			acknowledged = true
		}
		try #require(acknowledged, "The read was never acknowledged")
	}

	/// Register before injecting callbacks, so even synchronous completion is observed.
	private func observe(
		_ name: Notification.Name, from client: IRCClient, performing action: () -> Void
	) async throws {
		let (events, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingOldest(1))
		let observer = NotificationCenter.default.addObserver(forName: name, object: client, queue: nil) { _ in
			continuation.yield()
			continuation.finish()
		}
		let deadline = Task {
			try? await Task.sleep(for: .seconds(30))
			guard !Task.isCancelled else { return }
			continuation.finish()
		}
		defer {
			deadline.cancel()
			NotificationCenter.default.removeObserver(observer)
			continuation.finish()
		}
		action()
		var observed = false
		for await _ in events {
			observed = true
			break
		}
		try #require(observed, "Connection lifecycle event did not arrive before the deadline: \(name.rawValue)")
	}

	/// The connection drains the host's callbacks through one ordered stream, so
	/// the client answers the lines in the order the server sent them.
	@Test("Lines are answered in the order the connection delivered them")
	func answersInWireOrder() {
		let (client, connection) = connectedClient()

		for token in ["one", "two", "three"] {
			client.ircConnection(connection, didReceiveData: "PING :\(token)")
		}

		#expect(client.sentLines as? [String] == ["PONG one", "PONG two", "PONG three"])
	}

	/// A reconnect replaces the socket. Lines that were already in flight on the
	/// retired connection must not act on the new session.
	@Test("A line from a connection the client no longer owns is dropped")
	func ignoresRetiredConnection() {
		let (client, _) = connectedClient()
		let retired = Connection(config: IRCConnectionConfig(), onClient: client)

		client.ircConnection(retired, didReceiveData: "PING :stale")

		#expect(client.sentLines.count == 0)
	}

	@Test("Empty data is not treated as a line")
	func ignoresEmptyData() {
		let (client, connection) = connectedClient()

		client.ircConnection(connection, didReceiveData: "")

		#expect(client.sentLines.count == 0)
	}

	@Test("Terminating clients cannot schedule another connection or reconnect timer")
	func terminationRejectsScheduledConnections() {
		let client = TestClient()
		client.autoConnect(withDelay: 20, afterWakeUp: false)
		client.startReconnectTimer()
		let scheduled = client.pendingConnectionTask
		let rejoin = Task {}
		client.rejoinTasks["#test"] = rejoin
		client.isTerminating = true
		#expect(scheduled?.isCancelled == true)
		#expect(rejoin.isCancelled)
		#expect(client.rejoinTasks.isEmpty)
		client.autoConnect(withDelay: 20, afterWakeUp: false)
		client.startReconnectTimer()
		#expect(client.pendingConnectionTask == nil)
		#expect(client.reconnectTimer.isActive == false)
		client.cancelScheduledConnection()
		client.stopAllTimers()
	}

	@Test("A silent service is invalidated at five seconds and completes disconnect exactly once")
	func closeDeadlineCompletesExactlyOnce() async {
		let client = TestClient()
		let listener = NSXPCListener.anonymous()
		let (ticks, tick) = AsyncStream<Void>.makeStream()
		var waits: [TimeInterval] = []
		let clock = TimerClock(now: { .now }, wait: { interval in
			waits.append(interval)
			for await _ in ticks {
				return
			}
		})
		let connection = Connection(config: IRCConnectionConfig(), onClient: client, closeClock: clock) {
			NSXPCConnection(listenerEndpoint: listener.endpoint)
		}
		client.socket = connection
		client.isConnecting = true
		var completions = 0
		client.addDisconnectCallback { completions += 1 }
		connection.open()
		connection.beginCloseDeadline()
		connection.close()
		connection.close()
		for _ in 0 ..< 100 where waits.isEmpty {
			await Task.yield()
		}
		#expect(waits == [5])
		#expect(completions == 0)
		tick.yield()
		for _ in 0 ..< 100 where completions == 0 {
			await Task.yield()
		}
		#expect(completions == 1)
		#expect(client.socket == nil)
		#expect(connection.isConnecting == false)
		#expect(connection.isDisconnecting == false)
		connection.open()
		connection.close()
		#expect(connection.isConnecting == false)
		#expect(completions == 1)
		tick.finish()
		listener.invalidate()
	}

	@Test("Late lifecycle callbacks cannot disconnect a replacement session")
	func retiredLifecycleCallbacksAreIgnored() {
		let (client, replacement) = connectedClient()
		let retired = Connection(config: IRCConnectionConfig(), onClient: client)
		var completions = 0
		client.addDisconnectCallback { completions += 1 }
		client.ircConnectionDidConnect(retired)
		client.ircConnectionDidCloseReadStream(retired)
		client.ircConnection(retired, didDisconnectWithError: nil)
		#expect(client.socket === replacement)
		#expect(client.isConnected)
		#expect(completions == 0)
		#expect(client.sentLines.count == 0)
	}
}
