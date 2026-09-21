// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// Help for aliases with the same behavior. Syntax describes the handler's
/// accepted input, including optional targets and management subcommands.
struct SlashCommandHelp {
	let commands: [LocalCommand]
	let description: LocalizedStringResource
	let arguments: LocalizedStringResource?
	let hint: LocalizedStringResource

	private init(
		_ commands: [LocalCommand],
		_ description: LocalizedStringResource,
		_ arguments: LocalizedStringResource? = nil,
		_ hint: LocalizedStringResource = .SlashCommands.hintNoArguments
	) {
		self.commands = commands
		self.description = description
		self.arguments = arguments
		self.hint = hint
	}

	func suggestion(for command: LocalCommand) -> SlashCommandSuggestion {
		let suffix = arguments.map { " " + String(localized: $0) } ?? ""
		return SlashCommandSuggestion(
			name: command.rawValue,
			description: String(localized: description),
			syntax: "/" + command.rawValue + suffix,
			argumentHint: String(localized: hint),
			isScript: false
		)
	}

	static let byCommand: [LocalCommand: SlashCommandHelp] = Dictionary(
		uniqueKeysWithValues: entries.flatMap { help in help.commands.map { ($0, help) } }
	)

	private static let entries: [SlashCommandHelp] = [
		.init(
			[.adchat, .chatops, .globops, .locops, .nachat, .wallops],
			.SlashCommands.descriptionOperatorMessage,
			.SlashCommands.syntaxMessage,
			.SlashCommands.hintOperator
		),
		.init([.ame], .SlashCommands.descriptionBroadcastAction, .SlashCommands.syntaxMessage, .SlashCommands.hintAllJoinedChannels),
		.init([.amsg], .SlashCommands.descriptionBroadcastMessage, .SlashCommands.syntaxMessage, .SlashCommands.hintAllJoinedChannels),
		.init([.aquote, .araw], .SlashCommands.descriptionBroadcastRaw, .SlashCommands.syntaxIrcLine, .SlashCommands.hintIrcProtocolLine),
		.init([.attach], .SlashCommands.descriptionAttach, .SlashCommands.syntaxChannelOptional, .SlashCommands.hintZncChannel),
		.init([.autojoin], .SlashCommands.descriptionAutojoin),
		.init([.away], .SlashCommands.descriptionAway, .SlashCommands.syntaxComment, .SlashCommands.hintOptionalReason),
		.init([.back], .SlashCommands.descriptionClearAwayStatus),
		.init([.ban], .SlashCommands.descriptionBan, .SlashCommands.syntaxChannelNickname, .SlashCommands.hintChannelPrivileges),
		.init([.cap, .caps], .SlashCommands.descriptionCapabilities),
		.init(
			[.chathistory],
			.SlashCommands.descriptionHistory,
			.SlashCommands.syntaxSubcommandTargetArguments,
			.SlashCommands.hintChathistorySubcommands
		),
		.init([.clear], .SlashCommands.descriptionClear),
		.init([.clearall], .SlashCommands.descriptionClearAll),
		.init([.close, .remove], .SlashCommands.descriptionClose, .SlashCommands.syntaxTargetOptional, .SlashCommands.hintTargetOptional),
		.init([.conn], .SlashCommands.descriptionConnect, .SlashCommands.syntaxServerOptional, .SlashCommands.hintReconnectCurrentEndpoint),
		.init([.ctcp], .SlashCommands.descriptionCtcp, .SlashCommands.syntaxNicknameCommandArguments, .SlashCommands.hintCtcp),
		.init([.ctcpreply], .SlashCommands.descriptionCtcpReply, .SlashCommands.syntaxNicknameCommandArguments, .SlashCommands.hintCtcp),
		.init([.cycle, .hop, .rejoin], .SlashCommands.descriptionRejoin),
		.init(
			[.dcc],
			.SlashCommands.descriptionDirectChatFileTransfer,
			.SlashCommands.syntaxChatSendNicknamePath,
			.SlashCommands.hintDirectChatFilePath
		),
		.init(
			[.debug, .echo],
			.SlashCommands.descriptionPrintTextToggleLog,
			.SlashCommands.syntaxMessage,
			.SlashCommands.hintLocalTextProtocolLog
		),
		.init(
			[.defaults],
			.SlashCommands.descriptionAdvancedConnectionSetting,
			.SlashCommands.syntaxHelpEnableDisableFeature,
			.SlashCommands.hintSupportedFeaturesHelp
		),
		.init(
			[.dehalfop],
			.SlashCommands.descriptionRemoveHalfOperator,
			.SlashCommands.syntaxChannelNickname,
			.SlashCommands.hintChannelPrivileges
		),
		.init([.detach], .SlashCommands.descriptionDetach, .SlashCommands.syntaxChannelOptional, .SlashCommands.hintZncChannel),
		.init(
			[.deop],
			.SlashCommands.descriptionRemoveOperator,
			.SlashCommands.syntaxChannelNickname,
			.SlashCommands.hintChannelPrivileges
		),
		.init(
			[.devoice],
			.SlashCommands.descriptionRemoveVoice,
			.SlashCommands.syntaxChannelNickname,
			.SlashCommands.hintChannelPrivileges
		),
		.init([.gline], .SlashCommands.descriptionNetworkBan, .SlashCommands.syntaxMaskDurationReason, .SlashCommands.hintOperator),
		.init(
			[.goto],
			.SlashCommands.descriptionSwitchConversation,
			.SlashCommands.syntaxNameFragment,
			.SlashCommands.hintSearchConversationName
		),
		.init(
			[.gzline, .zline],
			.SlashCommands.descriptionIpAddressBan,
			.SlashCommands.syntaxMaskDurationReason,
			.SlashCommands.hintOperator
		),
		.init([.halfop], .SlashCommands.descriptionHalfop, .SlashCommands.syntaxChannelNickname, .SlashCommands.hintChannelPrivileges),
		.init([.ignore], .SlashCommands.descriptionIgnore, .SlashCommands.syntaxNicknameOptional, .SlashCommands.hintNicknameAddressBook),
		.init([.invite], .SlashCommands.descriptionInvite, .SlashCommands.syntaxNicknamesChannel, .SlashCommands.hintNicknamesChannelLast),
		.init([.ison], .SlashCommands.descriptionCheckOnlineNicknames, .SlashCommands.syntaxNicknames, .SlashCommands.hintNicknames),
		.init(
			[.j, .join],
			.SlashCommands.descriptionJoin,
			.SlashCommands.syntaxChannelsKeys,
			.SlashCommands.hintChannelsCommaSeparatedKeys
		),
		.init([.joinRandom], .SlashCommands.descriptionRandomJoin, .SlashCommands.syntaxCount, .SlashCommands.hintCount),
		.init(
			[.kb, .kickban],
			.SlashCommands.descriptionBanRemoveUser,
			.SlashCommands.syntaxChannelNicknameReason,
			.SlashCommands.hintChannelPrivileges
		),
		.init(
			[.kick],
			.SlashCommands.descriptionRemoveChannelUser,
			.SlashCommands.syntaxChannelNicknameReason,
			.SlashCommands.hintChannelPrivileges
		),
		.init([.kill], .SlashCommands.descriptionDisconnectUser, .SlashCommands.syntaxNicknameReason, .SlashCommands.hintOperator),
		.init([.lagcheck], .SlashCommands.descriptionMeasureRoundTrip),
		.init([.leave, .part], .SlashCommands.descriptionLeaveChannel, .SlashCommands.syntaxChannelReason, .SlashCommands.hintChannel),
		.init([.list], .SlashCommands.descriptionBrowseChannels),
		.init([.modeShortcut, .mode], .SlashCommands.descriptionMode, .SlashCommands.syntaxTargetFlagsArguments, .SlashCommands.hintMode),
		.init([.me, .ume], .SlashCommands.descriptionAction, .SlashCommands.syntaxMessage, .SlashCommands.hintMessage),
		.init(
			[.monitor, .watch],
			.SlashCommands.descriptionOnlineStatusList,
			.SlashCommands.syntaxListStatusClear,
			.SlashCommands.hintListStatusClear
		),
		.init([.msg, .umsg], .SlashCommands.descriptionMessage, .SlashCommands.syntaxMessageTargets, .SlashCommands.hintTargets),
		.init([.mute], .SlashCommands.descriptionMute),
		.init([.mylag], .SlashCommands.descriptionReportConnectionLatency),
		.init([.myversion], .SlashCommands.descriptionVersion),
		.init([.names], .SlashCommands.descriptionNames, .SlashCommands.syntaxChannels, .SlashCommands.hintChannels),
		.init([.nick], .SlashCommands.descriptionNick, .SlashCommands.syntaxNickname, .SlashCommands.hintNickname),
		.init([.notice, .unotice], .SlashCommands.descriptionNotice, .SlashCommands.syntaxMessageTargets, .SlashCommands.hintTargets),
		.init(
			[.notifybubble],
			.SlashCommands.descriptionNotification,
			.SlashCommands.syntaxChannelMessage,
			.SlashCommands.hintNotification
		),
		.init([.notifysound], .SlashCommands.descriptionSound, .SlashCommands.syntaxSound, .SlashCommands.hintSound),
		.init([.omsg], .SlashCommands.descriptionChannelOperatorMessage, .SlashCommands.syntaxOperatorMessage, .SlashCommands.hintChannel),
		.init(
			[.onotice],
			.SlashCommands.descriptionChannelOperatorNotice,
			.SlashCommands.syntaxOperatorMessage,
			.SlashCommands.hintChannel
		),
		.init([.op], .SlashCommands.descriptionGrantOperator, .SlashCommands.syntaxChannelNickname, .SlashCommands.hintChannelPrivileges),
		.init([.pass], .SlashCommands.descriptionPassword, .SlashCommands.syntaxPassword, .SlashCommands.hintPlaceholderValues),
		.init(
			[.query],
			.SlashCommands.descriptionOpenPrivateConversation,
			.SlashCommands.syntaxNicknameMessage,
			.SlashCommands.hintNicknameFirstMessage
		),
		.init(
			[.quiet],
			.SlashCommands.descriptionPreventSpeaking,
			.SlashCommands.syntaxChannelNickname,
			.SlashCommands.hintChannelPrivileges
		),
		.init([.quit], .SlashCommands.descriptionDisconnectNetwork, .SlashCommands.syntaxComment, .SlashCommands.hintOptionalReason),
		.init([.quote, .raw], .SlashCommands.descriptionRaw, .SlashCommands.syntaxIrcLine, .SlashCommands.hintIrcProtocolLine),
		.init([.recv], .SlashCommands.descriptionReceive, .SlashCommands.syntaxIrcLine, .SlashCommands.hintIrcProtocolLine),
		.init([.server], .SlashCommands.descriptionServer, .SlashCommands.syntaxAddressPortPassword, .SlashCommands.hintPortTlsPrefix),
		.init([.setcolor], .SlashCommands.descriptionColor, .SlashCommands.syntaxNickname, .SlashCommands.hintNickname),
		.init([.setname], .SlashCommands.descriptionRealName, .SlashCommands.syntaxRealName, .SlashCommands.hintRealName),
		.init([.setqueryname], .SlashCommands.descriptionQueryName, .SlashCommands.syntaxNickname, .SlashCommands.hintNickname),
		.init(
			[.shun],
			.SlashCommands.descriptionServerUserRestriction,
			.SlashCommands.syntaxMaskDurationReason,
			.SlashCommands.hintOperator
		),
		.init([.silence], .SlashCommands.descriptionSilence, .SlashCommands.syntaxMaskNickname, .SlashCommands.hintAddRemoveMask),
		.init([.sme], .SlashCommands.descriptionSecretAction, .SlashCommands.syntaxMessageTargets, .SlashCommands.hintTargets),
		.init([.smsg], .SlashCommands.descriptionSecretMessage, .SlashCommands.syntaxMessageTargets, .SlashCommands.hintTargets),
		.init([.sslcontext], .SlashCommands.descriptionCertificate),
		.init([.topicShortcut, .topic], .SlashCommands.descriptionTopic, .SlashCommands.syntaxTopic, .SlashCommands.hintTopic),
		.init([.tage], .SlashCommands.descriptionReportProjectTime),
		.init([.tempshun], .SlashCommands.descriptionTemporaryShun, .SlashCommands.syntaxMaskNicknameReason, .SlashCommands.hintOperator),
		.init(
			[.timer],
			.SlashCommands.descriptionTimer,
			.SlashCommands.syntaxSecondsRepeatCommand,
			.SlashCommands.hintSecondsRepeatManagement
		),
		.init([.umode], .SlashCommands.descriptionUserMode, .SlashCommands.syntaxFlagsArguments, .SlashCommands.hintPlaceholderValues),
		.init([.unban], .SlashCommands.descriptionRemoveBan, .SlashCommands.syntaxChannelNickname, .SlashCommands.hintChannelPrivileges),
		.init(
			[.unignore],
			.SlashCommands.descriptionRemoveIgnoreRule,
			.SlashCommands.syntaxNicknameOptional,
			.SlashCommands.hintNicknameAddressBook
		),
		.init([.unmute], .SlashCommands.descriptionRestoreNotificationSounds),
		.init(
			[.unquiet],
			.SlashCommands.descriptionRestoreSpeaking,
			.SlashCommands.syntaxChannelNickname,
			.SlashCommands.hintChannelPrivileges
		),
		.init([.voice], .SlashCommands.descriptionVoice, .SlashCommands.syntaxChannelNickname, .SlashCommands.hintChannelPrivileges),
		.init([.weights], .SlashCommands.descriptionNicknameCompletionPriorities),
		.init(
			[.who],
			.SlashCommands.descriptionMatchingUserInformation,
			.SlashCommands.syntaxChannelMaskFlags,
			.SlashCommands.hintPlaceholderValues
		),
		.init(
			[.whois],
			.SlashCommands.descriptionUserInformation,
			.SlashCommands.syntaxNicknameOptional,
			.SlashCommands.hintNicknamePrivateConversation
		),
		.init([.whowas], .SlashCommands.descriptionPreviousNickname, .SlashCommands.syntaxNickname, .SlashCommands.hintNickname),
		.init([.znccert], .SlashCommands.descriptionZncCertificate),
	]
}
