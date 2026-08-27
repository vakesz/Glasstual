/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import XCTest

final class IRCClientLifecyclePolicyTests: XCTestCase {
	func testAutojoinBatchHonorsConfiguredMaximum() {
		XCTAssertEqual(IRCClientAutojoinPolicy.nextBatchCount(remaining: 9, configuredMaximum: 3), 3)
		XCTAssertEqual(IRCClientAutojoinPolicy.nextBatchCount(remaining: 2, configuredMaximum: 3), 2)
	}

	func testAutojoinBatchAlwaysMakesProgress() {
		XCTAssertEqual(IRCClientAutojoinPolicy.nextBatchCount(remaining: 4, configuredMaximum: 0), 1)
		XCTAssertEqual(IRCClientAutojoinPolicy.nextBatchCount(remaining: 0, configuredMaximum: 4), 0)
	}

	func testAutojoinWaitsOnlyForUnidentifiedNickServSession() {
		XCTAssertTrue(IRCClientAutojoinPolicy.shouldWaitForIdentification(
			isIdentifiedWithSASL: false,
			waitsForNickServ: true,
			serverHasNickServ: true,
			isIdentifiedWithNickServ: false
		))
		XCTAssertFalse(IRCClientAutojoinPolicy.shouldWaitForIdentification(
			isIdentifiedWithSASL: true,
			waitsForNickServ: true,
			serverHasNickServ: true,
			isIdentifiedWithNickServ: false
		))
	}

	func testPongPolicyDisconnectsAtTimeoutWhenConfigured() {
		XCTAssertEqual(IRCClientConnectionTimerPolicy.pongAction(
			elapsed: IRCClientConnectionTimerPolicy.timeoutInterval,
			eofReceived: false,
			disconnectOnTimeout: true,
			pingEnabled: true,
			warningAlreadyShown: false
		), .disconnect)
	}

	func testPongPolicyWarnsOnlyOnceWhenDisconnectIsDisabled() {
		XCTAssertEqual(IRCClientConnectionTimerPolicy.pongAction(
			elapsed: IRCClientConnectionTimerPolicy.timeoutInterval,
			eofReceived: false,
			disconnectOnTimeout: false,
			pingEnabled: true,
			warningAlreadyShown: false
		), .warnTimeout)
		XCTAssertEqual(IRCClientConnectionTimerPolicy.pongAction(
			elapsed: IRCClientConnectionTimerPolicy.timeoutInterval,
			eofReceived: false,
			disconnectOnTimeout: false,
			pingEnabled: true,
			warningAlreadyShown: true
		), .none)
	}

	func testPongPolicyPingsOnlyWhenEnabled() {
		XCTAssertEqual(IRCClientConnectionTimerPolicy.pongAction(
			elapsed: IRCClientConnectionTimerPolicy.pingInterval,
			eofReceived: false,
			disconnectOnTimeout: false,
			pingEnabled: true,
			warningAlreadyShown: false
		), .ping)
		XCTAssertEqual(IRCClientConnectionTimerPolicy.pongAction(
			elapsed: IRCClientConnectionTimerPolicy.pingInterval,
			eofReceived: false,
			disconnectOnTimeout: false,
			pingEnabled: false,
			warningAlreadyShown: false
		), .none)
	}
}
