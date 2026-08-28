/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
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

import CocoaExtensions
import Foundation

@MainActor
extension IRCClient {
	func dispatchTimerCommand(_ parsed: ParsedUserCommand, targetChannel: IRCChannel?) -> Bool {
		guard parsed.localCommand == .timer else { return false }
		var arguments = parsed.arguments
		guard arguments.isEmpty == false else {
			printDebugInformation(IRCTimerStrings.invalidSyntax)
			return true
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
			addTimer(intervalString: action, arguments: arguments, targetChannel: targetChannel)
		}
		return true
	}

	private func showTimerHelp(topic: String) {
		printDebugInformation(IRCTimerStrings.separator)
		let helpTopic = IRCTimerHelpTopic(rawValue: topic.lowercased())
		printDebugInformation(multiline: IRCTimerStrings.help(topic: helpTopic))
	}

	private func stopTimer(identifier: String) {
		guard let timedCommand = existingTimer(identifier: identifier) else { return }
		guard timedCommand.timerIsActive else {
			printDebugInformation(IRCTimerStrings.alreadyStopped(identifier: identifier))
			return
		}
		stopTimedCommand(timedCommand)
		printDebugInformation(IRCTimerStrings.stopped(identifier: identifier))
	}

	private func restartTimer(identifier: String) {
		guard let timedCommand = existingTimer(identifier: identifier) else { return }
		let message = restartTimedCommand(timedCommand)
			? IRCTimerStrings.restarted(identifier: identifier)
			: IRCTimerStrings.cannotRestart(identifier: identifier)
		printDebugInformation(message)
	}

	private func removeTimer(identifier: String) {
		guard identifier.isEmpty == false else {
			printDebugInformation(IRCTimerStrings.identifierInvalid)
			return
		}
		if identifier.caseInsensitiveCompare("all") == .orderedSame {
			removeTimedCommands()
			printDebugInformation(IRCTimerStrings.allRemoved)
			return
		}
		guard let timedCommand = existingTimer(identifier: identifier) else { return }
		removeTimedCommand(timedCommand)
		printDebugInformation(IRCTimerStrings.removed(identifier: identifier))
	}

	private func existingTimer(identifier: String) -> TimedCommand? {
		guard identifier.isEmpty == false else {
			printDebugInformation(IRCTimerStrings.identifierInvalid)
			return nil
		}
		guard let timedCommand = timedCommand(withIdentifier: identifier) else {
			printDebugInformation(IRCTimerStrings.notFound(identifier: identifier))
			return nil
		}
		return timedCommand
	}

	private func listTimers() {
		let timedCommands = listOfTimedCommands()
		guard timedCommands.isEmpty == false else {
			printDebugInformation(IRCTimerStrings.none)
			return
		}
		printDebugInformation(IRCTimerStrings.count(timedCommands.count))
		for timedCommand in timedCommands {
			printDebugInformation(description(for: timedCommand))
		}
	}

	private func addTimer(
		intervalString: String,
		arguments: CommandArguments,
		targetChannel: IRCChannel?
	) {
		guard let interval = Int(intervalString), interval > 0 else {
			printDebugInformation(IRCTimerStrings.invalidInterval)
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
			printDebugInformation(IRCTimerStrings.invalidRepeatCount)
			return
		}
		guard command.isEmpty == false else {
			printDebugInformation(IRCTimerStrings.invalidSyntax)
			return
		}
		let timedCommand = TimedCommand(command: command, onClient: self, inChannel: targetChannel)
		addTimedCommand(timedCommand)
		startTimedCommand(
			timedCommand,
			interval: UInt(interval),
			onRepeat: repeatCount != 1,
			iterations: UInt(repeatCount)
		)
	}
}
