// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
@testable import Glasstual
import Security
import Testing

@Suite("Inbound connection delivery", .timeLimit(.minutes(1)))
@MainActor
struct ConnectionInboundDeliveryTests {
	@Test("A missing XPC service ends startup explicitly")
	func unavailableConnectionService() async throws {
		let session = TestServerSession()
		session.isConnecting = true
		let connection = Connection(config: ConnectionConfig(), onSession: session, closeClock: .continuous,
		                            makeService: { NSXPCConnection(serviceName: "test.glasstual.unavailable-service") })
		session.socket = connection
		connection.open()
		let deadline = ContinuousClock.now + .seconds(5)
		while session.socket != nil, ContinuousClock.now < deadline {
			try await Task.sleep(for: .milliseconds(10))
		}
		#expect(session.socket == nil)
		#expect(!session.isConnecting)
	}

	@Test("TLS publishes sidebar and title before 001, even for unknown cipher descriptions")
	func securityCallbackRefreshesBeforeRegistration() async {
		let (session, connection) = connectedSession()
		connection.callbackReceiver.didSecureConnection(
			withProtocolType: tlsProtocolVersionUnknown,
			cipherSuite: tlsCipherSuiteUnknown
		)
		for _ in 0 ..< 100 where session.recordedOutput.reloadedItems.isEmpty {
			await Task.yield()
		}
		#expect(connection.isSecured)
		#expect(session.isLoggedIn == false)
		#expect(session.recordedOutput.reloadedItems.contains { $0 === session })
		#expect(session.recordedOutput.titleUpdates.contains { $0 === session })
	}

	@Test("Final ERROR prints before the ordered EOF and disconnect callbacks")
	func finalErrorBeforeEOF() async throws {
		let (session, connection) = connectedSession()
		let receiver = connection.callbackReceiver
		try await observe(.serverSessionDidDisconnect, from: session) {
			receiver.didReceive([Data("ERROR :Final rejection".utf8)]) {}
			receiver.didCloseReadStream()
			receiver.didDisconnect(withError: nil)
		}
		let bodies = session.printedLines.compactMap { ($0 as? [String: Any])?["messageBody"] as? String }
		#expect(bodies.first?.contains("Final rejection") == true)
		#expect(session.socket == nil)
	}

	/// The application used to hold a bounded queue of its own between the host
	/// and the main actor, and a burst past 8,192 lines — a `/LIST` on a large
	/// network, a bouncer's playback — overflowed it and tore the connection
	/// down. The host now waits for each read to be acknowledged, so however
	/// much arrives, all of it is handled and the connection stays up.
	@Test("A burst larger than the old application queue is handled in full without a disconnect")
	func largeBurstIsDeliveredWithoutOverload() async throws {
		let (session, connection) = connectedSession()
		let burst = (0 ..< 10000).map { Data("PING :\($0)".utf8) }

		try await deliver(burst, to: connection.callbackReceiver)

		#expect(session.sentLines as? [String] == (0 ..< 10000).map { "PONG \($0)" })
		#expect(session.socket === connection)
	}

	@Test("A read is acknowledged only after every one of its lines was handled")
	func acknowledgementFollowsTheLastLine() async throws {
		let (session, connection) = connectedSession()
		let receiver = connection.callbackReceiver

		try await deliver((0 ..< 200).map { Data("PING :first-\($0)".utf8) }, to: receiver)
		#expect(session.sentLines.count == 200)

		try await deliver([Data("PING :second".utf8)], to: receiver)
		#expect(session.sentLines.lastObject as? String == "PONG second")
	}

	/// The host reads nothing more until it hears back, so a read that lands
	/// after the session moved on must still be answered.
	@Test("A read for a connection the session no longer owns is acknowledged without being handled")
	func retiredConnectionStillAcknowledges() async throws {
		let (session, _) = connectedSession()
		let retired = Connection(config: ConnectionConfig(), onSession: session)

		try await deliver([Data("PING :stale".utf8)], to: retired.callbackReceiver)

		#expect(session.sentLines.count == 0)
	}

