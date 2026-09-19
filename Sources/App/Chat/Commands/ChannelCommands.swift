// Copyright (c) 2010 - 2019 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

private struct ChannelModerationInvocation {
	let command: LocalCommand
	let channelName: String
	let channel: Conversation?
	let nickname: String
	let remainingArguments: String

	/// The moderation commands that set or clear a list mode before, or
	/// instead of, kicking.
	static let modeCommands: Set<LocalCommand> = [.ban, .kb, .kickban, .quiet, .unban, .unquiet]

	static let kickCommands: Set<LocalCommand> = [.kb, .kick, .kickban]

	static let removingCommands: Set<LocalCommand> = [.unban, .unquiet]

	static let quietCommands: Set<LocalCommand> = [.quiet, .unquiet]
}

@MainActor
extension ServerSession {
	func dispatchBroadcastCommand(_ command: LocalCommand, parsed: ParsedUserCommand) {
		guard isLoggedIn else { return }
		guard requireArguments(parsed.arguments, for: parsed.command) else { return }
		let remoteCommand: RemoteCommand = command == .amsg ? .privmsg : .privmsgAction
		for session in broadcastTargets(whenAllConnections: environment.settings.amsgAllConnections) {
			let channels = session.conversationList.filter { $0.isActive && $0.isChannel }
			session.sendText(parsed.arguments.attributedRest, as: remoteCommand, toConversations: channels)
		}
	}

	func dispatchCTCPCommand(
		_ command: LocalCommand,
		parsed: ParsedUserCommand,
		targetConversation: Conversation?
	) {
		guard isLoggedIn else { return }
		var arguments = parsed.arguments
		let selectedConversation = output?.selectedConversation
		let targetName: String
		if let targetConversation, targetConversation !== selectedConversation {
			guard targetConversation.isConsole == false else {
				printDebugInformation(String(localized: .IRC.thisCommandCannotBeUsedWithin))
				return
			}
			targetName = targetConversation.name
		} else {
			targetName = arguments.next()
		}
		let subcommand = arguments.next().uppercased()
		guard requireArguments(subcommand, for: parsed.command) else { return }
		if command == .ctcpreply {
			sendCTCPReply(targetName, command: subcommand, text: arguments.rest)
		} else if CTCPVerb(wireName: subcommand) == .ping {
			sendCTCPPing(targetName)
		} else {
			sendCTCPQuery(targetName, command: subcommand, text: arguments.rest)
		}
	}

	func dispatchChannelModerationCommand(
		_ command: LocalCommand,
		parsed: ParsedUserCommand,
		targetConversation: Conversation?
	) {
		guard isLoggedIn else { return }
		var arguments = parsed.arguments
		var nickname = arguments.next()
		let channelName: String
		let channel: Conversation?
		if stringIsChannelName(nickname) {
			channelName = nickname
			channel = findConversation(channelName)
			nickname = arguments.next()
		} else if let targetConversation, targetConversation.isChannel {
			channelName = targetConversation.name
			channel = targetConversation
		} else {
			printDebugInformation(String(localized: .IRC.thisCommandCanOnlyBeUsed))
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
			printDebugInformation(String(localized: .IRC.modeIsNotSupported(String(modeSymbol))))
			return false
		}
		let banTarget = invocation.channel?.findMember(invocation.nickname)?.user
		let banMask = banTarget.map(banMask(for:)) ?? invocation.nickname
		let removesMode = ChannelModerationInvocation.removingCommands.contains(invocation.command)
		send(.mode, arguments: [invocation.channelName, "\(removesMode ? "-" : "+")\(modeSymbol)", banMask])
		return true
	}

	private func applyModerationKickIfNeeded(_ invocation: ChannelModerationInvocation) {
		guard ChannelModerationInvocation.kickCommands.contains(invocation.command) else { return }
		let reason = invocation.remainingArguments.isEmpty
			? environment.settings.defaultKickMessage
			: invocation.remainingArguments
		send(.kick, arguments: [invocation.channelName, invocation.nickname, truncatedKickReason(reason)])
	}

