// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

@MainActor
extension ServerSession {
	func dispatchTimerCommand(_ parsed: ParsedUserCommand, targetConversation: Conversation?) {
		var arguments = parsed.arguments
		guard arguments.isEmpty == false else {
			printDebugInformation(String(localized: .IRC.invalidSyntaxTypeTimerHelp))
			return
		}
		let action = arguments.next().lowercased()
		switch action {
		case "help":
			showTimerHelp(topic: arguments.next())
		case "stop":
			stopTimer(identifier: arguments.next())
		case "restart":
			restartTimer(identifier: arguments.next())
		case "remove":
			removeTimer(identifier: arguments.next())
		case "list":
			listTimers()
		default:
			addTimer(intervalString: action, arguments: arguments, targetConversation: targetConversation)
		}
	}

	private func showTimerHelp(topic: String) {
		printDebugInformation(String(localized: .IRC.timerCommand))
		printDebugInformation(multiline: TimerHelpTopic.helpText(for: TimerHelpTopic(rawValue: topic.lowercased())))
	}

	private func stopTimer(identifier: String) {
		guard let timedCommand = existingTimer(identifier: identifier) else { return }
		guard timedCommand.timer.isActive else {
			printDebugInformation(String(localized: .IRC.timerWithIdentifierIsAlreadyStopped(identifier)))
			return
		}
		timedCommand.stop()
		printDebugInformation(String(localized: .IRC.timerWithIdentifierStopped(identifier)))
	}

	private func restartTimer(identifier: String) {
		guard let timedCommand = existingTimer(identifier: identifier) else { return }
		let message = timedCommand.restart()
			? String(localized: .IRC.timerWithIdentifierRestarted(identifier))
			: String(localized: .IRC.timerWithIdentifierCantBeRestarted(identifier))
		printDebugInformation(message)
	}

	private func removeTimer(identifier: String) {
		guard identifier.isEmpty == false else {
			printDebugInformation(String(localized: .IRC.timerIdentifierIsNotProperlyFormatted))
			return
		}
		if identifier.caseInsensitiveCompare("all") == .orderedSame {
			removeTimedCommands()
			printDebugInformation(String(localized: .IRC.allTimersRemoved))
			return
		}
		guard let timedCommand = existingTimer(identifier: identifier) else { return }
		removeTimedCommand(timedCommand)
		printDebugInformation(String(localized: .IRC.timerWithIdentifierRemoved(identifier)))
	}

	private func existingTimer(identifier: String) -> TimedCommand? {
		guard identifier.isEmpty == false else {
			printDebugInformation(String(localized: .IRC.timerIdentifierIsNotProperlyFormatted))
			return nil
		}
		guard let timedCommand = timedCommand(withIdentifier: identifier) else {
			printDebugInformation(String(localized: .IRC.timerWithIdentifierDoesNotExist(identifier)))
			return nil
		}
		return timedCommand
	}

	private func listTimers() {
		let timedCommands = listOfTimedCommands()
		guard timedCommands.isEmpty == false else {
			printDebugInformation(String(localized: .IRC.thereAreNoTimers))
			return
		}
		printDebugInformation(String(localized: .IRC.timerCount(timedCommands.count)))
		for timedCommand in timedCommands {
			printDebugInformation(description(for: timedCommand))
		}
	}

	private func addTimer(
		intervalString: String,
		arguments: CommandArguments,
		targetConversation: Conversation?
	) {
		guard let interval = Int(intervalString), interval > 0 else {
			printDebugInformation(String(localized: .IRC.timerIntervalMustBeAWhole))
			return
		}
		var arguments = arguments
		let repeatToken = arguments.next()
		let explicitRepeat = Int(repeatToken)
		let repeatCount: Int
		let command: String
		if let explicitRepeat {
			repeatCount = explicitRepeat
			command = arguments.rest.trimmingCharacters(in: .whitespacesAndNewlines)
		} else {
			repeatCount = 1
			command = [repeatToken, arguments.rest]
				.filter { $0.isEmpty == false }
				.joined(separator: " ")
				.trimmingCharacters(in: .whitespacesAndNewlines)
		}
		guard repeatCount >= 0 else {
			printDebugInformation(String(localized: .IRC.timerRepeatCountMust))
			return
		}
		guard command.isEmpty == false else {
			printDebugInformation(String(localized: .IRC.invalidSyntaxTypeTimerHelp))
			return
		}
		let timedCommand = TimedCommand(command: command, onSession: self, in: targetConversation)
		addTimedCommand(timedCommand)
		timedCommand.start(
			TimeInterval(interval),
			onRepeat: repeatCount != 1,
			iterations: UInt(repeatCount)
		)
	}
}

extension ServerSession {
	func description(for timedCommand: TimedCommand) -> String {
		let timerInterval = DateFormatting.humanReadable(timedCommand.timer.interval, shortValue: false)
		let timeRemaining = DateFormatting.humanReadable(timedCommand.timer.timeRemaining, shortValue: false)
		let timerStatus = timedCommand.timer.isActive
			? String(localized: .IRC.timerCommandActive)
			: String(localized: .IRC.timerCommandStopped)

		guard timedCommand.timer.repeats else {
			return String(localized: .IRC.idStatusIntervalNextFireCommand(
				timedCommand.identifier,
				timerStatus,
				timerInterval,
				timeRemaining,
				timedCommand.command
			))
		}

		let repeatLimit = timedCommand.timer.iterations == 0
			? String(localized: .IRC.noLimit)
			: String(timedCommand.timer.iterations)

		return String(localized: .IRC.idStatusIntervalNextFireRepeat(
			timedCommand.identifier,
			timerStatus,
			timerInterval,
			timeRemaining,
			repeatLimit,
			Int(timedCommand.timer.currentIteration),
			timedCommand.command
		))
	}
}

/// A `/timer` subcommand `/timer help` can explain.
enum TimerHelpTopic: String {
	case add
	case remove
	case list
	case stop
	case restart

	/// What `/timer help` prints: the page for `topic`, or the overview when
	/// the user named no topic or one the command does not have.
	static func helpText(for topic: TimerHelpTopic?) -> String {
		switch topic {
		case .add: String(localized: .IRC.timerSecondsRepeatCommandSeconds)
		case .remove: String(localized: .IRC.timerRemoveIdentifierRemoveTheTimer)
		case .list: String(localized: .IRC.timerListListTimers)
		case .stop: String(localized: .IRC.timerStopIdentifierStopTheTimer)
		case .restart: String(localized: .IRC.timerRestartIdentifierRestartTheTimer)
		case nil: String(localized: .IRC.timerCommandCanBeUsed)
		}
	}
}
