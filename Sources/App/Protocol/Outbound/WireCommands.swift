// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import os

private nonisolated let wireCommandLogger = Logger(
	subsystem: LogSubsystem.current,
	category: "WireCommands"
)

/// How many nicknames one `MONITOR +`/`WATCH` command carries when the server
/// has not said otherwise. Small enough that no line approaches the byte limit
/// whatever the nicknames are.
private let watchListGroupSize = 8

@MainActor
extension ServerSession {
	func changeNickname(_ nickname: String) {
		guard isConnected, nickname.isEmpty == false else { return }
		/* `NICKLEN` is a byte budget like the rest, and a server given a longer
		 nickname picks the truncation itself — which for anything but ASCII
		 lands mid-character. */
		send(.nick, arguments: [truncated(nickname, toLimit: supportInfo.maximumNicknameLength)])
	}

	func part(_ channel: Conversation, withComment comment: String? = nil) {
		guard isLoggedIn, channel.isChannel, channel.isActive else { return }
		send(.part, arguments: [channel.name, comment ?? config.normalLeavingComment])
	}

	func sendWho(to channel: Conversation, hideResponse: Bool = false) {
		guard channel.isChannel else { return }
		sendWho(toChannelNamed: channel.name, hideResponse: hideResponse)
	}

	func sendWho(toChannelNamed channelName: String, hideResponse: Bool = false) {
		guard isLoggedIn, channelName.isEmpty == false else { return }
		if hideResponse {
			requestedCommands.recordWhoRequestOpened()
		} else {
			requestedCommands.recordWhoRequestOpenedAsVisible()
		}
		if supportInfo.whoxSupported {
			send(.who, arguments: [channelName, "%tcuhnfar,\(ServerQuirks.whoxToken)"])
		} else {
			send(.who, arguments: [channelName])
		}
	}

	func sendWhois(_ nickname: String) {
		guard isLoggedIn, nickname.isEmpty == false else { return }
		send(.whois, arguments: [nickname, nickname])
	}

	func kick(_ nickname: String, in channel: Conversation) {
		guard isLoggedIn, channel.isChannel, channel.isActive, nickname.isEmpty == false else { return }
		send(
			.kick,
			arguments: [channel.name, nickname, truncatedKickReason(environment.settings.defaultKickMessage)]
		)
	}

	/// `reason` cut to `KICKLEN`, telling the user when anything was lost.
	///
	/// The menu and the `/kick` command send the same default message, so they
	/// measure it the same way: a reason the server truncates instead comes back
	/// cut mid-character and with nothing said about it.
	func truncatedKickReason(_ reason: String) -> String {
		truncated(
			reason,
			toLimit: supportInfo.maximumKickLength,
			reporting: { String(localized: .IRC.youHaveExceededTheMaximumKick($0, arg2: $1)) }
		)
	}

	/// `topic` cut to `TOPICLEN`, telling the user when anything was lost.
	func truncatedTopic(_ topic: String) -> String {
		truncated(
			topic,
			toLimit: supportInfo.maximumTopicLength,
			reporting: { String(localized: .IRC.youHaveExceededTheMaximumTopic($0, arg2: $1)) }
		)
	}

	/// `comment` cut to `AWAYLEN`, telling the user when anything was lost.
	func truncatedAwayComment(_ comment: String) -> String {
		truncated(
			comment,
			toLimit: supportInfo.maximumAwayLength,
			reporting: { String(localized: .IRC.youHaveExceededTheMaximumAway($0, arg2: $1)) }
		)
	}

	/// `text` cut to an ISUPPORT byte budget. A limit of zero is the server
	/// naming none, which leaves the text alone.
	func truncated(_ text: String, toLimit limit: UInt) -> String {
		ProtocolLimits.truncated(text, toByteCount: Int(min(limit, UInt(text.utf8.count))))
	}

	private func truncated(
		_ text: String,
		toLimit limit: UInt,
		reporting message: (String, Int) -> String
	) -> String {
		let maximumLength = Int(min(limit, UInt(text.utf8.count)))
		let result = ProtocolLimits.truncated(text, toByteCount: maximumLength)

		if result != text {
			printDebugInformation(message(networkNameAlt, maximumLength))
		}

		return result
	}

	/// Asks the server what modes a channel is under: `MODE` with nothing after
	/// the channel name.
	func requestModes(inChannelNamed channelName: String) {
		guard isLoggedIn, channelName.isEmpty == false else { return }

		send(.mode, arguments: [channelName])
	}