	@Test("Wire STS preserves pending and keychain PASS through reset", arguments: [true, false])
	func stsPreservesEndpointPassword(_ storedInKeychain: Bool) async throws {
		let (session, _) = connectedSession()
		defer { session.stopAllTimers() }
		var origin = ServerEndpoint(serverAddress: "sts-test.invalid", pendingServerPassword: .set("endpoint-secret"))
		defer { origin.keychainItem.delete() }
		if storedInKeychain {
			try await KeychainWriter.shared.apply([origin.keychainItem: origin.pendingServerPassword])
			origin.pendingServerPassword = .unchanged
			try #require(origin.serverPasswordFromKeychain == "endpoint-secret")
		}
		session.config.serverList = [origin]
		session.server = origin
		let stored = await KeychainSecretLoader.passwords(for: [origin.keychainItem])
		session.sessionCredentials.install(stored, items: [origin.keychainItem], applying: session.config.pendingKeychainEdits)
		var config = ConnectionConfig()
		config.serverAddress = origin.serverAddress
		config.serverPort = 6667
		let plain = Connection(config: config, onSession: session)
		session.socket = plain
		try await observe(.serverSessionDidConnect, from: session) {
			plain.callbackReceiver.didConnect(toHost: origin.serverAddress)
		}
		try #require(plain.isConnected)
		session.sentLines.removeAllObjects()
		session.connectionDidReceive("CAP * LS :sts=port=6697")
		try #require(session.isDisconnecting)
		#expect(plain.isDisconnecting)
		// Invoke the actual registered action while connect is guarded. This
		// exercises its captured origin without launching a network service.
		session.invokeDisconnectCallbacks()
		let pending = try #require(session.pendingEndpoint)
		#expect(pending.reason == .stsUpgrade)
		#expect(pending.origin?.uniqueIdentifier == origin.uniqueIdentifier)
		session.retiredServerKeychainItems.insert(origin.keychainItem)
		session.resetAllPropertyValues()
		let endpoint = try #require(session.takeConnectionEndpoint())
		#expect(endpoint.serverAddress == origin.serverAddress)
		#expect(endpoint.serverPort == 6697)
		#expect(endpoint.connectionPrefersSecuredConnection)
		#expect(session.server?.uniqueIdentifier == origin.uniqueIdentifier)
		let secured = Connection(config: endpoint, onSession: session)
		session.socket = secured
		try await observe(.serverSessionDidConnect, from: session) {
			secured.callbackReceiver.didConnect(toHost: endpoint.serverAddress)
		}
		let passwords = session.sentLines.compactMap { $0 as? String }.filter { $0.hasPrefix("PASS ") }
		let expectedPassword = try SendingMessage.string(command: .pass, arguments: ["endpoint-secret"])
		#expect(passwords == [expectedPassword])
	}

