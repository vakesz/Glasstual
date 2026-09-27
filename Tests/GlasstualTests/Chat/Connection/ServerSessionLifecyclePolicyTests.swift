// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Server session lifecycle policies")
struct ServerSessionLifecyclePolicyTests {
	@Test("Shutdown refuses new connection attempts before session teardown",
	      arguments: [SessionConnectMode.normal, .reconnect, .retry])
	func applicationShutdownPreventsConnection(_ mode: SessionConnectMode) {
		let session = TestServerSession()
		session.config.serverList = [ServerEndpoint(serverAddress: "irc.example.test", serverPort: 6697)]
		session.fixture.applicationState.applicationIsTerminating = true
		defer { session.disconnect() }

		session.connect(mode)

		#expect(session.connectionState.transport == .idle)
		#expect(session.socket == nil)
		#expect(session.printedLines.count == 0)
	}

	@Test("Shutdown during credential loading cancels the connection before opening a socket")
	func applicationShutdownDuringCredentialLoad() async throws {
		let fixture = ChatEnvironmentFixture()
		var config = ServerConfig()
		config.serverList = [ServerEndpoint(serverAddress: "127.0.0.1", serverPort: 6697)]
		let session = ServerSession(config: config, environment: fixture.environment)
		let (gate, release) = AsyncStream<Void>.makeStream()
		let (started, didStart) = AsyncStream<Void>.makeStream()
		defer {
			release.finish()
			didStart.finish()
			session.disconnect()
		}
		session.credentialLoader = { _ in
			didStart.yield(())
			for await _ in gate {}
			return [:]
		}
		session.connect()
		let preparation = try #require(session.startup.credentialTask)
		var iterator = started.makeAsyncIterator()
		_ = await iterator.next()
		try #require(session.isConnecting)

		fixture.applicationState.applicationIsTerminating = true
		release.finish()
		await preparation.value

		#expect(session.connectionState.transport == .idle)
		#expect(session.socket == nil)
		#expect(session.startup.credentialTask == nil)
		#expect(session.reconnect.isEnabled == false)
	}

	@Test("A missed pong disconnects at the timeout when the preference asks for it")
	func pongPolicyDisconnectsAtTimeoutWhenConfigured() {
		#expect(ConnectionTimerPolicy.pongAction(
			elapsed: ConnectionTimerPolicy.timeoutInterval,
			eofReceived: false,
			disconnectOnTimeout: true,
			pingEnabled: true,
			warningAlreadyShown: false
		) == .disconnect)
	}

	@Test("Without the disconnect preference the timeout warns once and then stays quiet")
	func pongPolicyWarnsOnlyOnceWhenDisconnectIsDisabled() {
		#expect(ConnectionTimerPolicy.pongAction(
			elapsed: ConnectionTimerPolicy.timeoutInterval,
			eofReceived: false,
			disconnectOnTimeout: false,
			pingEnabled: true,
			warningAlreadyShown: false
		) == .warnTimeout)
		#expect(ConnectionTimerPolicy.pongAction(
			elapsed: ConnectionTimerPolicy.timeoutInterval,
			eofReceived: false,
			disconnectOnTimeout: false,
			pingEnabled: true,
			warningAlreadyShown: true
		) == .none)
	}

	@Test("The ping interval only pings while pinging is enabled")
	func pongPolicyPingsOnlyWhenEnabled() {
		#expect(ConnectionTimerPolicy.pongAction(
			elapsed: ConnectionTimerPolicy.pingInterval,
			eofReceived: false,
			disconnectOnTimeout: false,
			pingEnabled: true,
			warningAlreadyShown: false
		) == .ping)
		#expect(ConnectionTimerPolicy.pongAction(
			elapsed: ConnectionTimerPolicy.pingInterval,
			eofReceived: false,
			disconnectOnTimeout: false,
			pingEnabled: false,
			warningAlreadyShown: false
		) == .none)
	}
}