	/** Sends `groups` as `MODE` commands on `channelName`.

	 The structured entry point, and the one anything that knows what it is
	 changing should call: each group arrives already separated into a mode
	 string and its parameters, and is cut here only to respect the server's
	 `MODES` and the line length. Nothing to change sends nothing — asking the
	 server for a channel's modes is ``requestModes(inChannelNamed:)``.

	 A group whose mode string is empty is dropped rather than sent: it is what
	 the mode compiler answers with for a list the server stopped advertising. */
	func sendModes(_ groups: [ModeChangeGroup], inChannelNamed channelName: String) {
		guard isLoggedIn, channelName.isEmpty == false else { return }

		let budget = outboundParameterBudget(forCommand: "MODE", fixedArguments: [channelName])

		for group in groups where group.symbols.isEmpty == false {
			for command in OutboundModeCommands.groups(
				for: group,
				maximumModes: supportInfo.maximumModeCount,
				budget: budget
			) {
				send(.mode, arguments: [channelName] + command.wireArguments)
			}
		}
	}

	/** Sends the mode changes the text `symbols` and `parameters` describe.

	 The adapter the sheets and `/mode` use: they hold mode changes as the text
	 the user typed — `"-k+l hunter2 50"`, `"+b *!*@example.org"` — so the text
	 is tokenised into groups here and handed to the structured overload. It
	 parses; it decides nothing, beyond `/mode #channel` with nothing after it
	 being a request for the channel's modes. */
	func sendModes(_ symbols: String?, withParametersString parameters: String?, inChannelNamed channelName: String) {
		let tokens = LineParser.wireTokens(in: "\(symbols ?? "") \(parameters ?? "")")

		guard tokens.isEmpty == false else {
			requestModes(inChannelNamed: channelName)
			return
		}

		/* Only a channel has a `CHANMODES` table to say which letters are owed a
		 parameter; a user mode string is split on its signs alone. */
		let targetIsChannel = stringIsChannelName(channelName)
		let groups = OutboundModeCommands.groups(inTokens: tokens) { symbol, modeIsSet in
			targetIsChannel && supportInfo.modeHasParameter(String(symbol), whenModeIsSet: modeIsSet)
		}

		sendModes(groups, inChannelNamed: channelName)
	}

	/** The bytes one command has left for the parameters that follow
	 `fixedArguments`.

	 The line the server accepts is `LINELEN` including its CR LF, or the RFC's
	 512 when it advertised none; the command name, the arguments already
	 decided, and the spaces between them all come out of it first. Never less
	 than one byte, so a command with impossible framing still makes progress
	 rather than looping. */
	func outboundParameterBudget(forCommand command: String, fixedArguments: [String]) -> Int {
		let maximum = ProtocolLimits.bodyLimit(forAdvertisedLineLength: Int(supportInfo.maximumLineLength))
		let overhead = fixedArguments.reduce(command.utf8.count) { $0 + 1 + $1.utf8.count } + 1

		return max(maximum - overhead, 1)
	}

	func sendPing(_ token: String) {
		guard isConnected else { return }
		send(.ping, arguments: [token])
	}

	func sendPong(_ token: String) {
		guard isConnected else { return }
		send(.pong, arguments: [token])
	}

	func sendInvite(to nickname: String, toJoin channel: Conversation) {
		guard channel.isChannel else { return }
		sendInvite(to: nickname, toJoinChannelNamed: channel.name)
	}

	func sendInvite(to nickname: String, toJoinChannelNamed channelName: String) {
		guard nickname.isEmpty == false, channelName.isEmpty == false else { return }
		send(.invite, arguments: [nickname, channelName])
	}

	func sendTopic(to topic: String?, in channel: Conversation) {
		guard channel.isChannel, channel.isActive else { return }
		sendTopic(to: topic, inChannelNamed: channel.name)
	}

	func sendTopic(to topic: String?, inChannelNamed channelName: String) {
		guard isLoggedIn, channelName.isEmpty == false else { return }
		var arguments = [channelName]
		if let topic {
			arguments.append(truncatedTopic(topic))
		}
		send(.topic, arguments: arguments)
	}

	func sendCapabilityAuthenticate(_ data: String) {
		guard isConnected, data.isEmpty == false else { return }
		send(.authenticate, arguments: [data])
	}

