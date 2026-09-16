/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
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

extension Client {
	func description(for timedCommand: TimedCommand) -> String {
		let timerInterval = humanReadableTimeInterval(timedCommand.timer.interval, shortValue: false)
		let timeRemaining = humanReadableTimeInterval(timedCommand.timer.timeRemaining, shortValue: false)
		let timerStatus = TimerStrings.status(active: timedCommand.timer.isActive)

		guard timedCommand.timer.repeats else {
			return TimerStrings.summary(
				identifier: timedCommand.identifier,
				status: timerStatus,
				interval: timerInterval,
				nextFire: timeRemaining,
				command: timedCommand.command
			)
		}

		let repeatLimit = timedCommand.timer.iterations == 0
			? TimerStrings.noLimit
			: String(timedCommand.timer.iterations)

		return TimerStrings.repeatingSummary(
			identifier: timedCommand.identifier,
			status: timerStatus,
			interval: timerInterval,
			nextFire: timeRemaining,
			repeatLimit: repeatLimit,
			iteration: timedCommand.timer.currentIteration,
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

	/** Runs `timedCommand` where it was made.

	 A command made in a channel runs in that channel, and one made in the
	 server console runs with no channel at all. Completing the target at fire
	 time instead sent a command made in the console, or in a channel since
	 closed, into whichever channel happened to be selected by then — so a
	 timer whose channel has gone is removed rather than run. */
	@MainActor
	func onTimedCommand(_ timedCommand: TimedCommand) {
		let channel = timedCommand.channelId.flatMap { channelId in
			channelList.first { $0.uniqueIdentifier == channelId }
		}

		if timedCommand.channelId != nil, channel == nil {
			timedCommand.stop()
			removeTimedCommand(timedCommand)
			return
		}

		if timedCommand.timer.isActive == false {
			removeTimedCommand(timedCommand)
		}

		sendCommand(timedCommand.command, completeTarget: channel != nil, target: channel?.name)
	}
}
