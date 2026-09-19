// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

final class TimedCommand {
	private static var lastIdentifier = 0

	let identifier: String
	let sessionId: String
	let conversationId: String?
	let command: String

	/// The timer the command runs on. Callers read its interval, iteration and
	/// activity off it directly.
	let timer: SessionTimer

	init(command: String, onSession session: ServerSession, in conversation: Conversation? = nil) {
		let identifier = Self.nextIdentifier()
		self.identifier = identifier
		sessionId = session.uniqueIdentifier
		conversationId = conversation?.uniqueIdentifier
		self.command = command

		/* The command the timer runs is looked up when it fires rather than
		 captured here: the timer is built before `self` finishes initialising,
		 and the session's registry is the one place that says whether the command
		 is still wanted. A timer left holding its command would also be a cycle
		 neither side ever breaks. */
		timer = SessionTimer { [weak session] _ in
			guard let session,
			      let timedCommand = session.timedCommand(withIdentifier: identifier)
			else {
				return
			}

			session.onTimedCommand(timedCommand)
		}
	}

	isolated deinit {
		timer.stop()
	}

	func start(_ interval: TimeInterval, onRepeat repeatTimer: Bool = false, iterations: UInt = 0) {
		timer.start(interval, repeats: repeatTimer, iterations: iterations)
	}

	func stop() {
		timer.stop()
	}

	/// Runs the command's last interval again, or reports that it never ran
	/// one: the timer's interval is zero until the first `start`.
	func restart() -> Bool {
		guard timer.interval > 0 else {
			return false
		}

		start(timer.interval, onRepeat: timer.repeats, iterations: timer.iterations)

		return true
	}

	private static func nextIdentifier() -> String {
		lastIdentifier += 1
		return String(lastIdentifier)
	}
}

extension ServerSession {
	func timedCommand(withIdentifier identifier: String) -> TimedCommand? {
		timedCommandsByIdentifier[identifier]
	}

	func listOfTimedCommands() -> [TimedCommand] {
		Array(timedCommandsByIdentifier.values)
	}

	func addTimedCommand(_ timedCommand: TimedCommand) {
		timedCommandsByIdentifier[timedCommand.identifier] = timedCommand
	}

	func removeTimedCommands() {
		timedCommandsByIdentifier.removeAll()
	}

	func removeTimedCommand(_ timedCommand: TimedCommand) {
		timedCommandsByIdentifier.removeValue(forKey: timedCommand.identifier)
	}

	/** Runs `timedCommand` where it was made.

	 A command made in a conversation runs in that conversation, and one made in
	 the server console runs with no target at all. Completing the target at fire
	 time instead sent a command made in the console, or in a conversation since
	 closed, into whichever conversation happened to be selected by then — so a
	 timer whose conversation has gone is removed rather than run. */
	@MainActor
	func onTimedCommand(_ timedCommand: TimedCommand) {
		let conversation = timedCommand.conversationId.flatMap { conversationId in
			conversationList.first { $0.uniqueIdentifier == conversationId }
		}

		if timedCommand.conversationId != nil, conversation == nil {
			timedCommand.stop()
			removeTimedCommand(timedCommand)
			return
		}

		if timedCommand.timer.isActive == false {
			removeTimedCommand(timedCommand)
		}

		sendCommand(timedCommand.command, completeTarget: conversation != nil, target: conversation?.name)
	}
}