	/** Asks the server which of `nicknames` are online.

	 One parameter per nickname, over as many commands as the list needs: joined
	 into one they became a single trailing parameter, so the server answered
	 about a nickname called "alice bob carol". Each command opens its own
	 request, because each draws its own `RPL_ISON`. */
	func sendIson(forNicknames nicknames: [String], hideResponse: Bool = false) {
		guard isLoggedIn, nicknames.isEmpty == false else { return }

		for group in WireBatching.packTokens(
			nicknames,
			maximumCount: ProtocolLimits.maximumParameterCount,
			budget: outboundParameterBudget(forCommand: "ISON", fixedArguments: [])
		) {
			if hideResponse {
				requestedCommands.recordIsonRequestOpened(askingAbout: group)
			} else {
				requestedCommands.recordIsonRequestOpenedAsVisible()
			}

			send(.ison, arguments: group)
		}
	}

	func requestChannelList(withArguments arguments: String? = nil) {
		guard isLoggedIn else { return }
		send(.list, arguments: arguments.map { [$0] } ?? [])
	}

	func sendPassword(_ password: String) {
		guard isConnected, password.isEmpty == false else { return }
		send(.pass, arguments: [password])
	}

	/** Adds or removes `nicknames` on the server's presence list.

	 The server says in `MONITOR=`/`WATCH=` how many entries it keeps, and
	 answers everything past that with `ERR_MONLISTFULL`/`ERR_TOOMANYWATCH`.
	 Sending the tail anyway spent the flood allowance on entries that were
	 never going to be accepted, so the list is cut here — with a line in the
	 log, since the user chose those names in the address book and nothing else
	 would say why the last of them are not tracked. */
	func modifyWatchList(byAdding adding: Bool, nicknames: [String]) {
		let accepted = adding ? watchListEntriesWithinServerCeiling(nicknames) : nicknames

		for group in WireBatching.packTokens(
			accepted,
			maximumCount: watchListGroupSize,
			budget: outboundParameterBudget(forCommand: "MONITOR", fixedArguments: ["+"])
		) {
			modifyWatchListGroup(byAdding: adding, nicknames: group)
		}
	}

	/// `nicknames` cut to what the server has room for, counting what is already
	/// tracked. An unadvertised limit is no limit.
	private func watchListEntriesWithinServerCeiling(_ nicknames: [String]) -> [String] {
		let ceiling = isCapabilityEnabled(.monitorCommand)
			? supportInfo.maximumMonitorEntries
			: supportInfo.maximumWatchEntries

		guard ceiling > 0 else {
			return nicknames
		}

		/* What the session believes the server already holds: the address book's
		 tracked nicknames and the open direct conversations, minus the ones this
		 call is about — `populateISONTrackedUsersList` records an addition before it
		 sends it, so counting those again would leave no room for them. */
		let pending = Set(nicknames.map(casefoldNickname))
		let held = Set(trackedUsers.trackedUsers.keys.map(casefoldNickname))
			.union(directPeerNicknames.map(casefoldNickname))
			.subtracting(pending)
		let room = max(Int(ceiling) - held.count, 0)

		guard nicknames.count > room else {
			return nicknames
		}

		wireCommandLogger.notice(
			"""
			Server tracks at most \(ceiling, privacy: .public) presence entries; \
			dropping \(nicknames.count - room, privacy: .public) of them
			"""
		)
		/* The user put these names in the address book, and nothing else in the
		 interface would ever say why the last of them stop being tracked. */
		printDebugInformation(
			toConsole: String(localized: .IRC.presenceListIsFull(nicknames.count - room, arg2: Int(clamping: ceiling)))
		)

		return Array(nicknames.prefix(room))
	}

	private func modifyWatchListGroup(byAdding adding: Bool, nicknames: [String]) {
		guard isLoggedIn, nicknames.isEmpty == false else { return }
		if isCapabilityEnabled(.monitorCommand) {
			send(.monitor, arguments: [adding ? "+" : "-", nicknames.joined(separator: ",")])
		} else if isCapabilityEnabled(.watchCommand) {
			/* One parameter per nickname. Joined into one, the group became a
			 trailing parameter and went out as `WATCH :+alice +bob`, which the
			 server reads as a single name. */
			let modifier = adding ? "+" : "-"
			send(.watch, arguments: nicknames.map { modifier + $0 })
		}
	}
}
