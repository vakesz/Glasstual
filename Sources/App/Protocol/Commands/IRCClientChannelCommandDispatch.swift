/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2019 Codeux Software, LLC & respective contributors.
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

private struct ChannelModerationInvocation {
	let command: IRCLocalCommand
	let channelName: String
	let channel: IRCChannel?
	let nickname: String
	let remainingArguments: String

	/// The moderation commands that set or clear a list mode before, or
	/// instead of, kicking.
	static let modeCommands: Set<IRCLocalCommand> = [.ban, .kb, .kickban, .quiet, .unban, .unquiet]

	static let kickCommands: Set<IRCLocalCommand> = [.kb, .kick, .kickban]

	static let removingCommands: Set<IRCLocalCommand> = [.unban, .unquiet]

	static let quietCommands: Set<IRCLocalCommand> = [.quiet, .unquiet]
}

@MainActor
extension IRCClient {
	func dispatchNativeChannelCommand(
		_ parsed: ParsedUserCommand,
		targetChannel: IRCChannel?
	) -> Bool {
		guard parsed.localCommand != nil else { return false }
		return dispatchBroadcastCommand(parsed) ||
			dispatchCTCPCommand(parsed, targetChannel: targetChannel) ||
			dispatchUserPrivilegeCommand(parsed, targetChannel: targetChannel) ||
			dispatchChannelModerationCommand(parsed, targetChannel: targetChannel) ||
			dispatchChannelLifecycleCommand(parsed, targetChannel: targetChannel) ||
			dispatchChannelNavigationCommand(parsed) ||
			dispatchChannelWindowCommand(parsed, targetChannel: targetChannel) ||
			dispatchChannelMembershipCommand(parsed, targetChannel: targetChannel) ||
			dispatchChannelModeCommand(parsed, targetChannel: targetChannel) ||
			dispatchQueryRenameCommand(parsed, targetChannel: targetChannel) ||
			dispatchChannelConversationCommand(parsed, targetChannel: targetChannel)
	}

	private func dispatchBroadcastCommand(_ parsed: ParsedUserCommand) -> Bool {
		let command = parsed.localCommand
		guard command == .ame || command == .amsg else { return false }
		guard isLoggedIn else { return true }
		guard requireArguments(parsed.arguments, for: parsed.command) else { return true }
		let remoteCommand: IRCRemoteCommand = command == .amsg ? .privmsg : .privmsgAction
		for client in (world?.clientList ?? [])
			where client === self || environment.preferences.amsgAllConnections
		{
			let channels = client.channelList.filter { $0.isActive && $0.isChannel }
			client.sendText(parsed.arguments.attributedRest, as: remoteCommand, toChannels: channels)
		}
		return true
	}

	private func dispatchCTCPCommand(_ parsed: ParsedUserCommand, targetChannel: IRCChannel?) -> Bool {
		let command = parsed.localCommand
		guard command == .ctcp || command == .ctcpreply else { return false }
		guard isLoggedIn else { return true }
		var arguments = parsed.arguments
		let selectedChannel = output?.selectedChannel
		let targetName: String
		if let targetChannel, targetChannel !== selectedChannel {
			guard targetChannel.isUtility == false else {
				printDebugInformation(IRCCommandStrings.commandUnavailableInWindow)
				return true
			}
			targetName = targetChannel.name
		} else {
			targetName = arguments.next()
		}
		let subcommand = arguments.next().uppercased()
		guard requireArguments(subcommand, for: parsed.command) else { return true }
		if command == .ctcpreply {
			sendCTCPReply(targetName, command: subcommand, text: arguments.rest)
		} else if subcommand == "PING" {
			sendCTCPPing(targetName)
		} else {
			sendCTCPQuery(targetName, command: subcommand, text: arguments.rest)
		}
		return true
	}

	private func dispatchChannelModerationCommand(
		_ parsed: ParsedUserCommand,
		targetChannel: IRCChannel?
	) -> Bool {
		guard let command = parsed.localCommand,
		      ChannelModerationInvocation.modeCommands.contains(command)
		      || ChannelModerationInvocation.kickCommands.contains(command)
		else { return false }
		guard isLoggedIn else { return true }
		var arguments = parsed.arguments
		var nickname = arguments.next()
		let channelName: String
		let channel: IRCChannel?
		if stringIsChannelName(nickname) {
			channelName = nickname
			channel = findChannel(channelName)
			nickname = arguments.next()
		} else if let targetChannel, targetChannel.isChannel {
			channelName = targetChannel.name
			channel = targetChannel
		} else {
			printDebugInformation(IRCCommandStrings.channelRequired)
			return true
		}
		guard requireArguments(nickname, for: parsed.command) else { return true }
		let invocation = ChannelModerationInvocation(
			command: command,
			channelName: channelName,
			channel: channel,
			nickname: nickname,
			remainingArguments: arguments.rest
		)
		guard applyModerationModeIfNeeded(invocation) else { return true }
		applyModerationKickIfNeeded(invocation)
		return true
	}

