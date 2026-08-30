/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import Foundation

extension IRCClient {
	func description(for timedCommand: TimedCommand) -> String {
		let timerInterval = humanReadableTimeInterval(timedCommand.timerInterval, false, 0) as String? ?? ""
		let timeRemaining = humanReadableTimeInterval(timedCommand.timeRemaining, false, 0) as String? ?? ""
		let timerStatus = IRCTimerStrings.status(active: timedCommand.timerIsActive)

		guard timedCommand.repeatTimer else {
			return IRCTimerStrings.summary(
				identifier: timedCommand.identifier,
				status: timerStatus,
				interval: timerInterval,
				nextFire: timeRemaining,
				command: timedCommand.command
			)
		}

		let repeatLimit = timedCommand.iterations == 0
			? IRCTimerStrings.noLimit
			: String(timedCommand.iterations)

		return IRCTimerStrings.repeatingSummary(
			identifier: timedCommand.identifier,
			status: timerStatus,
			interval: timerInterval,
			nextFire: timeRemaining,
			repeatLimit: repeatLimit,
			iteration: timedCommand.currentIteration,
			command: timedCommand.command
		)
	}

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

	func stopTimedCommand(_ timedCommand: TimedCommand) {
		timedCommand.stop()
	}

	func startTimedCommand(_ timedCommand: TimedCommand, interval: UInt) {
		startTimedCommand(timedCommand, interval: interval, onRepeat: false, iterations: 0)
	}

	func startTimedCommand(_ timedCommand: TimedCommand, interval: UInt, onRepeat: Bool) {
		startTimedCommand(timedCommand, interval: interval, onRepeat: onRepeat, iterations: 0)
	}

	func startTimedCommand(
		_ timedCommand: TimedCommand,
		interval: UInt,
		onRepeat: Bool,
		iterations: UInt
	) {
		timedCommand.start(TimeInterval(interval), onRepeat: onRepeat, iterations: iterations)
	}

	func restartTimedCommand(_ timedCommand: TimedCommand) -> Bool {
		timedCommand.restart()
	}

	@MainActor
	func onTimedCommand(_ timedCommand: TimedCommand) {
		if timedCommand.timerIsActive == false {
			removeTimedCommand(timedCommand)
		}

		let channel = timedCommand.channelId.flatMap { channelId in
			channelList.first { $0.uniqueIdentifier == channelId }
		}
		sendCommand(timedCommand.command, completeTarget: true, target: channel?.name)
	}
}
