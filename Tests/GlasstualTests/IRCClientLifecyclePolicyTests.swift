/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import Testing

@MainActor
@Suite("Client lifecycle policies")
struct IRCClientLifecyclePolicyTests {
	@Test("Autojoin waits only for a NickServ session that has not identified")
	func autojoinWaitsOnlyForUnidentifiedNickServSession() {
		#expect(IRCClientAutojoinPolicy.shouldWaitForIdentification(
			isIdentifiedWithSASL: false,
			waitsForNickServ: true,
			serverHasNickServ: true,
			isIdentifiedWithNickServ: false
		))
		#expect(IRCClientAutojoinPolicy.shouldWaitForIdentification(
			isIdentifiedWithSASL: true,
			waitsForNickServ: true,
			serverHasNickServ: true,
			isIdentifiedWithNickServ: false
		) == false)
	}

	@Test("A missed pong disconnects at the timeout when the preference asks for it")
	func pongPolicyDisconnectsAtTimeoutWhenConfigured() {
		#expect(IRCClientConnectionTimerPolicy.pongAction(
			elapsed: IRCClientConnectionTimerPolicy.timeoutInterval,
			eofReceived: false,
			disconnectOnTimeout: true,
			pingEnabled: true,
			warningAlreadyShown: false
		) == .disconnect)
	}

	@Test("Without the disconnect preference the timeout warns once and then stays quiet")
	func pongPolicyWarnsOnlyOnceWhenDisconnectIsDisabled() {
		#expect(IRCClientConnectionTimerPolicy.pongAction(
			elapsed: IRCClientConnectionTimerPolicy.timeoutInterval,
			eofReceived: false,
			disconnectOnTimeout: false,
			pingEnabled: true,
			warningAlreadyShown: false
		) == .warnTimeout)
		#expect(IRCClientConnectionTimerPolicy.pongAction(
			elapsed: IRCClientConnectionTimerPolicy.timeoutInterval,
			eofReceived: false,
			disconnectOnTimeout: false,
			pingEnabled: true,
			warningAlreadyShown: true
		) == .none)
	}

	@Test("The ping interval only pings while pinging is enabled")
	func pongPolicyPingsOnlyWhenEnabled() {
		#expect(IRCClientConnectionTimerPolicy.pongAction(
			elapsed: IRCClientConnectionTimerPolicy.pingInterval,
			eofReceived: false,
			disconnectOnTimeout: false,
			pingEnabled: true,
			warningAlreadyShown: false
		) == .ping)
		#expect(IRCClientConnectionTimerPolicy.pongAction(
			elapsed: IRCClientConnectionTimerPolicy.pingInterval,
			eofReceived: false,
			disconnectOnTimeout: false,
			pingEnabled: false,
			warningAlreadyShown: false
		) == .none)
	}
}