	private func applyModerationModeIfNeeded(_ invocation: ChannelModerationInvocation) -> Bool {
		guard ChannelModerationInvocation.modeCommands.contains(invocation.command) else { return true }
		let modeSymbol: Character = ChannelModerationInvocation.quietCommands.contains(invocation.command) ? "q" : "b"
		guard supportInfo.modeSymbolIsUserPrefix(String(modeSymbol)) == false else {
			printDebugInformation(IRCCommandStrings.unsupportedMode(String(modeSymbol)))
			return false
		}
		let banMask = invocation.channel?.findMember(invocation.nickname)?.user.banMask ?? invocation.nickname
		let removesMode = ChannelModerationInvocation.removingCommands.contains(invocation.command)
		send("MODE", arguments: [invocation.channelName, "\(removesMode ? "-" : "+")\(modeSymbol)", banMask])
		return true
	}

	private func applyModerationKickIfNeeded(_ invocation: ChannelModerationInvocation) {
		guard ChannelModerationInvocation.kickCommands.contains(invocation.command) else { return }
		let reason = invocation.remainingArguments.isEmpty
			? environment.preferences.defaultKickMessage
			: invocation.remainingArguments
		let maximumLength = Int(supportInfo.maximumKickLength)
		let truncatedReason = ClientWireUtilities.truncated(reason, toByteCount: maximumLength)
		if truncatedReason != reason {
			printDebugInformation(
				IRCCommandStrings.kickMessageTooLong(networkName: networkNameAlt, maximumLength: maximumLength)
			)
		}
		send("KICK", arguments: [invocation.channelName, invocation.nickname, truncatedReason])
	}

	private func dispatchUserPrivilegeCommand(
		_ parsed: ParsedUserCommand,
		targetChannel: IRCChannel?
	) -> Bool {
		let mode: (symbol: String, isSet: Bool)? = switch parsed.localCommand {
		case .op: ("o", true)
		case .deop: ("o", false)
		case .halfop: ("h", true)
		case .dehalfop: ("h", false)
		case .voice: ("v", true)
		case .devoice: ("v", false)
		default: nil
		}
		guard let mode else { return false }
		guard isLoggedIn else { return true }
		guard supportInfo.modeSymbolIsUserPrefix(mode.symbol) else {
			printDebugInformation(IRCCommandStrings.unsupportedMode(mode.symbol))
			return true
		}
		var arguments = parsed.arguments
		let channelName = stringIsChannelName(arguments.rest)
			? arguments.next()
			: (targetChannel?.isChannel == true ? targetChannel?.name : nil)
		guard let channelName else {
			printDebugInformation(IRCCommandStrings.channelRequired)
			return true
		}
		guard requireArguments(arguments.rest, for: parsed.command) else { return true }
		for change in compileListOfModeChanges(
			forModeSymbol: mode.symbol,
			modeIsSet: mode.isSet,
			parameterString: arguments.rest
		) {
			send("MODE", arguments: [channelName, change])
		}
		return true
	}

	private func dispatchChannelLifecycleCommand(
		_ parsed: ParsedUserCommand,
		targetChannel: IRCChannel?
	) -> Bool {
		guard let command = parsed.localCommand else { return false }
		switch command {
		case .j, .join:
			guard isLoggedIn else { return true }
			joinCommandChannel(parsed, targetChannel: targetChannel)
		case .joinRandom:
			guard isLoggedIn else { return true }
			joinRandomDebugChannels(parsed)
		case .cycle, .hop, .rejoin:
			guard isLoggedIn else { return true }
			guard let targetChannel, targetChannel.isChannel else {
				printDebugInformation(IRCCommandStrings.channelRequired)
				return true
			}
			part(targetChannel)
			forceJoinChannel(targetChannel.name, password: targetChannel.secretKey)
		case .leave, .part:
			guard isLoggedIn else { return true }
			partCommandChannel(parsed, targetChannel: targetChannel)
		default:
			return false
		}
		return true
	}

	private func joinCommandChannel(_ parsed: ParsedUserCommand, targetChannel: IRCChannel?) {
		var arguments = parsed.arguments
		let channelName: String
		if arguments.isEmpty {
			guard let targetChannel, targetChannel.isChannel else {
				printDebugInformation(IRCCommandStrings.channelRequired)
				return
			}
			channelName = targetChannel.name
		} else {
			let requestedChannelName = arguments.next()
			guard requireArguments(requestedChannelName, for: parsed.command) else { return }
			channelName = stringIsChannelNameOrZero(requestedChannelName)
				? requestedChannelName
				: "#\(requestedChannelName)"
		}
		joinUnlistedChannelsAndSelectBestMatch(channelName, passwords: arguments.rest)
	}

