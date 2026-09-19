// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

@MainActor
@Suite("Server session lifecycle policies")
struct ServerSessionLifecyclePolicyTests {
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
