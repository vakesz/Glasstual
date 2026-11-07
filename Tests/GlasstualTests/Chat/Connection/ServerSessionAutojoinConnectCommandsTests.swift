// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/** `autojoinWaitsForConnectCommands` holds the autojoin back until the
 configured connect commands of this connection have been sent. */
@MainActor
@Suite("Autojoin waiting for the connect commands")
struct ServerSessionAutojoinConnectCommandsTests {
	/// Virtual seconds: the test steps a ``ManualTimerClock`` past it.
	private static let settlingDelay: TimeInterval = 3

	private let clock = ManualTimerClock()

	/// The settling delay runs on the suite's manual clock, so no test sleeps.
	private func makeSession(
		waitsForConnectCommands: Bool,
		connectCommands: [String] = [],
		delay: TimeInterval = ServerSessionAutojoinConnectCommandsTests.settlingDelay
	) -> TestServerSession {
		let session = TestServerSession(
			configDictionary: [
				"autojoinWaitsForConnectCommands": waitsForConnectCommands,
				"autojoinDelayAfterConnectCommands": delay,
				"loginCommands": connectCommands,
			],
			nicknamePassword: nil,
			fixture: ChatEnvironmentFixture(settings: ChatSettings())
		)
		session.startupClock = clock.timerClock
		session.userNickname = "swift-user"
		session.markAsLoggedIn()
		return session
	}

	private func joinLines(of session: TestServerSession) -> [String] {
		(session.sentLines as NSArray)
			.compactMap { $0 as? String }
			.filter { $0.hasPrefix("JOIN") }
	}

	/// There is nothing to wait out when no command was sent, and nothing to
	/// wait out when the option is off.
	@Test("Only a connection with commands to send serves the delay")
	func delayAppliesOnlyWhereThereAreCommandsToWaitFor() {
		#expect(AutojoinPolicy.delayAfterConnectCommands(
			waitsForConnectCommands: true,
			hasConnectCommands: true,
			configuredDelay: 3
		) == 3)
		#expect(AutojoinPolicy.delayAfterConnectCommands(
			waitsForConnectCommands: true,
			hasConnectCommands: false,
			configuredDelay: 3
		) == 0)
		#expect(AutojoinPolicy.delayAfterConnectCommands(
			waitsForConnectCommands: false,
			hasConnectCommands: true,
			configuredDelay: 3
		) == 0)
	}

	/// A delay the stepper cannot produce still cannot strand a connection.
	@Test("The delay is held inside its bounds")
	func delayIsClampedToItsBounds() {
		#expect(AutojoinPolicy.delayAfterConnectCommands(
			waitsForConnectCommands: true,
			hasConnectCommands: true,
			configuredDelay: -5
		) == 0)
		#expect(AutojoinPolicy.delayAfterConnectCommands(
			waitsForConnectCommands: true,
			hasConnectCommands: true,
			configuredDelay: 5000
		) == ServerConfigDefaults.maximumAutojoinConnectCommandDelay)
	}

	@Test("A registration whose commands have not settled joins nothing yet")
	func autojoinHoldsUntilTheDelayHasRun() async throws {
		let session = makeSession(
			waitsForConnectCommands: true,
			connectCommands: ["/mode swift-user +i"]
		)
		_ = try #require(session.findConversationOrCreate("#swift"))

		session.performAutoJoin()

		#expect(joinLines(of: session).isEmpty)

		session.markConnectCommandsPerformed()

		/* Sent, but not settled: the delay is what the option buys. */
		#expect(session.didPerformConnectCommands)
		#expect(session.connectCommandsHaveSettled == false)
		#expect(joinLines(of: session).isEmpty)
		#expect(session.isAutojoined == false)

		await clock.advance(by: Self.settlingDelay - 1)
		#expect(session.connectCommandsHaveSettled == false)
		#expect(joinLines(of: session).isEmpty)

		await clock.advance(by: 1)

		#expect(session.connectCommandsHaveSettled)
		#expect(joinLines(of: session).contains { $0.contains("#swift") })
		#expect(session.isAutojoined)
	}

	/// Nothing was sent, so there is nothing for the delay to cover.
	@Test("A connection with no commands settles at once")
	func autojoinRunsImmediatelyWithNoConnectCommands() throws {
		let session = makeSession(waitsForConnectCommands: true)
		_ = try #require(session.findConversationOrCreate("#swift"))

		session.performAutoJoin()

		#expect(joinLines(of: session).isEmpty)

		session.markConnectCommandsPerformed()

		#expect(session.connectCommandsHaveSettled)
		#expect(joinLines(of: session).contains { $0.contains("#swift") })
	}

	@Test("Without the option the autojoin runs as soon as it is asked to")
	func autojoinRunsImmediatelyWithoutTheOption() throws {
		let session = makeSession(
			waitsForConnectCommands: false,
			connectCommands: ["/mode swift-user +i"]
		)
		_ = try #require(session.findConversationOrCreate("#swift"))

		session.performAutoJoin()
		#expect(joinLines(of: session).isEmpty)
		session.markConnectCommandsPerformed()

		#expect(joinLines(of: session).contains { $0.contains("#swift") })
	}

	@Test("A join the user asked for does not wait for anything")
	func userInitiatedJoinIgnoresTheWait() throws {
		let session = makeSession(
			waitsForConnectCommands: true,
			connectCommands: ["/mode swift-user +i"]
		)
		_ = try #require(session.findConversationOrCreate("#swift"))

		session.performAutoJoin(initiatedByUser: true)

		#expect(joinLines(of: session).contains { $0.contains("#swift") })
	}

	/// The next connection has its own commands to send and its own delay to
	/// serve, so neither the state nor the task can survive a disconnect.
	@Test("Disconnecting forgets the wait and cancels it")
	func disconnectingForgetsTheWait() {
		let session = makeSession(
			waitsForConnectCommands: true,
			connectCommands: ["/mode swift-user +i"]
		)
		session.markConnectCommandsPerformed()

		#expect(session.didPerformConnectCommands)
		#expect(session.startup.settlingTask != nil)

		session.resetAllPropertyValues()

		#expect(session.didPerformConnectCommands == false)
		#expect(session.connectCommandsHaveSettled == false)
		#expect(session.startup.settlingTask == nil)
	}
}
