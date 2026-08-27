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

private struct ChannelModerationInvocation {
	let command: String
	let channelName: String
	let channel: IRCChannel?
	let nickname: String
	let remainingArguments: String
}

@MainActor
extension IRCClient {
	func dispatchNativeChannelCommand(
		_ parsed: ParsedUserCommand,
		targetChannel: IRCChannel?
	) -> Bool {
		dispatchBroadcastCommand(parsed) ||
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
		let command = parsed.command.lowercased()
		guard command == "ame" || command == "amsg" else { return false }
		guard isLoggedIn else { return true }
		guard requireArguments(parsed.arguments.string, for: parsed.command) else { return true }
		let remoteCommand: IRCRemoteCommand = command == "amsg" ? .privmsg : .privmsgAction
		for client in NSObject.applicationController().world.clientList
			where client === self || TextualPreferences.amsgAllConnections()
		{
			let channels = client.channelList.filter { $0.isActive && $0.isChannel }
			client.sendText(parsed.arguments, as: remoteCommand, toChannels: channels)
		}
		return true
	}

	private func dispatchCTCPCommand(_ parsed: ParsedUserCommand, targetChannel: IRCChannel?) -> Bool {
		let command = parsed.command.lowercased()
		guard command == "ctcp" || command == "ctcpreply" else { return false }
		guard isLoggedIn else { return true }
		let arguments = NSMutableAttributedString(attributedString: parsed.arguments)
		let selectedChannel = NSObject.applicationController().mainWindow?.selectedChannel
		let targetName: String
		if let targetChannel, targetChannel !== selectedChannel {
			guard targetChannel.isUtility == false else {
				printDebugInformation(IRCCommandStrings.commandUnavailableInWindow)
				return true
			}
			targetName = targetChannel.name
		} else {
			targetName = arguments.ceTokenAsString
		}
		let subcommand = arguments.ceTokenAsString.uppercased()
		guard requireArguments(subcommand, for: parsed.command) else { return true }
		if command == "ctcpreply" {
			sendCTCPReply(targetName, command: subcommand, text: arguments.string)
		} else if subcommand == "PING" {
			sendCTCPPing(targetName)
		} else {
			sendCTCPQuery(targetName, command: subcommand, text: arguments.string)
		}
		return true
	}

	private func dispatchChannelModerationCommand(
		_ parsed: ParsedUserCommand,
		targetChannel: IRCChannel?
	) -> Bool {
		let supportedCommands = ["ban", "kb", "kick", "kickban", "quiet", "unban", "unquiet"]
		let command = parsed.command.lowercased()
		guard supportedCommands.contains(command) else { return false }
		guard isLoggedIn else { return true }
		let arguments = NSMutableAttributedString(attributedString: parsed.arguments)
		var nickname = arguments.ceTokenAsString
		let channelName: String
		let channel: IRCChannel?
		if stringIsChannelName(nickname) {
			channelName = nickname
			channel = findChannel(channelName)
			nickname = arguments.ceTokenAsString
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
			remainingArguments: arguments.string
		)
		guard applyModerationModeIfNeeded(invocation) else { return true }
		applyModerationKickIfNeeded(invocation)
		return true
	}

	private func applyModerationModeIfNeeded(_ invocation: ChannelModerationInvocation) -> Bool {
		let modeCommands = ["ban", "kb", "kickban", "quiet", "unban", "unquiet"]
		guard modeCommands.contains(invocation.command) else { return true }
		let modeSymbol = ["quiet", "unquiet"].contains(invocation.command) ? "q" : "b"
		guard supportInfo.modeSymbolIsUserPrefix(modeSymbol) == false else {
			printDebugInformation(IRCCommandStrings.unsupportedMode(modeSymbol))
			return false
		}
		let banMask = invocation.channel?.findMember(invocation.nickname)?.user.banMask ?? invocation.nickname
		let removesMode = ["unban", "unquiet"].contains(invocation.command)
		send("MODE", arguments: [invocation.channelName, "\(removesMode ? "-" : "+")\(modeSymbol)", banMask])
		return true
	}

