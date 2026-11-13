// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// The intervals and decisions behind the ping, retry and reachability timers.
@MainActor
struct ConnectionTimerPolicyTests {
	@Test("A stalled registration is retried after four minutes")
	func retryInterval() {
		#expect(ConnectionTimerPolicy.retryInterval == 240)
	}

	@Test("The delay never shrinks as attempts accumulate, and survives any count")
	func delayIsMonotonicAndTotal() {
		let delays = (UInt(0) ... 12).map { ConnectionTimerPolicy.reconnectDelay(attempt: $0, jitter: 0) }

		#expect(delays == delays.sorted())
		#expect(delays.first == ConnectionTimerPolicy.reconnectInterval)
		#expect(delays.last == ConnectionTimerPolicy.maximumReconnectInterval)
		#expect(ConnectionTimerPolicy.reconnectDelay(attempt: .max, jitter: 0) == ConnectionTimerPolicy.maximumReconnectInterval)
	}

	@Test("A jitter outside 0 to 1 is clamped", arguments: [-5.0, 2.0, .infinity])
	func jitterIsClamped(_ jitter: Double) {
		let delay = ConnectionTimerPolicy.reconnectDelay(attempt: 0, jitter: jitter)

		#expect(delay >= ConnectionTimerPolicy.reconnectInterval * 0.75)
		#expect(delay <= ConnectionTimerPolicy.reconnectInterval)
	}

	struct PongCase: Sendable {
		let elapsed: TimeInterval
		let eof: Bool
		let disconnect: Bool
		let ping: Bool
		let warned: Bool
		let action: String
	}

	nonisolated static let pongCases: [PongCase] = [
		PongCase(elapsed: 0, eof: false, disconnect: false, ping: true, warned: false, action: "none"),
		PongCase(elapsed: 269, eof: false, disconnect: false, ping: true, warned: false, action: "none"),
		PongCase(elapsed: 270, eof: false, disconnect: false, ping: true, warned: false, action: "ping"),
		PongCase(elapsed: 270, eof: false, disconnect: false, ping: false, warned: false, action: "none"),
		PongCase(elapsed: 359, eof: false, disconnect: false, ping: true, warned: false, action: "ping"),
		PongCase(elapsed: 360, eof: false, disconnect: false, ping: true, warned: false, action: "warnTimeout"),
		PongCase(elapsed: 360, eof: false, disconnect: false, ping: true, warned: true, action: "none"),
		PongCase(elapsed: 360, eof: false, disconnect: true, ping: true, warned: true, action: "disconnect"),
		PongCase(elapsed: 360, eof: true, disconnect: false, ping: true, warned: true, action: "disconnect"),
	]

	@Test("Silence escalates from a ping to a warning to a disconnect", arguments: Self.pongCases)
	func pongAction(_ testCase: PongCase) {
		#expect(
			ConnectionTimerPolicy.pongAction(
				elapsed: testCase.elapsed,
				eofReceived: testCase.eof,
				disconnectOnTimeout: testCase.disconnect,
				pingEnabled: testCase.ping,
				warningAlreadyShown: testCase.warned
			).description == testCase.action
		)
	}

	// MARK: - Reachability

	private func session(disconnectsOnChange: Bool, loggedIn: Bool) -> TestServerSession {
		let session = TestServerSession(configDictionary: ["nickname": "mara", "username": "mara"])

		session.config.performDisconnectOnReachabilityChange = disconnectsOnChange

		if loggedIn {
			session.markAsLoggedIn()
		}

		return session
	}

	@Test("Regaining the network leaves the session alone")
	func reachableDoesNothing() {
		let session = session(disconnectsOnChange: true, loggedIn: true)

		session.noteReachabilityChanged(true)

		#expect(session.disconnectType == .normal)
		#expect(session.reconnect.isEnabled == false)
	}

	@Test("Losing the network acts only on a logged-in session that asked for it", arguments: [
		(true, true, true),
		(true, false, false),
		(false, true, false),
		(false, false, false),
	])
	func lossActsOnlyWhenAskedFor(_ setting: Bool, _ loggedIn: Bool, _ acts: Bool) {
		let session = session(disconnectsOnChange: setting, loggedIn: loggedIn)

		session.noteReachabilityChanged(false)

		#expect((session.disconnectType == .reachabilityChange) == acts)
		#expect(session.reconnect.isEnabled == acts)
	}
}

private extension ConnectionTimerPolicy.PongAction {
	var description: String {
		switch self {
		case .none: "none"
		case .ping: "ping"
		case .warnTimeout: "warnTimeout"
		case .disconnect: "disconnect"
		}
	}
}
