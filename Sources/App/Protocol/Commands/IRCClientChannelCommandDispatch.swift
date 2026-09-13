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
	let channel: Channel?
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
		_ group: IRCLocalCommand.ChannelGroup,
		parsed: ParsedUserCommand,
		targetChannel: Channel?
	) {
		switch group {
		case .broadcast:
			dispatchBroadcastCommand(parsed)
		case .ctcp:
			dispatchCTCPCommand(parsed, targetChannel: targetChannel)
		case .privilege:
			dispatchUserPrivilegeCommand(parsed, targetChannel: targetChannel)
		case .moderation:
			dispatchChannelModerationCommand(parsed, targetChannel: targetChannel)
		case .lifecycle:
			dispatchChannelLifecycleCommand(parsed, targetChannel: targetChannel)
		case .navigation:
			dispatchChannelNavigationCommand(parsed)
		case .window:
			dispatchChannelWindowCommand(parsed, targetChannel: targetChannel)
		case .membership:
			dispatchChannelMembershipCommand(parsed, targetChannel: targetChannel)
		case .mode:
			dispatchChannelModeCommand(parsed, targetChannel: targetChannel)
		case .queryRename:
			dispatchQueryRenameCommand(parsed, targetChannel: targetChannel)
		case .conversation:
			dispatchChannelConversationCommand(parsed, targetChannel: targetChannel)
		}
	}

	private func dispatchBroadcastCommand(_ parsed: ParsedUserCommand) {
		guard isLoggedIn else { return }
		guard requireArguments(parsed.arguments, for: parsed.command) else { return }
		let remoteCommand: IRCRemoteCommand = parsed.localCommand == .amsg ? .privmsg : .privmsgAction
		for client in (world?.clientList ?? [])
			where client === self || environment.preferences.amsgAllConnections
		{
			let channels = client.channelList.filter { $0.isActive && $0.isChannel }
			client.sendText(parsed.arguments.attributedRest, as: remoteCommand, toChannels: channels)
		}
	}

	private func dispatchCTCPCommand(_ parsed: ParsedUserCommand, targetChannel: Channel?) {
		let command = parsed.localCommand
		guard isLoggedIn else { return }
		var arguments = parsed.arguments
		let selectedChannel = output?.selectedChannel
		let targetName: String
		if let targetChannel, targetChannel !== selectedChannel {
			guard targetChannel.isUtility == false else {
				printDebugInformation(IRCCommandStrings.commandUnavailableInWindow)
				return
			}
			targetName = targetChannel.name
		} else {
			targetName = arguments.next()
		}
		let subcommand = arguments.next().uppercased()
		guard requireArguments(subcommand, for: parsed.command) else { return }
		if command == .ctcpreply {
			sendCTCPReply(targetName, command: subcommand, text: arguments.rest)
		} else if subcommand == "PING" {
			sendCTCPPing(targetName)
		} else {
			sendCTCPQuery(targetName, command: subcommand, text: arguments.rest)
		}
	}

	private func dispatchChannelModerationCommand(
		_ parsed: ParsedUserCommand,
		targetChannel: Channel?
	) {
		guard let command = parsed.localCommand, isLoggedIn else { return }
		var arguments = parsed.arguments
		var nickname = arguments.next()
		let channelName: String
		let channel: Channel?
		if stringIsChannelName(nickname) {
			channelName = nickname
			channel = findChannel(channelName)
			nickname = arguments.next()
		} else if let targetChannel, targetChannel.isChannel {
			channelName = targetChannel.name
			channel = targetChannel
		} else {
			printDebugInformation(IRCCommandStrings.channelRequired)
			return
		}
		guard requireArguments(nickname, for: parsed.command) else { return }
		let invocation = ChannelModerationInvocation(
			command: command,
			channelName: channelName,
			channel: channel,
			nickname: nickname,
			remainingArguments: arguments.rest
		)
		guard applyModerationModeIfNeeded(invocation) else { return }
		applyModerationKickIfNeeded(invocation)
	}

	private func applyModerationModeIfNeeded(_ invocation: ChannelModerationInvocation) -> Bool {
		guard ChannelModerationInvocation.modeCommands.contains(invocation.command) else { return true }
		let modeSymbol: Character = ChannelModerationInvocation.quietCommands.contains(invocation.command) ? "q" : "b"
		guard supportInfo.modeSymbolIsUserPrefix(String(modeSymbol)) == false else {
			printDebugInformation(IRCCommandStrings.unsupportedMode(String(modeSymbol)))
			return false
		}
		let banTarget = invocation.channel?.findMember(invocation.nickname)?.user
		let banMask = banTarget.map(banMask(for:)) ?? invocation.nickname
		let removesMode = ChannelModerationInvocation.removingCommands.contains(invocation.command)
		send("MODE", arguments: [invocation.channelName, "\(removesMode ? "-" : "+")\(modeSymbol)", banMask])
		return true
	}

	private func applyModerationKickIfNeeded(_ invocation: ChannelModerationInvocation) {
		guard ChannelModerationInvocation.kickCommands.contains(invocation.command) else { return }
		let reason = invocation.remainingArguments.isEmpty
			? environment.preferences.defaultKickMessage
			: invocation.remainingArguments
		send("KICK", arguments: [invocation.channelName, invocation.nickname, truncatedKickReason(reason)])
	}

	private func dispatchUserPrivilegeCommand(
		_ parsed: ParsedUserCommand,
		targetChannel: Channel?
	) {
		let mode: (symbol: String, isSet: Bool)? = switch parsed.localCommand {
		case .op: ("o", true)
		case .deop: ("o", false)
		case .halfop: ("h", true)
		case .dehalfop: ("h", false)
		case .voice: ("v", true)
		case .devoice: ("v", false)
		default: nil
		}

		guard let mode, isLoggedIn else { return }
		guard supportInfo.modeSymbolIsUserPrefix(mode.symbol) else {
			printDebugInformation(IRCCommandStrings.unsupportedMode(mode.symbol))
			return
		}
		var arguments = parsed.arguments
		let channelName = stringIsChannelName(arguments.rest)
			? arguments.next()
			: (targetChannel?.isChannel == true ? targetChannel?.name : nil)
		guard let channelName else {
			printDebugInformation(IRCCommandStrings.channelRequired)
			return
		}
		guard requireArguments(arguments.rest, for: parsed.command) else { return }
		/* Each change carries its mode string and its nicknames separately, so
		 nothing has to take a joined string back apart: sent whole,
		 `+ooo alice bob carol` was one parameter and opped nobody. */
		sendModes(
			compileListOfModeChanges(
				forModeSymbol: mode.symbol,
				modeIsSet: mode.isSet,
				parameterString: arguments.rest
			),
			inChannelNamed: channelName
		)
	}

	private func dispatchChannelLifecycleCommand(
		_ parsed: ParsedUserCommand,
		targetChannel: Channel?
	) {
		guard let command = parsed.localCommand else { return }
		switch command {
		case .j, .join:
			guard isLoggedIn else { return }
			joinCommandChannel(parsed, targetChannel: targetChannel)
		case .joinRandom:
			guard isLoggedIn else { return }
			joinRandomDebugChannels(parsed)
		case .cycle, .hop, .rejoin:
			guard isLoggedIn else { return }
			guard let targetChannel, targetChannel.isChannel else {
				printDebugInformation(IRCCommandStrings.channelRequired)
				return
			}
			part(targetChannel)
			forceJoinChannel(targetChannel.name, password: targetChannel.secretKey)
		case .leave, .part:
			guard isLoggedIn else { return }
			partCommandChannel(parsed, targetChannel: targetChannel)
		default:
			break
		}
	}

	private func joinCommandChannel(_ parsed: ParsedUserCommand, targetChannel: Channel?) {
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

	private func partCommandChannel(_ parsed: ParsedUserCommand, targetChannel: Channel?) {
		var arguments = parsed.arguments
		let explicitChannel = stringIsChannelName(arguments.rest) ? arguments.next() : nil
		if explicitChannel == nil, let targetChannel, targetChannel.isChannel == false {
			world?.destroyChannel(targetChannel)
			return
		}
		guard let channelName = explicitChannel ?? targetChannel?.name else { return }
		let reason = arguments.isEmpty ? config.normalLeavingComment : arguments.rest
		send("PART", arguments: [channelName, reason])
	}

	private func dispatchChannelNavigationCommand(_ parsed: ParsedUserCommand) {
		guard let mainWindow = output else { return }
		var arguments = parsed.arguments
		let needle = arguments.next()
		guard requireArguments(needle, for: parsed.command) else { return }
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
			mainWindow.select(bestMatch)
		}
	}

	private func dispatchChannelWindowCommand(
		_ parsed: ParsedUserCommand,
		targetChannel: Channel?
	) {
		guard let command = parsed.localCommand else { return }
		switch command {
		case .clear:
			guard let mainWindow = output else { return }
			if let targetChannel {
				mainWindow.clearContents(of: targetChannel)
			} else {
				mainWindow.clearContents(of: self)
			}
		case .clearall:
			guard let mainWindow = output else { return }
			for client in (world?.clientList ?? [])
				where client === self || environment.preferences.clearAllConnections
			{
				mainWindow.clearContents(of: client)
				client.channelList.forEach { mainWindow.clearContents(of: $0) }
			}
		case .close, .remove:
			closeCommandChannel(parsed, targetChannel: targetChannel)
		case .list:
			guard isLoggedIn else { return }
			openServerChannelList()
		case .setcolor:
			setColorForCommandNickname(parsed)
		default:
			break
		}
	}

	private func closeCommandChannel(_ parsed: ParsedUserCommand, targetChannel: Channel?) {
		var arguments = parsed.arguments
		let channelName = arguments.next()
		if channelName.isEmpty {
			if let targetChannel {
				world?.destroyChannel(targetChannel)
			}
			return
		}
		guard let channel = findChannel(channelName) else {
			printDebugInformation(IRCCommandStrings.channelNotFound(channelName))
			return
		}
		world?.destroyChannel(channel)
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
		targetChannel: Channel?
	) {
		guard isLoggedIn else { return }
		let arguments = parsed.arguments
		guard requireArguments(arguments, for: parsed.command) else { return }
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
			return
		}
		for nickname in nicknames where stringIsNickname(nickname) {
			send("INVITE", arguments: [nickname, channelName])
		}
	}

	private func dispatchChannelModeCommand(_ parsed: ParsedUserCommand, targetChannel: Channel?) {
		guard isLoggedIn else { return }
		var arguments = parsed.arguments
		let modeString = arguments.rest
		let usesSelectedTarget = modeString.isEmpty || modeString.hasPrefix("+") || modeString.hasPrefix("-")
		let channelName = usesSelectedTarget
			? (targetChannel?.isChannel == true ? targetChannel?.name : nil)
			: arguments.next()
		guard let channelName else {
			printInvalidSyntaxMessage(for: parsed.command)
			return
		}
		sendModes(arguments.isEmpty ? nil : arguments.rest, withParametersString: nil, inChannelNamed: channelName)
	}

	private func dispatchQueryRenameCommand(_ parsed: ParsedUserCommand, targetChannel: Channel?) {
		guard let targetChannel, targetChannel.isPrivateMessage else {
			printDebugInformation(IRCCommandStrings.queryRequired)
			return
		}
		var arguments = parsed.arguments
		let nickname = arguments.next()
		guard requireArguments(nickname, for: parsed.command) else { return }
		guard stringIsNickname(nickname) else {
			printDebugInformation(IRCCommandStrings.invalidArguments)
			return
		}
		if let existingQuery = findChannel(nickname) {
			/* Delete/Cancel, not Yes/No: the button says what accepting does, and
			 the destructive role is what tints it and tells VoiceOver the
			 existing conversation is not coming back. */
			let shouldDelete = output?.confirmModally(
				AlertRequest(
					title: PromptStrings.Deletion.existingQueryTitle(name: existingQuery.name),
					body: PromptStrings.Deletion.warning(for: .query),
					defaultButton: PromptStrings.Action.delete,
					alternateButton: PromptStrings.Action.cancel,
					destructiveButton: .default,
					style: .warning
				)
			) ?? true
			guard shouldDelete else { return }
			world?.destroyChannel(existingQuery)
		}
		targetChannel.name = nickname
		if let mainWindow = output {
			mainWindow.reloadTreeItem(targetChannel)
			mainWindow.updateTitle(for: targetChannel)
		}
	}

	private func dispatchChannelConversationCommand(
		_ parsed: ParsedUserCommand,
		targetChannel: Channel?
	) {
		guard let command = parsed.localCommand else { return }
		switch command {
		case .query:
			openCommandQuery(parsed)
		case .topicShortcut, .topic:
			guard isLoggedIn else { return }
			setCommandTopic(parsed, targetChannel: targetChannel)
		default:
			break
		}
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
		mainWindow.select(query)
		if arguments.isEmpty == false {
			sendText(arguments.attributedRest, as: .privmsg, to: query)
		}
	}

	private func setCommandTopic(_ parsed: ParsedUserCommand, targetChannel: Channel?) {
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
		sendTopic(to: topic, inChannelNamed: channelName)
	}
}