	@Test("Same-host STS requires an origin match and /conn never inherits endpoint secrets")
	func endpointCredentialPolicies() {
		let origin = ServerEndpoint(serverAddress: "origin.invalid", pendingServerPassword: .set("secret"))
		#expect(PendingIRCEndpoint(host: "ORIGIN.invalid", port: 6697, secured: true, origin: origin, reason: .stsUpgrade)
			.credentialEndpoint == origin)
		#expect(PendingIRCEndpoint(host: "other.invalid", port: 6697, secured: true, origin: origin, reason: .stsUpgrade)
			.credentialEndpoint == nil)
		#expect(PendingIRCEndpoint(host: "origin.invalid", port: 6667, secured: false, origin: origin, reason: .userCommand)
			.credentialEndpoint == nil)
	}

	@Test("Redirect and /conn endpoint policies never carry another endpoint's PASS")
	func redirectCredentialsStaySeparate() async throws {
		let (session, socket) = connectedSession()
		defer { session.stopAllTimers() }
		let origin = ServerEndpoint(serverAddress: "origin.invalid", pendingServerPassword: .set("do-not-forward"))
		session.config.serverList = [origin]
		session.server = origin
		try await observe(.serverSessionDidConnect, from: session) {
			socket.callbackReceiver.didConnect(toHost: origin.serverAddress)
		}
		try #require(socket.isConnected)
		#expect(session.sentLines.compactMap { $0 as? String }.contains { $0.hasPrefix("PASS ") })
		session.sentLines.removeAllObjects()
		session.connectionDidReceive(":server 010 me redirect.invalid 6668 :Try another server")
		try #require(session.isDisconnecting)
		#expect(socket.isDisconnecting)
		session.invokeDisconnectCallbacks()
		let pending = try #require(session.pendingEndpoint)
		#expect(pending.reason == .serverRedirect)
		session.resetAllPropertyValues()
		let endpoint = try #require(session.takeConnectionEndpoint())
		#expect(endpoint.serverAddress == "redirect.invalid")
		#expect(endpoint.serverPort == 6668)
		#expect(session.server == nil)
		let redirected = Connection(config: endpoint, onSession: session)
		session.socket = redirected
		try await observe(.serverSessionDidConnect, from: session) {
			redirected.callbackReceiver.didConnect(toHost: endpoint.serverAddress)
		}
		#expect(session.sentLines.compactMap { $0 as? String }.contains { $0.hasPrefix("PASS ") } == false)
	}

	/// Once the upgrade is decided the plaintext socket is being abandoned, and
	/// anything negotiated on it goes to a server the session resolved not to
	/// talk to in clear.
	@Test("An STS upgrade negotiates nothing more on the plaintext socket")
	func stsUpgradeAbandonsNegotiation() async throws {
		let (session, _) = connectedSession()
		defer { session.stopAllTimers() }
		let origin = ServerEndpoint(serverAddress: "sts-abandon-test.invalid")
		session.config.serverList = [origin]
		session.server = origin
		var config = ConnectionConfig()
		config.serverAddress = origin.serverAddress
		config.serverPort = 6667
		let plain = Connection(config: config, onSession: session)
		session.socket = plain
		try await observe(.serverSessionDidConnect, from: session) {
			plain.callbackReceiver.didConnect(toHost: origin.serverAddress)
		}
		session.sentCapabilityCommands.removeAllObjects()

		session.connectionDidReceive("CAP * LS :sts=port=6697 multi-prefix server-time")

		try #require(session.isDisconnecting)
		#expect(session.sentCapabilityCommands.count == 0)
	}

	/// A redirect is server-controlled input; one that could turn TLS off would
	/// hand the registration credentials to whoever answers in clear.
	@Test("A redirect is as encrypted as the session it replaces", arguments: [true, false])
	func redirectKeepsTransportSecurity(_ secured: Bool) async throws {
		let (session, _) = connectedSession()
		defer { session.stopAllTimers() }
		let origin = ServerEndpoint(serverAddress: "origin.invalid", prefersSecuredConnection: secured)
		session.config.serverList = [origin]
		var config = ConnectionConfig()
		config.serverAddress = origin.serverAddress
		config.connectionPrefersSecuredConnection = secured
		let socket = Connection(config: config, onSession: session)
		session.socket = socket
		try await observe(.serverSessionDidConnect, from: session) {
			socket.callbackReceiver.didConnect(toHost: origin.serverAddress)
		}

		session.connectionDidReceive(":server 010 me redirect.invalid 6667 :Try another server")
		try #require(session.isDisconnecting)
		session.invokeDisconnectCallbacks()

		let pending = try #require(session.pendingEndpoint)
		#expect(pending.secured == secured)
		session.resetAllPropertyValues()
		let endpoint = try #require(session.takeConnectionEndpoint())
		#expect(endpoint.serverAddress == "redirect.invalid")
		#expect(endpoint.connectionPrefersSecuredConnection == secured)
	}

	/// After 001 the session has a session worth keeping; a 010 then is shown,
	/// not obeyed.
	@Test("A redirect after registration is not followed")
	func redirectAfterRegistrationIsIgnored() {
		let (session, _) = connectedSession()
		session.markAsLoggedIn()

		session.connectionDidReceive(":server 010 me redirect.invalid 6697 :Try another server")

		#expect(session.isDisconnecting == false)
		#expect(session.pendingEndpoint == nil)
		#expect(session.disconnectType != .serverRedirect)
	}

	@Test("/conn keeps the encryption of the session it replaces", arguments: [true, false])
	func connectCommandKeepsTransportSecurity(_ secured: Bool) {
		let session = TestServerSession()
		var config = ConnectionConfig()
		config.connectionPrefersSecuredConnection = secured
		session.socket = Connection(config: config, onSession: session)

		let endpoint = session.connectCommandEndpoint(host: "other.invalid")

		#expect(endpoint.secured == secured)
		#expect(endpoint.port == (secured ? ConnectionDefaults.serverPortSecure : ConnectionDefaults.serverPort))
		#expect(endpoint.credentialEndpoint == nil)
	}

	@Test("With no socket, /conn follows the server entry the session connects to", arguments: [true, false])
	func connectCommandFollowsTheServerEntry(_ secured: Bool) {
		let session = TestServerSession()
		session.config.serverList = [ServerEndpoint(serverAddress: "origin.invalid", prefersSecuredConnection: secured)]

		#expect(session.connectCommandEndpoint(host: "other.invalid").secured == secured)
	}

	private func connectedSession() -> (TestServerSession, Connection) {
		let session = TestServerSession()
		session.forwardsProcessedMessages = true
		session.isConnected = true
		let connection = Connection(config: ConnectionConfig(), onSession: session)
		session.socket = connection
		return (session, connection)
	}

	/// Hands `lines` to `receiver` as one read and waits for the reply the host
	/// would be waiting on.
	private func deliver(_ lines: [Data], to receiver: any RemoteConnectionClientProtocol) async throws {
		let (acknowledgements, acknowledge) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingOldest(1))
		receiver.didReceive(lines) {
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
		_ name: Notification.Name, from session: ServerSession, performing action: () -> Void
	) async throws {
		let (events, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingOldest(1))
		let observer = NotificationCenter.default.addObserver(forName: name, object: session, queue: nil) { _ in
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
	/// the session answers the lines in the order the server sent them.
	@Test("Lines are answered in the order the connection delivered them")
	func answersInWireOrder() {
		let (session, _) = connectedSession()

		for token in ["one", "two", "three"] {
			session.connectionDidReceive("PING :\(token)")
		}

		#expect(session.sentLines as? [String] == ["PONG one", "PONG two", "PONG three"])
	}

	/// A reconnect replaces the socket. Lines that were already in flight on the
	/// retired connection must not act on the new session, which is why the
	/// connection checks that the session still owns it before delivering.
	@Test("A line from a connection the session no longer owns is dropped")
	func ignoresRetiredConnection() async {
		let (session, _) = connectedSession()
		let retired = Connection(config: ConnectionConfig(), onSession: session)

		retired.callbackReceiver.didReceive([Data("PING :stale".utf8)]) {}
		await settle()

		#expect(session.sentLines.count == 0)
	}

	@Test("Empty data is not treated as a line")
	func ignoresEmptyData() {
		let (session, _) = connectedSession()

		session.connectionDidReceive("")

		#expect(session.sentLines.count == 0)
	}

	@Test("Terminating sessions cannot schedule another connection or reconnect timer")
	func terminationRejectsScheduledConnections() {
		let session = TestServerSession()
		session.autoConnect(withDelay: 20, afterWakeUp: false)
		session.startReconnectTimer()
		let scheduled = session.pendingConnectionTask
		let rejoin = Task {}
		session.rejoinTasks["#test"] = rejoin
		session.isTerminating = true
		#expect(scheduled?.isCancelled == true)
		#expect(rejoin.isCancelled)
		#expect(session.rejoinTasks.isEmpty)
		session.autoConnect(withDelay: 20, afterWakeUp: false)
		session.startReconnectTimer()
		#expect(session.pendingConnectionTask == nil)
		#expect(session.reconnect.timer.isActive == false)
		session.cancelScheduledConnection()
		session.stopAllTimers()
	}

	@Test("A silent service is invalidated at five seconds and completes disconnect exactly once")
	func closeDeadlineCompletesExactlyOnce() async {
		let session = TestServerSession()
		let listener = NSXPCListener.anonymous()
		let (ticks, tick) = AsyncStream<Void>.makeStream()
		var waits: [TimeInterval] = []
		let clock = TimerClock(now: { .now }, wait: { interval in
			waits.append(interval)
			for await _ in ticks {
				return
			}
		})
		let connection = Connection(config: ConnectionConfig(), onSession: session, closeClock: clock) {
			NSXPCConnection(listenerEndpoint: listener.endpoint)
		}
		session.socket = connection
		session.isConnecting = true
		var completions = 0
		session.addDisconnectCallback { completions += 1 }
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
		#expect(session.socket == nil)
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
	func retiredLifecycleCallbacksAreIgnored() async {
		let (session, replacement) = connectedSession()
		let retired = Connection(config: ConnectionConfig(), onSession: session)
		var completions = 0
		session.addDisconnectCallback { completions += 1 }
		retired.callbackReceiver.didConnect(toHost: nil)
		retired.callbackReceiver.didCloseReadStream()
		retired.callbackReceiver.didDisconnect(withError: nil)
		await settle()
		#expect(session.socket === replacement)
		#expect(session.isConnected)
		#expect(completions == 0)
		#expect(session.sentLines.count == 0)
	}

	/// Lets the connection's event loop drain what was just pushed into it.
	private func settle() async {
		for _ in 0 ..< 100 {
			await Task.yield()
		}
	}
}