	/** A mode change on a channel: either a `/op`-style shorthand, which names one
	 mode letter and reads the rest of the line as nicknames, or `/mode` itself,
	 where the letters are the user's and the server reads them. */
	func dispatchChannelModeCommand(
		_ command: LocalCommand,
		parsed: ParsedUserCommand,
		targetConversation: Conversation?
	) {
		guard isLoggedIn else { return }

		let mode: (symbol: String, isSet: Bool)? = switch command {
		case .op: ("o", true)
		case .deop: ("o", false)
		case .halfop: ("h", true)
		case .dehalfop: ("h", false)
		case .voice: ("v", true)
		case .devoice: ("v", false)
		default: nil
		}

		guard let mode else {
			sendModesFromCommandLine(parsed, targetConversation: targetConversation)
			return
		}

		guard supportInfo.modeSymbolIsUserPrefix(mode.symbol) else {
			printDebugInformation(String(localized: .IRC.modeIsNotSupported(mode.symbol)))
			return
		}
		var arguments = parsed.arguments
		let channelName = stringIsChannelName(arguments.rest)
			? arguments.next()
			: (targetConversation?.isChannel == true ? targetConversation?.name : nil)
		guard let channelName else {
			printDebugInformation(String(localized: .IRC.thisCommandCanOnlyBeUsed))
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

	func dispatchChannelLifecycleCommand(
		_ command: LocalCommand,
		parsed: ParsedUserCommand,
		targetConversation: Conversation?
	) {
		switch command {
		case .j, .join:
			guard isLoggedIn else { return }
			joinCommandChannel(parsed, targetConversation: targetConversation)
		case .joinRandom:
			guard isLoggedIn else { return }
			joinRandomDebugChannels(parsed)
		case .cycle, .hop, .rejoin:
			guard isLoggedIn else { return }
			guard let targetConversation, targetConversation.isChannel else {
				printDebugInformation(String(localized: .IRC.thisCommandCanOnlyBeUsed))
				return
			}
			part(targetConversation)
			forceJoinChannel(targetConversation.name, password: targetConversation.secretKey)
		case .leave, .part:
			guard isLoggedIn else { return }
			partCommandChannel(parsed, targetConversation: targetConversation)
		case .invite:
			inviteCommandNicknames(parsed, targetConversation: targetConversation)
		default:
			break
		}
	}

	private func joinCommandChannel(_ parsed: ParsedUserCommand, targetConversation: Conversation?) {
		var arguments = parsed.arguments
		let channelName: String
		if arguments.isEmpty {
			guard let targetConversation, targetConversation.isChannel else {
				printDebugInformation(String(localized: .IRC.thisCommandCanOnlyBeUsed))
				return
			}
			channelName = targetConversation.name
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
			send(.join, arguments: ["#debug-channel-\(UInt32.random(in: 0 ..< 9_999_999))"])
		}
	}

	private func partCommandChannel(_ parsed: ParsedUserCommand, targetConversation: Conversation?) {
		var arguments = parsed.arguments
		let explicitChannel = stringIsChannelName(arguments.rest) ? arguments.next() : nil
		if explicitChannel == nil, let targetConversation, targetConversation.isChannel == false {
			chatSession?.destroyConversation(targetConversation)
			return
		}
		guard let channelName = explicitChannel ?? targetConversation?.name else { return }
		let reason = arguments.isEmpty ? config.normalLeavingComment : arguments.rest
		send(.part, arguments: [channelName, reason])
	}

	private func selectBestMatchingConversation(_ parsed: ParsedUserCommand) {
		guard let mainWindow = output else { return }
		var arguments = parsed.arguments
		let needle = arguments.next()
		guard requireArguments(needle, for: parsed.command) else { return }
		var bestMatch = mainWindow.selectedItem
		var bestScore: CGFloat = 0
		for session in allSessions {
			for conversation in session.conversationList {
				let score = conversation.name.matchScore(against: needle, lengthPenaltyWeight: 0.1)
				guard score > bestScore else { continue }
				bestMatch = conversation
				bestScore = score
			}
		}
		if let bestMatch {
			mainWindow.select(bestMatch)
		}
	}

	func dispatchConversationWindowCommand(
		_ command: LocalCommand,
		parsed: ParsedUserCommand,
		targetConversation: Conversation?
	) {
		switch command {
		case .clear:
			guard let mainWindow = output else { return }
			if let targetConversation {
				mainWindow.clearContents(of: targetConversation)
			} else {
				mainWindow.clearContents(of: self)
			}
		case .clearall:
			guard let mainWindow = output else { return }
			for session in broadcastTargets(whenAllConnections: environment.settings.clearAllConnections) {
				mainWindow.clearContents(of: session)
				session.conversationList.forEach { mainWindow.clearContents(of: $0) }
			}
		case .close, .remove:
			closeCommandConversation(parsed, targetConversation: targetConversation)
		case .list:
			guard isLoggedIn else { return }
			channelListPresentation?.openChannelList(for: self)
		case .setcolor:
			setColorForCommandNickname(parsed)
		case .goto:
			selectBestMatchingConversation(parsed)
		default:
			break
		}
	}

	private func closeCommandConversation(_ parsed: ParsedUserCommand, targetConversation: Conversation?) {
		var arguments = parsed.arguments
		let name = arguments.next()
		if name.isEmpty {
			if let targetConversation {
				chatSession?.destroyConversation(targetConversation)
			}
			return
		}
		guard let conversation = findConversation(name) else {
			printDebugInformation(String(localized: .IRC.cannotFindChannelNamed(name)))
			return
		}
		chatSession?.destroyConversation(conversation)
	}

	private func setColorForCommandNickname(_ parsed: ParsedUserCommand) {
		guard environment.settings.disableNicknameColorHashing == false else {
			printDebugInformation(String(localized: .IRC.thisCommandCannotBeUsedUnless))
			return
		}
		var arguments = parsed.arguments
		let nickname = arguments.next().lowercased()
		guard requireArguments(nickname, for: parsed.command) else { return }
		guard stringIsNickname(nickname) else {
			printDebugInformation(String(localized: .IRC.cannotSetColorForBecause(nickname)))
			return
		}
		menu?.showNicknameColorSheet(forNickname: nickname)
	}

	private func inviteCommandNicknames(_ parsed: ParsedUserCommand, targetConversation: Conversation?) {
		guard isLoggedIn else { return }
		let arguments = parsed.arguments
		guard requireArguments(arguments, for: parsed.command) else { return }
		var nicknames = arguments.rest.components(separatedBy: .whitespaces)
		let channelName: String?
		if let lastArgument = nicknames.last, stringIsChannelName(lastArgument) {
			channelName = lastArgument
			nicknames.removeLast()
		} else {
			channelName = targetConversation?.isChannel == true ? targetConversation?.name : nil
		}
		guard let channelName else {
			printDebugInformation(String(localized: .IRC.thisCommandCanOnlyBeUsed))
			return
		}
		for nickname in nicknames where stringIsNickname(nickname) {
			send(.invite, arguments: [nickname, channelName])
		}
	}

	private func sendModesFromCommandLine(_ parsed: ParsedUserCommand, targetConversation: Conversation?) {
		var arguments = parsed.arguments
		let modeString = arguments.rest
		let usesSelectedTarget = modeString.isEmpty || modeString.hasPrefix("+") || modeString.hasPrefix("-")
		let channelName = usesSelectedTarget
			? (targetConversation?.isChannel == true ? targetConversation?.name : nil)
			: arguments.next()
		guard let channelName else {
			printInvalidSyntaxMessage(for: parsed.command)
			return
		}
		sendModes(arguments.isEmpty ? nil : arguments.rest, withParametersString: nil, inChannelNamed: channelName)
	}

	private func retitleCommandDirectConversation(_ parsed: ParsedUserCommand, targetConversation: Conversation?) {
		guard let targetConversation, targetConversation.isDirect else {
			printDebugInformation(String(localized: .IRC.thisCommandCanOnlyBeUsedWithAQuery))
			return
		}
		var arguments = parsed.arguments
		let nickname = arguments.next()
		guard requireArguments(nickname, for: parsed.command) else { return }
		guard stringIsNickname(nickname) else {
			printDebugInformation(String(localized: .IRC.oneOrMoreArgumentsAreNot))
			return
		}
		/* The conversation being retitled is what a change of case finds, and it
		 is not the other conversation the prompt offers to delete. */
		if let existingConversation = findConversation(nickname), existingConversation !== targetConversation {
			/* Delete/Cancel, not Yes/No: the button says what accepting does, and
			 the destructive role is what tints it and tells VoiceOver the
			 existing conversation is not coming back. */
			let originalName = targetConversation.name
			requestConfirmation(
				AlertRequest(
					title: PromptStrings.Deletion.existingQueryTitle(name: existingConversation.name),
					body: PromptStrings.Deletion.warning(for: .query),
					defaultButton: PromptStrings.Action.delete,
					alternateButton: PromptStrings.Action.cancel,
					destructiveButton: .default,
					style: .warning
				),
				isCurrent: { session in
					session.conversationList.contains { $0 === targetConversation }
						&& targetConversation.name == originalName
						&& session.findConversation(nickname) === existingConversation
				},
				perform: { session in
					session.chatSession?.destroyConversation(existingConversation)
					session.retitleDirectConversation(targetConversation, from: originalName, to: nickname)
				}
			)
			return
		}
		retitleDirectConversation(targetConversation, from: targetConversation.name, to: nickname)
	}

	func dispatchConversationCommand(
		_ command: LocalCommand,
		parsed: ParsedUserCommand,
		targetConversation: Conversation?
	) {
		switch command {
		case .query:
			openCommandDirectConversation(parsed)
		case .topicShortcut, .topic:
			guard isLoggedIn else { return }
			setCommandTopic(parsed, targetConversation: targetConversation)
		case .setqueryname:
			retitleCommandDirectConversation(parsed, targetConversation: targetConversation)
		default:
			break
		}
	}

	private func openCommandDirectConversation(_ parsed: ParsedUserCommand) {
		var arguments = parsed.arguments
		let nickname = arguments.next()
		guard requireArguments(nickname, for: parsed.command) else { return }
		guard stringIsNickname(nickname) else {
			printDebugInformation(String(localized: .IRC.oneOrMoreArgumentsAreNot))
			return
		}
		guard let directConversation = findConversationOrCreate(nickname, isDirect: true),
		      let mainWindow = output
		else { return }
		mainWindow.select(directConversation)
		if arguments.isEmpty == false {
			sendText(arguments.attributedRest, as: .privmsg, to: directConversation)
		}
	}

	private func setCommandTopic(_ parsed: ParsedUserCommand, targetConversation: Conversation?) {
		var arguments = parsed.arguments
		let channelName = stringIsChannelName(arguments.rest)
			? arguments.next()
			: (targetConversation?.isChannel == true ? targetConversation?.name : nil)
		guard let channelName else { return }
		let topic = arguments.attributedRest.stringFormattedForIRC
		guard topic.isEmpty == false else {
			send(.topic, arguments: [channelName])
			return
		}
		sendTopic(to: topic, inChannelNamed: channelName)
	}
}