	private func applyModerationKickIfNeeded(_ invocation: ChannelModerationInvocation) {
		guard ["kb", "kick", "kickban"].contains(invocation.command) else { return }
		let reason = invocation.remainingArguments.isEmpty
			? TextualPreferences.defaultKickMessage()
			: invocation.remainingArguments
		let maximumLength = Int(supportInfo.maximumKickLength)
		if maximumLength > 0, (reason as NSString).length > maximumLength {
			printDebugInformation(
				IRCCommandStrings.kickMessageTooLong(networkName: networkNameAlt, maximumLength: maximumLength)
			)
		}
		send("KICK", arguments: [invocation.channelName, invocation.nickname, reason])
	}

	private func dispatchUserPrivilegeCommand(
		_ parsed: ParsedUserCommand,
		targetChannel: IRCChannel?
	) -> Bool {
		let mode: (symbol: String, isSet: Bool)? = switch parsed.command.lowercased() {
		case "op": ("o", true)
		case "deop": ("o", false)
		case "halfop": ("h", true)
		case "dehalfop": ("h", false)
		case "voice": ("v", true)
		case "devoice": ("v", false)
		default: nil
		}
		guard let mode else { return false }
		guard isLoggedIn else { return true }
		guard supportInfo.modeSymbolIsUserPrefix(mode.symbol) else {
			printDebugInformation(IRCCommandStrings.unsupportedMode(mode.symbol))
			return true
		}
		let arguments = NSMutableAttributedString(attributedString: parsed.arguments)
		let channelName = stringIsChannelName(arguments.string)
			? arguments.ceTokenAsString
			: (targetChannel?.isChannel == true ? targetChannel?.name : nil)
		guard let channelName else {
			printDebugInformation(IRCCommandStrings.channelRequired)
			return true
		}
		guard requireArguments(arguments.string, for: parsed.command) else { return true }
		for change in compileListOfModeChanges(
			forModeSymbol: mode.symbol,
			modeIsSet: mode.isSet,
			parameterString: arguments.string
		) {
			send("MODE", arguments: [channelName, change])
		}
		return true
	}

	private func dispatchChannelLifecycleCommand(
		_ parsed: ParsedUserCommand,
		targetChannel: IRCChannel?
	) -> Bool {
		let command = parsed.command.lowercased()
		switch command {
		case "j", "join":
			guard isLoggedIn else { return true }
			let arguments = NSMutableAttributedString(attributedString: parsed.arguments)
			let channelName: String
			if arguments.length == 0 {
				guard let targetChannel, targetChannel.isChannel else {
					printDebugInformation(IRCCommandStrings.channelRequired)
					return true
				}
				channelName = targetChannel.name
			} else {
				let requestedChannelName = arguments.ceTokenAsString
				guard requireArguments(requestedChannelName, for: parsed.command) else { return true }
				channelName = stringIsChannelNameOrZero(requestedChannelName)
					? requestedChannelName
					: "#\(requestedChannelName)"
			}
			joinUnlistedChannelsAndSelectBestMatch(channelName, passwords: arguments.string)
		case "join_random":
			guard isLoggedIn else { return true }
			let arguments = NSMutableAttributedString(attributedString: parsed.arguments)
			let requestedCount = Int(arguments.ceTokenAsString) ?? 1
			for _ in 0 ..< max(1, requestedCount) {
				send("JOIN", arguments: ["#debug-channel-\(randomNumber(9_999_999))"])
			}
		case "cycle", "hop", "rejoin":
			guard isLoggedIn else { return true }
			guard let targetChannel, targetChannel.isChannel else {
				printDebugInformation(IRCCommandStrings.channelRequired)
				return true
			}
			part(targetChannel)
			forceJoinChannel(targetChannel.name, password: targetChannel.secretKey)
		case "leave", "part":
			guard isLoggedIn else { return true }
			let mutableArguments = NSMutableAttributedString(attributedString: parsed.arguments)
			let explicitChannel = stringIsChannelName(mutableArguments.string)
				? mutableArguments.ceTokenAsString
				: nil
			if explicitChannel == nil, let targetChannel, targetChannel.isChannel == false {
				NSObject.applicationController().world.destroy(targetChannel)
				return true
			}
			guard let channelName = explicitChannel ?? targetChannel?.name else { return true }
			let reason = mutableArguments.string.isEmpty
				? config.normalLeavingComment
				: mutableArguments.string
			send("PART", arguments: [channelName, reason])
		default:
			return false
		}
		return true
	}

