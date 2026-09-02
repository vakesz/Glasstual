/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

/** `autojoinWaitsForConnectCommands` holds the autojoin back until the
 configured connect commands of this connection have been sent. */
@MainActor
@Suite("Autojoin waiting for the connect commands")
struct IRCClientAutojoinConnectCommandsTests {
	/// Short enough that a test can wait it out, long enough that the assertion
	/// before it is not racing the sleep.
	private static let settlingDelay: TimeInterval = 0.2

	/** The autojoin delay preference is zero so `startAutojoinTimer()` joins
	 inline rather than leaving the assertion to race a second timer. */
	private func makeClient(
		waitsForConnectCommands: Bool,
		connectCommands: [String] = [],
		delay: TimeInterval = IRCClientAutojoinConnectCommandsTests.settlingDelay
	) -> GLTTestClient {
		let client = GLTTestClient(
			configDictionary: [
				"autojoinWaitsForConnectCommands": waitsForConnectCommands,
				"autojoinDelayAfterConnectCommands": delay,
				"onConnectCommands": connectCommands,
			],
			nicknamePassword: nil,
			fixture: GLTClientEnvironmentFixture(preferences: ClientPreferences())
		)
		client.userNickname = "swift-user"
		client.markAsLoggedIn()
		return client
	}

	/// Waits for the settling task rather than for a fixed interval, so a busy
	/// machine cannot turn the delay into a failure.
	private func waitForJoin(on client: GLTTestClient) async throws {
		let deadline = ContinuousClock.now + .seconds(5)
		while joinLines(of: client).isEmpty, ContinuousClock.now < deadline {
			try await Task.sleep(for: .milliseconds(10), clock: .continuous)
		}
	}

	private func joinLines(of client: GLTTestClient) -> [String] {
		(client.sentLines as NSArray)
			.compactMap { $0 as? String }
			.filter { $0.hasPrefix("JOIN") }
	}

	@Test("The wait is over once the commands have settled")
	func waitEndsWhenConnectCommandsHaveSettled() {
		#expect(IRCClientAutojoinPolicy.shouldWaitForConnectCommands(
			waitsForConnectCommands: true,
			connectCommandsHaveSettled: false
		))
		#expect(IRCClientAutojoinPolicy.shouldWaitForConnectCommands(
			waitsForConnectCommands: true,
			connectCommandsHaveSettled: true
		) == false)
		#expect(IRCClientAutojoinPolicy.shouldWaitForConnectCommands(
			waitsForConnectCommands: false,
			connectCommandsHaveSettled: false
		) == false)
	}

	/// There is nothing to wait out when no command was sent, and nothing to
	/// wait out when the option is off.
	@Test("Only a connection with commands to send serves the delay")
	func delayAppliesOnlyWhereThereAreCommandsToWaitFor() {
		#expect(IRCClientAutojoinPolicy.delayAfterConnectCommands(
			waitsForConnectCommands: true,
			hasConnectCommands: true,
			configuredDelay: 3
		) == 3)
		#expect(IRCClientAutojoinPolicy.delayAfterConnectCommands(
			waitsForConnectCommands: true,
			hasConnectCommands: false,
			configuredDelay: 3
		) == 0)
		#expect(IRCClientAutojoinPolicy.delayAfterConnectCommands(
			waitsForConnectCommands: false,
			hasConnectCommands: true,
			configuredDelay: 3
		) == 0)
	}

	/// A delay the stepper cannot produce still cannot strand a connection.
	@Test("The delay is held inside its bounds")
	func delayIsClampedToItsBounds() {
		#expect(IRCClientAutojoinPolicy.delayAfterConnectCommands(
			waitsForConnectCommands: true,
			hasConnectCommands: true,
			configuredDelay: -5
		) == 0)
		#expect(IRCClientAutojoinPolicy.delayAfterConnectCommands(
			waitsForConnectCommands: true,
			hasConnectCommands: true,
			configuredDelay: 5000
		) == ClientConfigDefaults.maximumAutojoinConnectCommandDelay)
	}

	@Test("A registration whose commands have not settled joins nothing yet")
	func autojoinHoldsUntilTheDelayHasRun() async throws {
		let client = makeClient(
			waitsForConnectCommands: true,
			connectCommands: ["/msg NickServ identify hunter2"]
		)
		_ = try #require(client.findChannelOrCreate("#swift"))

		client.performAutoJoin()

		#expect(joinLines(of: client).isEmpty)

		client.markConnectCommandsPerformed()

		/* Sent, but not settled: the delay is what the option buys. */
		#expect(client.didPerformConnectCommands)
		#expect(client.connectCommandsHaveSettled == false)
		#expect(joinLines(of: client).isEmpty)
		#expect(client.isAutojoined == false)

		try await waitForJoin(on: client)

		#expect(client.connectCommandsHaveSettled)
		#expect(joinLines(of: client).contains { $0.contains("#swift") })
		#expect(client.isAutojoined)
	}

	/// Nothing was sent, so there is nothing for the delay to cover.
	@Test("A connection with no commands settles at once")
	func autojoinRunsImmediatelyWithNoConnectCommands() throws {
		let client = makeClient(waitsForConnectCommands: true)
		_ = try #require(client.findChannelOrCreate("#swift"))

		client.performAutoJoin()

		#expect(joinLines(of: client).isEmpty)

		client.markConnectCommandsPerformed()

		#expect(client.connectCommandsHaveSettled)
		#expect(joinLines(of: client).contains { $0.contains("#swift") })
	}

	@Test("Without the option the autojoin runs as soon as it is asked to")
	func autojoinRunsImmediatelyWithoutTheOption() throws {
		let client = makeClient(
			waitsForConnectCommands: false,
			connectCommands: ["/msg NickServ identify hunter2"]
		)
		_ = try #require(client.findChannelOrCreate("#swift"))

		client.performAutoJoin()

		#expect(joinLines(of: client).contains { $0.contains("#swift") })
	}

	@Test("A join the user asked for does not wait for anything")
	func userInitiatedJoinIgnoresTheWait() throws {
		let client = makeClient(
			waitsForConnectCommands: true,
			connectCommands: ["/msg NickServ identify hunter2"]
		)
		_ = try #require(client.findChannelOrCreate("#swift"))

		client.performAutoJoin(initiatedByUser: true)

		#expect(joinLines(of: client).contains { $0.contains("#swift") })
	}

	/// The next connection has its own commands to send and its own delay to
	/// serve, so neither the state nor the task can survive a disconnect.
	@Test("Disconnecting forgets the wait and cancels it")
	func disconnectingForgetsTheWait() {
		let client = makeClient(
			waitsForConnectCommands: true,
			connectCommands: ["/msg NickServ identify hunter2"]
		)
		client.markConnectCommandsPerformed()

		#expect(client.didPerformConnectCommands)
		#expect(client.connectCommandsSettlingTask != nil)

		client.resetAllPropertyValues()

		#expect(client.didPerformConnectCommands == false)
		#expect(client.connectCommandsHaveSettled == false)
		#expect(client.connectCommandsSettlingTask == nil)
	}
}
