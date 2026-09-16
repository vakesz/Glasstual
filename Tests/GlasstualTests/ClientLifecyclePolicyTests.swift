/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import Testing

@MainActor
@Suite("Client lifecycle policies")
struct ClientLifecyclePolicyTests {
	@Test("A missed pong disconnects at the timeout when the preference asks for it")
	func pongPolicyDisconnectsAtTimeoutWhenConfigured() {
		#expect(ClientConnectionTimerPolicy.pongAction(
			elapsed: ClientConnectionTimerPolicy.timeoutInterval,
			eofReceived: false,
			disconnectOnTimeout: true,
			pingEnabled: true,
			warningAlreadyShown: false
		) == .disconnect)
	}

	@Test("Without the disconnect preference the timeout warns once and then stays quiet")
	func pongPolicyWarnsOnlyOnceWhenDisconnectIsDisabled() {
		#expect(ClientConnectionTimerPolicy.pongAction(
			elapsed: ClientConnectionTimerPolicy.timeoutInterval,
			eofReceived: false,
			disconnectOnTimeout: false,
			pingEnabled: true,
			warningAlreadyShown: false
		) == .warnTimeout)
		#expect(ClientConnectionTimerPolicy.pongAction(
			elapsed: ClientConnectionTimerPolicy.timeoutInterval,
			eofReceived: false,
			disconnectOnTimeout: false,
			pingEnabled: true,
			warningAlreadyShown: true
		) == .none)
	}

	@Test("The ping interval only pings while pinging is enabled")
	func pongPolicyPingsOnlyWhenEnabled() {
		#expect(ClientConnectionTimerPolicy.pongAction(
			elapsed: ClientConnectionTimerPolicy.pingInterval,
			eofReceived: false,
			disconnectOnTimeout: false,
			pingEnabled: true,
			warningAlreadyShown: false
		) == .ping)
		#expect(ClientConnectionTimerPolicy.pongAction(
			elapsed: ClientConnectionTimerPolicy.pingInterval,
			eofReceived: false,
			disconnectOnTimeout: false,
			pingEnabled: false,
			warningAlreadyShown: false
		) == .none)
	}
}