	private func dispatchChannelNavigationCommand(_ parsed: ParsedUserCommand) -> Bool {
		guard parsed.command.caseInsensitiveCompare("goto") == .orderedSame else { return false }
		guard let mainWindow = NSObject.applicationController().mainWindow else { return true }
		let arguments = NSMutableAttributedString(attributedString: parsed.arguments)
		let needle = arguments.ceTokenAsString
		guard requireArguments(needle, for: parsed.command) else { return true }
		var bestMatch = mainWindow.selectedItem
		var bestScore: CGFloat = 0
		for client in NSObject.applicationController().world.clientList {
			for channel in client.channelList {
				let score = (channel.name as NSString).ce_compare(with: needle, lengthPenaltyWeight: 0.1)
				guard score > bestScore else { continue }
				bestMatch = commandTreeItem(for: channel)
				bestScore = score
			}
		}
		if let bestMatch {
			mainWindow.select(bestMatch)
		}
		return true
	}

	private func dispatchChannelWindowCommand(
		_ parsed: ParsedUserCommand,
		targetChannel: IRCChannel?
	) -> Bool {
		guard let mainWindow = NSObject.applicationController().mainWindow else { return false }
		switch parsed.command.lowercased() {
		case "clear":
			if let targetChannel {
				mainWindow.clearContents(of: targetChannel)
			} else {
				mainWindow.clearContents(of: self)
			}
		case "clearall":
			for client in NSObject.applicationController().world.clientList
				where client === self || TextualPreferences.clearAllConnections()
			{
				mainWindow.clearContents(of: client)
				client.channelList.forEach { mainWindow.clearContents(of: $0) }
			}
		case "close", "remove":
			let arguments = NSMutableAttributedString(attributedString: parsed.arguments)
			let channelName = arguments.ceTokenAsString
			if channelName.isEmpty {
				if let targetChannel {
					NSObject.applicationController().world.destroy(targetChannel)
				}
				return true
			}
			guard let channel = findChannel(channelName) else {
				printDebugInformation(IRCCommandStrings.channelNotFound(channelName))
				return true
			}
			NSObject.applicationController().world.destroy(channel)
		case "list":
			guard isLoggedIn else { return true }
			createChannelListDialog()
			requestChannelList()
		case "setcolor":
			guard TextualPreferences.disableNicknameColorHashing() == false else {
				printDebugInformation(IRCCommandStrings.nicknameColorsMustBeEnabled)
				return true
			}
			let arguments = NSMutableAttributedString(attributedString: parsed.arguments)
			let nickname = arguments.ceTokenAsString.lowercased()
			guard requireArguments(nickname, for: parsed.command) else { return true }
			guard stringIsNickname(nickname) else {
				printDebugInformation(IRCCommandStrings.invalidNicknameForColor(nickname))
				return true
			}
			NSObject.applicationController().menuController?.memberChangeColor(nickname)
		default:
			return false
		}
		return true
	}

