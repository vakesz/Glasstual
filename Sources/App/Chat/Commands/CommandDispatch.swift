// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

@MainActor
extension ServerSession {
	func sendCommand(_ input: String, completeTarget: Bool = true, target targetName: String? = nil) {
		sendCommand(NSAttributedString(string: input), completeTarget: completeTarget, target: targetName)
	}

	func sendCommand(_ input: NSAttributedString, completeTarget: Bool = true, target targetName: String? = nil) {
		guard let parsed = ParsedUserCommand(input) else { return }
		guard allowsDeveloperModeCommand(parsed) else { return }

		let targetConversation = resolvedTargetConversation(
			completeTarget: completeTarget,
			targetName: targetName
		)

		/* A name the session has no handler for is not an error: it belongs to a
		 user script or to the server. */
		guard let command = parsed.localCommand, let group = command.group else {
			dispatchScriptOrRawCommand(parsed, targetConversation: targetConversation)

			return
		}

		dispatch(group, command: command, parsed: parsed, targetConversation: targetConversation)
	}

	/** Calls the handler `group` names.

	 One switch, one call: the command is resolved once above and handed over with
	 the line, so no handler re-derives it from the name it was dispatched on. */
	private func dispatch(
		_ group: LocalCommand.Group,
		command: LocalCommand,
		parsed: ParsedUserCommand,
		targetConversation: Conversation?
	) {
		switch group {
		case .directChat:
			handleDCCCommand(parsed.arguments, command: parsed.command, targetConversation: targetConversation)
		case .message:
			dispatchMessageCommand(parsed, targetConversation: targetConversation)
		case .broadcast:
			dispatchBroadcastCommand(command, parsed: parsed)
		case .ctcp:
			dispatchCTCPCommand(command, parsed: parsed, targetConversation: targetConversation)
		case .configuration:
			dispatchConfigurationCommand(command, parsed: parsed, targetConversation: targetConversation)
		case .timer:
			dispatchTimerCommand(parsed, targetConversation: targetConversation)
		case .moderation:
			dispatchChannelModerationCommand(command, parsed: parsed, targetConversation: targetConversation)
		case .lifecycle:
			dispatchChannelLifecycleCommand(command, parsed: parsed, targetConversation: targetConversation)
		case .window:
			dispatchConversationWindowCommand(command, parsed: parsed, targetConversation: targetConversation)
		case .mode:
			dispatchChannelModeCommand(command, parsed: parsed, targetConversation: targetConversation)
		case .conversation:
			dispatchConversationCommand(command, parsed: parsed, targetConversation: targetConversation)
		case .bouncer:
			dispatchBouncerCommand(command, parsed: parsed, targetConversation: targetConversation)
		case .raw:
			dispatchRawCommand(command, parsed: parsed)
		case .request:
			dispatchNativeRequestCommand(command, parsed: parsed)
		case .operatorControl:
			dispatchNativeOperatorCommand(command, parsed: parsed)
		case .session:
			dispatchSessionCommand(command, parsed: parsed)
		case .notification:
			dispatchNotificationCommand(command, parsed: parsed)
		case .capability:
			dispatchNativeCapabilityCommand(command, parsed: parsed)
		case .information:
			dispatchNativeInformationCommand(command, parsed: parsed, targetConversation: targetConversation)
		}
	}

	/// Refuses a developer-mode command unless the setting is on. Keeping
	/// the flag out of the completion list is not enough on its own: the name
	/// still works when typed.
	private func allowsDeveloperModeCommand(_ parsed: ParsedUserCommand) -> Bool {
		guard parsed.isDeveloperModeOnly,
		      environment.settings.developerModeEnabled == false
		else {
			return true
		}
		printDebugInformation(String(localized: .IRC.developerModeRequired))
		return false
	}

	private func dispatchScriptOrRawCommand(_ parsed: ParsedUserCommand, targetConversation: Conversation?) {
		let ranScript = environment.services.scripts?.runScript(
			forOutgoingCommand: parsed.command,
			input: parsed.arguments.rest,
			target: targetConversation?.name,
			on: self
		) == true

		guard ranScript == false else { return }

		sendCommand(parsed.command.uppercased(), withData: parsed.arguments.rest)
	}

	func requireArguments(_ arguments: String, for command: String) -> Bool {
		guard arguments.isEmpty else { return true }
		printInvalidSyntaxMessage(for: command)
		return false
	}

	/// Rejects a command line that carries fewer arguments than the command
	/// index declares required, printing the index's own syntax line.
	func requireArguments(_ arguments: CommandArguments, for command: String) -> Bool {
		guard arguments.satisfiesDeclaredArity == false else { return true }
		printInvalidSyntaxMessage(for: command)
		return false
	}

	/// Every connection the chat session holds.
	var allSessions: [ServerSession] {
		chatSession?.sessions ?? []
	}

	/// The connections a command acts on: every one of them when the command's
	/// "all connections" setting is on, this one alone otherwise.
	func broadcastTargets(whenAllConnections allConnections: Bool) -> [ServerSession] {
		allConnections ? allSessions : [self]
	}

	private func resolvedTargetConversation(
		completeTarget: Bool,
		targetName: String?
	) -> Conversation? {
		guard completeTarget else { return nil }
		if let targetName {
			return findConversation(targetName)
		}
		guard let output, output.selectedSession === self else {
			return nil
		}
		return output.selectedConversation
	}
}

extension ServerSession {
	/** Writes `command` and `data` to the wire exactly as given.

	 Nothing here marks a trailing parameter, and nothing should: this is the
	 raw path — the one an unrecognised `/command` takes — where the text is the
	 user's and the line is whatever they typed. A parameter of theirs that has
	 to hold spaces needs the colon they typed in front of it, the way it would
	 on any other session's raw line.

	 A command the session itself assembles has parameters it already knows the
	 boundaries of, so it goes through `send(_:arguments:)` instead, which marks
	 the trailing one from `RemoteCommand.trailingParameter`. */
	func sendCommand(_ command: String, withData data: String) {
		sendLine("\(command) \(data)")
	}

	func printInvalidSyntaxMessage(for command: String) {
		guard let localCommand = LocalCommand(typedName: command) else { return }
		printDebugInformation(String(localized: .IRC.invalidSyntax(localCommand.syntax)))
	}
}
