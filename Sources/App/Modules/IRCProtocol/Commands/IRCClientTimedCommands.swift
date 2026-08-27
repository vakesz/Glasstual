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
import ObjectiveC

private final class ClientTimedCommandStore: @unchecked Sendable {
	private let lock = NSLock()
	private var commands: [String: TimedCommand] = [:]

	func command(withIdentifier identifier: String) -> TimedCommand? {
		lock.withLock { commands[identifier] }
	}

	func allCommands() -> [TimedCommand] {
		lock.withLock { Array(commands.values) }
	}

	func insert(_ command: TimedCommand) {
		lock.withLock { commands[command.identifier] = command }
	}

	func remove(_ command: TimedCommand) {
		_ = lock.withLock { commands.removeValue(forKey: command.identifier) }
	}

	func removeAll() {
		lock.withLock { commands.removeAll(keepingCapacity: false) }
	}
}

private nonisolated(unsafe) var timedCommandStoreKey: UInt8 = 0

extension IRCClient {
	private var timedCommandStore: ClientTimedCommandStore {
		if let store = objc_getAssociatedObject(self, &timedCommandStoreKey) as? ClientTimedCommandStore {
			return store
		}

		objc_sync_enter(self)
		defer { objc_sync_exit(self) }

		if let store = objc_getAssociatedObject(self, &timedCommandStoreKey) as? ClientTimedCommandStore {
			return store
		}

		let store = ClientTimedCommandStore()
		objc_setAssociatedObject(self, &timedCommandStoreKey, store, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
		return store
	}

	@objc(descriptionForTimedCommand:)
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

	@objc(timedCommandWithIdentifier:)
	func timedCommand(withIdentifier identifier: String) -> TimedCommand? {
		timedCommandStore.command(withIdentifier: identifier)
	}

	@objc(listOfTimedCommands)
	func listOfTimedCommands() -> [TimedCommand] {
		timedCommandStore.allCommands()
	}

	@objc(addTimedCommand:)
	func addTimedCommand(_ timedCommand: TimedCommand) {
		timedCommandStore.insert(timedCommand)
	}

	@objc(removeTimedCommands)
	func removeTimedCommands() {
		timedCommandStore.removeAll()
	}

	@objc(removeTimedCommand:)
	func removeTimedCommand(_ timedCommand: TimedCommand) {
		timedCommandStore.remove(timedCommand)
	}

	@objc(stopTimedCommand:)
	func stopTimedCommand(_ timedCommand: TimedCommand) {
		timedCommand.stop()
	}

	@objc(startTimedCommand:interval:)
	func startTimedCommand(_ timedCommand: TimedCommand, interval: UInt) {
		startTimedCommand(timedCommand, interval: interval, onRepeat: false, iterations: 0)
	}

	@objc(startTimedCommand:interval:onRepeat:)
	func startTimedCommand(_ timedCommand: TimedCommand, interval: UInt, onRepeat: Bool) {
		startTimedCommand(timedCommand, interval: interval, onRepeat: onRepeat, iterations: 0)
	}

	@objc(startTimedCommand:interval:onRepeat:iterations:)
	func startTimedCommand(
		_ timedCommand: TimedCommand,
		interval: UInt,
		onRepeat: Bool,
		iterations: UInt
	) {
		timedCommand.start(TimeInterval(interval), onRepeat: onRepeat, iterations: iterations)
	}

	@objc(restartTimedCommand:)
	func restartTimedCommand(_ timedCommand: TimedCommand) -> Bool {
		timedCommand.restart()
	}

	@objc(onTimedCommand:)
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