	private func dispatchChannelMembershipCommand(
		_ parsed: ParsedUserCommand,
		targetChannel: IRCChannel?
	) -> Bool {
		guard parsed.command.caseInsensitiveCompare("invite") == .orderedSame else { return false }
		guard isLoggedIn else { return true }
		let arguments = parsed.arguments.string
		guard requireArguments(arguments, for: parsed.command) else { return true }
		var nicknames = arguments.components(separatedBy: .whitespaces)
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
		guard ["m", "mode"].contains(parsed.command.lowercased()) else { return false }
		guard isLoggedIn else { return true }
		let arguments = NSMutableAttributedString(attributedString: parsed.arguments)
		let modeString = arguments.string
		let usesSelectedTarget = modeString.isEmpty || modeString.hasPrefix("+") || modeString.hasPrefix("-")
		let channelName = usesSelectedTarget
			? (targetChannel?.isChannel == true ? targetChannel?.name : nil)
			: arguments.ceTokenAsString
		guard let channelName else {
			printInvalidSyntaxMessage(for: parsed.command)
			return true
		}
		let parameters = arguments.string.isEmpty ? [channelName] : [channelName, arguments.string]
		send("MODE", arguments: parameters)
		return true
	}

	private func dispatchQueryRenameCommand(_ parsed: ParsedUserCommand, targetChannel: IRCChannel?) -> Bool {
		guard parsed.command.caseInsensitiveCompare("setqueryname") == .orderedSame else { return false }
		guard let targetChannel, targetChannel.isPrivateMessage else {
			printDebugInformation(IRCCommandStrings.queryRequired)
			return true
		}
		let arguments = NSMutableAttributedString(attributedString: parsed.arguments)
		let nickname = arguments.ceTokenAsString
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
			NSObject.applicationController().world.destroy(existingQuery)
		}
		targetChannel.name = nickname
		if let mainWindow = NSObject.applicationController().mainWindow {
			let treeItem = commandTreeItem(for: targetChannel)
			mainWindow.reloadTreeItem(treeItem)
			mainWindow.updateTitle(for: treeItem)
		}
		return true
	}

	private func dispatchChannelConversationCommand(
		_ parsed: ParsedUserCommand,
		targetChannel: IRCChannel?
	) -> Bool {
		switch parsed.command.lowercased() {
		case "query":
			let arguments = NSMutableAttributedString(attributedString: parsed.arguments)
			let nickname = arguments.ceTokenAsString
			guard requireArguments(nickname, for: parsed.command) else { return true }
			guard stringIsNickname(nickname) else {
				printDebugInformation(IRCCommandStrings.invalidArguments)
				return true
			}
			guard let query = findChannelOrCreate(nickname, isPrivateMessage: true),
			      let mainWindow = NSObject.applicationController().mainWindow
			else { return true }
			mainWindow.select(commandTreeItem(for: query))
			if arguments.length > 0 {
				sendText(arguments, as: .privmsg, to: query)
			}
		case "t", "topic":
			guard isLoggedIn else { return true }
			let arguments = NSMutableAttributedString(attributedString: parsed.arguments)
			let channelName = stringIsChannelName(arguments.string)
				? arguments.ceTokenAsString
				: (targetChannel?.isChannel == true ? targetChannel?.name : nil)
			guard let channelName else { return true }
			let topic = arguments.stringFormattedForIRC
			guard topic.isEmpty == false else {
				send("TOPIC", arguments: [channelName])
				return true
			}
			let maximumLength = Int(supportInfo.maximumTopicLength)
			if maximumLength > 0, (topic as NSString).length > maximumLength {
				printDebugInformation(
					IRCCommandStrings.topicTooLong(networkName: networkNameAlt, maximumLength: maximumLength)
				)
			}
			send("TOPIC", arguments: [channelName, topic])
		default:
			return false
		}
		return true
	}

	private func commandTreeItem(for channel: IRCChannel) -> IRCTreeItem {
		guard let treeItem = (channel as AnyObject) as? IRCTreeItem else {
			preconditionFailure("IRCChannel must bridge to its Objective-C tree item")
		}
		return treeItem
	}
}