	private func joinRandomDebugChannels(_ parsed: ParsedUserCommand) {
		var arguments = parsed.arguments
		let requestedCount = Int(arguments.next()) ?? 1
		// Bounded so that a typo cannot turn into a self-inflicted flood.
		let maximumCount = 20
		let count = min(max(1, requestedCount), maximumCount)
		for _ in 0 ..< count {
			send("JOIN", arguments: ["#debug-channel-\(randomNumber(9_999_999))"])
		}
	}

	private func partCommandChannel(_ parsed: ParsedUserCommand, targetChannel: IRCChannel?) {
		var arguments = parsed.arguments
		let explicitChannel = stringIsChannelName(arguments.rest) ? arguments.next() : nil
		if explicitChannel == nil, let targetChannel, targetChannel.isChannel == false {
			world?.destroy(targetChannel)
			return
		}
		guard let channelName = explicitChannel ?? targetChannel?.name else { return }
		let reason = arguments.isEmpty ? config.normalLeavingComment : arguments.rest
		send("PART", arguments: [channelName, reason])
	}

	private func dispatchChannelNavigationCommand(_ parsed: ParsedUserCommand) -> Bool {
		guard parsed.localCommand == .goto else { return false }
		guard let mainWindow = output else { return true }
		var arguments = parsed.arguments
		let needle = arguments.next()
		guard requireArguments(needle, for: parsed.command) else { return true }
		var bestMatch = mainWindow.selectedItem
		var bestScore: CGFloat = 0
		for client in world?.clientList ?? [] {
			for channel in client.channelList {
				let score = channel.name.matchScore(against: needle, lengthPenaltyWeight: 0.1)
				guard score > bestScore else { continue }
				bestMatch = channel
				bestScore = score
			}
		}
		if let bestMatch {
			mainWindow.selectItem(bestMatch)
		}
		return true
	}

	private func dispatchChannelWindowCommand(
		_ parsed: ParsedUserCommand,
		targetChannel: IRCChannel?
	) -> Bool {
		guard let command = parsed.localCommand else { return false }
		guard let mainWindow = output else { return false }
		switch command {
		case .clear:
			if let targetChannel {
				mainWindow.clearContents(of: targetChannel)
			} else {
				mainWindow.clearContents(of: self)
			}
		case .clearall:
			for client in (world?.clientList ?? [])
				where client === self || environment.preferences.clearAllConnections
			{
				mainWindow.clearContents(of: client)
				client.channelList.forEach { mainWindow.clearContents(of: $0) }
			}
		case .close, .remove:
			closeCommandChannel(parsed, targetChannel: targetChannel)
		case .list:
			guard isLoggedIn else { return true }
			createChannelListDialog()
			requestChannelList()
		case .setcolor:
			setColorForCommandNickname(parsed)
		default:
			return false
		}
		return true
	}

	private func closeCommandChannel(_ parsed: ParsedUserCommand, targetChannel: IRCChannel?) {
		var arguments = parsed.arguments
		let channelName = arguments.next()
		if channelName.isEmpty {
			if let targetChannel {
				world?.destroy(targetChannel)
			}
			return
		}
		guard let channel = findChannel(channelName) else {
			printDebugInformation(IRCCommandStrings.channelNotFound(channelName))
			return
		}
		world?.destroy(channel)
	}

	private func setColorForCommandNickname(_ parsed: ParsedUserCommand) {
		guard environment.preferences.disableNicknameColorHashing == false else {
			printDebugInformation(IRCCommandStrings.nicknameColorsMustBeEnabled)
			return
		}
		var arguments = parsed.arguments
		let nickname = arguments.next().lowercased()
		guard requireArguments(nickname, for: parsed.command) else { return }
		guard stringIsNickname(nickname) else {
			printDebugInformation(IRCCommandStrings.invalidNicknameForColor(nickname))
			return
		}
		menu?.showNicknameColorSheet(forNickname: nickname)
	}

	private func dispatchChannelMembershipCommand(
		_ parsed: ParsedUserCommand,
		targetChannel: IRCChannel?
	) -> Bool {
		guard parsed.localCommand == .invite else { return false }
		guard isLoggedIn else { return true }
		let arguments = parsed.arguments
		guard requireArguments(arguments, for: parsed.command) else { return true }
		var nicknames = arguments.rest.components(separatedBy: .whitespaces)
		let channelName: String?
		if let lastArgument = nicknames.last, stringIsChannelName(lastArgument) {
			channelName = lastArgument
			nicknames.removeLast()
		} else {
			channelName = targetChannel?.isChannel == true ? targetChannel?.name : nil
		}
		guard let channelName else {
			printDebugInformation(IRCCommandStrings.channelRequired)
			return true
		}
		for nickname in nicknames where stringIsNickname(nickname) {
			send("INVITE", arguments: [nickname, channelName])
		}
		return true
	}

	private func dispatchChannelModeCommand(_ parsed: ParsedUserCommand, targetChannel: IRCChannel?) -> Bool {
		let command = parsed.localCommand
		guard command == .modeShortcut || command == .mode else { return false }
		guard isLoggedIn else { return true }
		var arguments = parsed.arguments
		let modeString = arguments.rest
		let usesSelectedTarget = modeString.isEmpty || modeString.hasPrefix("+") || modeString.hasPrefix("-")
		let channelName = usesSelectedTarget
			? (targetChannel?.isChannel == true ? targetChannel?.name : nil)
			: arguments.next()
		guard let channelName else {
			printInvalidSyntaxMessage(for: parsed.command)
			return true
		}
		let parameters = arguments.isEmpty ? [channelName] : [channelName, arguments.rest]
		send("MODE", arguments: parameters)
		return true
	}

	private func dispatchQueryRenameCommand(_ parsed: ParsedUserCommand, targetChannel: IRCChannel?) -> Bool {
		guard parsed.localCommand == .setqueryname else { return false }
		guard let targetChannel, targetChannel.isPrivateMessage else {
			printDebugInformation(IRCCommandStrings.queryRequired)
			return true
		}
		var arguments = parsed.arguments
		let nickname = arguments.next()
		guard requireArguments(nickname, for: parsed.command) else { return true }
		guard stringIsNickname(nickname) else {
			printDebugInformation(IRCCommandStrings.invalidArguments)
			return true
		}
		if let existingQuery = findChannel(nickname) {
			let shouldDelete = TDCAlert.modalAlert(
				withMessage: PromptStrings.Deletion.warning(for: .query),
				title: PromptStrings.Deletion.existingQueryTitle(name: existingQuery.name),
				defaultButton: PromptStrings.Action.yes,
				alternateButton: PromptStrings.Action.no
			)
			guard shouldDelete else { return true }
			world?.destroy(existingQuery)
		}
		targetChannel.name = nickname
		if let mainWindow = output {
			mainWindow.reloadTreeItem(targetChannel)
			mainWindow.updateTitle(for: targetChannel)
		}
		return true
	}

	private func dispatchChannelConversationCommand(
		_ parsed: ParsedUserCommand,
		targetChannel: IRCChannel?
	) -> Bool {
		guard let command = parsed.localCommand else { return false }
		switch command {
		case .query:
			openCommandQuery(parsed)
		case .topicShortcut, .topic:
			guard isLoggedIn else { return true }
			setCommandTopic(parsed, targetChannel: targetChannel)
		default:
			return false
		}
		return true
	}

	private func openCommandQuery(_ parsed: ParsedUserCommand) {
		var arguments = parsed.arguments
		let nickname = arguments.next()
		guard requireArguments(nickname, for: parsed.command) else { return }
		guard stringIsNickname(nickname) else {
			printDebugInformation(IRCCommandStrings.invalidArguments)
			return
		}
		guard let query = findChannelOrCreate(nickname, isPrivateMessage: true),
		      let mainWindow = output
		else { return }
		mainWindow.selectItem(query)
		if arguments.isEmpty == false {
			sendText(arguments.attributedRest, as: .privmsg, to: query)
		}
	}

	private func setCommandTopic(_ parsed: ParsedUserCommand, targetChannel: IRCChannel?) {
		var arguments = parsed.arguments
		let channelName = stringIsChannelName(arguments.rest)
			? arguments.next()
			: (targetChannel?.isChannel == true ? targetChannel?.name : nil)
		guard let channelName else { return }
		let topic = arguments.attributedRest.stringFormattedForIRC
		guard topic.isEmpty == false else {
			send("TOPIC", arguments: [channelName])
			return
		}
		let maximumLength = Int(supportInfo.maximumTopicLength)
		let truncatedTopic = ClientWireUtilities.truncated(topic, toByteCount: maximumLength)
		if truncatedTopic != topic {
			printDebugInformation(
				IRCCommandStrings.topicTooLong(networkName: networkNameAlt, maximumLength: maximumLength)
			)
		}
		send("TOPIC", arguments: [channelName, truncatedTopic])
	}
}
