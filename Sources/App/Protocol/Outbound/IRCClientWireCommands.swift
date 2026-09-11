/* *********************************************************************
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
 *********************************************************************** */

import Foundation
import os

private let whoxRequestToken = "152"

private nonisolated let wireCommandLogger = Logger( // nonisolated: let
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "IRCWireCommands"
)

/// How many nicknames one `MONITOR +`/`WATCH` command carries when the server
/// has not said otherwise. Small enough that no line approaches the byte limit
/// whatever the nicknames are.
private let watchListGroupSize = 8

/** Splitting a list of single-token parameters over several commands.

 `ISON`, `WATCH` and `MONITOR` all take a list the user's address book decides
 the length of, and a list long enough overruns either the fifteen parameters
 RFC 1459 allows or the 512 bytes the line has. Both are the same split, so
 both use this one. */
nonisolated enum OutboundParameterChunking { // nonisolated: value
	/// `parameters` grouped into one command's worth each.
	///
	/// - Parameters:
	///   - parameters: The tokens to spread over commands. Empty ones are
	///     dropped: they cannot survive as their own wire token anyway.
	///   - maximumCount: The most parameters one command takes.
	///   - budget: The bytes one command has for its parameters, the spaces
	///     between them included. A parameter longer than the whole budget
	///     still goes out on a line of its own rather than being dropped.
	static func chunks(of parameters: [String], maximumCount: Int, budget: Int) -> [[String]] {
		var result: [[String]] = []
		var current: [String] = []
		var currentLength = 0

		for parameter in parameters where parameter.isEmpty == false {
			let separator = current.isEmpty ? 0 : 1

			if current.isEmpty == false,
			   current.count >= maximumCount || currentLength + separator + parameter.utf8.count > budget
			{
				result.append(current)
				current = []
				currentLength = 0
			}

			currentLength += (current.isEmpty ? 0 : 1) + parameter.utf8.count
			current.append(parameter)
		}

		if current.isEmpty == false {
			result.append(current)
		}

		return result
	}
}

/** Fitting mode changes into the `MODE` commands a server will take.

 A change is a mode string and the parameters that pair with it. What varies is
 how many of those pairs one command may carry: `MODES` from ISUPPORT caps the
 count and the line length caps the bytes, so one change becomes as many
 commands as it needs. Sending a change whole made the server read
 `+ooo alice bob carol` as a single parameter and op nobody. */
nonisolated enum OutboundModeCommands { // nonisolated: value
	/// The groups `tokens` — a mode string and its parameters as the user or a
	/// sheet wrote them — describe, before any splitting.
	///
	/// `/umode +s +cfk` is two independent changes, and a server that reads only
	/// the first mode string of a line would silently drop the second if they
	/// shared one.
	static func groups(inTokens tokens: [String]) -> [ModeChangeGroup] {
		var result: [ModeChangeGroup] = []

		for token in tokens where token.isEmpty == false {
			if isModeString(token) || result.isEmpty {
				result.append(ModeChangeGroup(symbols: token))
			} else {
				result[result.count - 1].parameters.append(token)
			}
		}

		return result
	}

	private static func isModeString(_ token: String) -> Bool {
		token.hasPrefix("+") || token.hasPrefix("-")
	}

	/// `group` cut into the commands one server will take.
	///
	/// - Parameters:
	///   - maximumModes: `MODES` from ISUPPORT — how many parameterised changes
	///     one command takes. Zero means the server named no limit.
	///   - budget: The bytes left for these arguments once the command name and
	///     the channel are charged.
	static func groups(for group: ModeChangeGroup, maximumModes: UInt, budget: Int) -> [ModeChangeGroup] {
		let changes = modeChanges(in: group.symbols)

		/* Only a mode string whose every letter has a parameter can be split:
		 the letters pair up with the parameters one for one, so any prefix of
		 the pairs is a valid command. Anything else — a bare `+nt`, a `-k+l`
		 the caller gave one parameter — goes out whole, because cutting it
		 would change which parameter belongs to which mode. */
		guard changes.count == group.parameters.count, changes.count > 1 else {
			return [group]
		}

		var result: [ModeChangeGroup] = []
		var currentChanges: [(sign: Character, symbol: Character)] = []
		var currentParameters: [String] = []

		func flush() {
			guard currentChanges.isEmpty == false else { return }
			result.append(ModeChangeGroup(symbols: modeString(for: currentChanges), parameters: currentParameters))
			currentChanges = []
			currentParameters = []
		}

		func length(changes: [(sign: Character, symbol: Character)], parameters: [String]) -> Int {
			modeString(for: changes).utf8.count + parameters.reduce(0) { $0 + 1 + $1.utf8.count }
		}

		for (change, parameter) in zip(changes, group.parameters) {
			let wouldBeLength = length(
				changes: currentChanges + [change],
				parameters: currentParameters + [parameter]
			)

			if currentChanges.isEmpty == false,
			   maximumModes > 0 && UInt(currentChanges.count) >= maximumModes || wouldBeLength > budget
			{
				flush()
			}

			currentChanges.append(change)
			currentParameters.append(parameter)
		}

		flush()

		return result
	}

	/// The `(sign, symbol)` pairs a mode string names, in order.
	private static func modeChanges(in modeString: String) -> [(sign: Character, symbol: Character)] {
		var sign: Character = "+"
		var result: [(sign: Character, symbol: Character)] = []

		for character in modeString {
			if character == "+" || character == "-" {
				sign = character
			} else {
				result.append((sign: sign, symbol: character))
			}
		}

		return result
	}

	/// The pairs written back as a mode string, repeating a sign only where it
	/// changes.
	private static func modeString(for changes: [(sign: Character, symbol: Character)]) -> String {
		var result = ""
		var sign: Character?

		for change in changes {
			if change.sign != sign {
				result.append(change.sign)
				sign = change.sign
			}

			result.append(change.symbol)
		}

		return result
	}
}

@MainActor
public extension IRCClient {
	func changeNickname(_ nickname: String) {
		guard isConnected, nickname.isEmpty == false else { return }
		/* `NICKLEN` is a byte budget like the rest, and a server given a longer
		 nickname picks the truncation itself — which for anything but ASCII
		 lands mid-character. */
		send("NICK", arguments: [truncated(nickname, toLimit: supportInfo.maximumNicknameLength)])
	}

	func part(_ channel: IRCChannel) {
		part(channel, withComment: nil)
	}

	func part(_ channel: IRCChannel, withComment comment: String?) {
		guard isLoggedIn, channel.isChannel, channel.isActive else { return }
		send("PART", arguments: [channel.name, comment ?? config.normalLeavingComment])
	}

	func sendWho(to channel: IRCChannel) {
		sendWho(to: channel, hideResponse: false)
	}

	func sendWho(to channel: IRCChannel, hideResponse: Bool) {
		guard channel.isChannel else { return }
		sendWho(toChannelNamed: channel.name, hideResponse: hideResponse)
	}

	func sendWho(toChannelNamed channelName: String) {
		sendWho(toChannelNamed: channelName, hideResponse: false)
	}

	func sendWho(toChannelNamed channelName: String, hideResponse: Bool) {
		guard isLoggedIn, channelName.isEmpty == false else { return }
		if hideResponse {
			requestedCommands.recordWhoRequestOpened()
		} else {
			requestedCommands.recordWhoRequestOpenedAsVisible()
		}
		if supportInfo.whoxSupported {
			send("WHO", arguments: [channelName, "%tcuhnfar,\(whoxRequestToken)"])
		} else {
			send("WHO", arguments: [channelName])
		}
	}

	func sendWhois(_ nickname: String) {
		guard isLoggedIn, nickname.isEmpty == false else { return }
		send("WHOIS", arguments: [nickname, nickname])
	}

	func kick(_ nickname: String, in channel: IRCChannel) {
		guard isLoggedIn, channel.isChannel, channel.isActive, nickname.isEmpty == false else { return }
		send(
			"KICK",
			arguments: [channel.name, nickname, truncatedKickReason(environment.preferences.defaultKickMessage)]
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
			reporting: IRCCommandStrings.kickMessageTooLong(networkName:maximumLength:)
		)
	}

	/// `topic` cut to `TOPICLEN`, telling the user when anything was lost.
	func truncatedTopic(_ topic: String) -> String {
		truncated(
			topic,
			toLimit: supportInfo.maximumTopicLength,
			reporting: IRCCommandStrings.topicTooLong(networkName:maximumLength:)
		)
	}

	/// `comment` cut to `AWAYLEN`, telling the user when anything was lost.
	func truncatedAwayComment(_ comment: String) -> String {
		truncated(
			comment,
			toLimit: supportInfo.maximumAwayLength,
			reporting: IRCCommandStrings.awayMessageTooLong(networkName:maximumLength:)
		)
	}

	/// `text` cut to an ISUPPORT byte budget. A limit of zero is the server
	/// naming none, which leaves the text alone.
	func truncated(_ text: String, toLimit limit: UInt) -> String {
		ClientWireUtilities.truncated(text, toByteCount: Int(min(limit, UInt(text.utf8.count))))
	}

	private func truncated(
		_ text: String,
		toLimit limit: UInt,
		reporting message: (String, Int) -> String
	) -> String {
		let maximumLength = Int(min(limit, UInt(text.utf8.count)))
		let result = ClientWireUtilities.truncated(text, toByteCount: maximumLength)

		if result != text {
			printDebugInformation(message(networkNameAlt, maximumLength))
		}

		return result
	}

	func requestModes(for channel: IRCChannel) {
		requestModes(inChannelNamed: channel.name)
	}

	/// Asks the server what modes a channel is under: `MODE` with nothing after
	/// the channel name.
	func requestModes(inChannelNamed channelName: String) {
		guard isLoggedIn, channelName.isEmpty == false else { return }

		send("MODE", arguments: [channelName])
	}

	func sendModes(_ symbols: String?, withParametersString parameters: String?, in channel: IRCChannel) {
		sendModes(symbols, withParametersString: parameters, inChannelNamed: channel.name)
	}

	/** Sends `groups` as `MODE` commands on `channelName`.

	 The structured entry point, and the one anything that knows what it is
	 changing should call: each group arrives already separated into a mode
	 string and its parameters, and is cut here only to respect the server's
	 `MODES` and the line length. Nothing to change sends nothing — asking the
	 server for a channel's modes is ``requestModes(for:)``.

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
				send("MODE", arguments: [channelName] + command.wireArguments)
			}
		}
	}

	func sendModes(_ groups: [ModeChangeGroup], in channel: IRCChannel) {
		sendModes(groups, inChannelNamed: channel.name)
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

		sendModes(OutboundModeCommands.groups(inTokens: tokens), inChannelNamed: channelName)
	}

	/** The bytes one command has left for the parameters that follow
	 `fixedArguments`.

	 The line the server accepts is `LINELEN` including its CR LF, or the RFC's
	 512 when it advertised none; the command name, the arguments already
	 decided, and the spaces between them all come out of it first. Never less
	 than one byte, so a command with impossible framing still makes progress
	 rather than looping. */
	func outboundParameterBudget(forCommand command: String, fixedArguments: [String]) -> Int {
		let advertised = Int(supportInfo.maximumLineLength)
		let maximum = advertised > IRCProtocolLimits.lineTerminatorLength
			? advertised - IRCProtocolLimits.lineTerminatorLength
			: IRCProtocolLimits.maximumBodyLength
		let overhead = fixedArguments.reduce(command.utf8.count) { $0 + 1 + $1.utf8.count } + 1

		return max(maximum - overhead, 1)
	}

	func sendPing(_ token: String) {
		guard isConnected else { return }
		send("PING", arguments: [token])
	}

	func sendPong(_ token: String) {
		guard isConnected else { return }
		send("PONG", arguments: [token])
	}

	func sendInvite(to nickname: String, toJoin channel: IRCChannel) {
		guard channel.isChannel else { return }
		sendInvite(to: nickname, toJoinChannelNamed: channel.name)
	}

	func sendInvite(to nickname: String, toJoinChannelNamed channelName: String) {
		guard nickname.isEmpty == false, channelName.isEmpty == false else { return }
		send("INVITE", arguments: [nickname, channelName])
	}

	func sendTopic(to topic: String?, in channel: IRCChannel) {
		guard channel.isChannel, channel.isActive else { return }
		sendTopic(to: topic, inChannelNamed: channel.name)
	}

	func sendTopic(to topic: String?, inChannelNamed channelName: String) {
		guard isLoggedIn, channelName.isEmpty == false else { return }
		var arguments = [channelName]
		if let topic {
			arguments.append(truncatedTopic(topic))
		}
		send("TOPIC", arguments: arguments)
	}

	func sendCapabilityAuthenticate(_ data: String) {
		guard isConnected, data.isEmpty == false else { return }
		send("AUTHENTICATE", arguments: [data])
	}

	func sendIson(forNicknames nicknames: [String]) {
		sendIson(forNicknames: nicknames, hideResponse: false)
	}

	/** Asks the server which of `nicknames` are online.

	 One parameter per nickname, over as many commands as the list needs: joined
	 into one they became a single trailing parameter, so the server answered
	 about a nickname called "alice bob carol". Each command opens its own
	 request, because each draws its own `RPL_ISON`. */
	func sendIson(forNicknames nicknames: [String], hideResponse: Bool) {
		guard isLoggedIn, nicknames.isEmpty == false else { return }

		for group in OutboundParameterChunking.chunks(
			of: nicknames,
			maximumCount: IRCProtocolLimits.maximumParameterCount,
			budget: outboundParameterBudget(forCommand: "ISON", fixedArguments: [])
		) {
			if hideResponse {
				requestedCommands.recordIsonRequestOpened()
			} else {
				requestedCommands.recordIsonRequestOpenedAsVisible()
			}

			send("ISON", arguments: group)
		}
	}

	func requestChannelList() {
		requestChannelList(withArguments: nil)
	}

	func requestChannelList(withArguments arguments: String?) {
		guard isLoggedIn else { return }
		send("LIST", arguments: arguments.map { [$0] } ?? [])
	}

	func sendPassword(_ password: String) {
		guard isConnected, password.isEmpty == false else { return }
		send("PASS", arguments: [password])
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

		for group in OutboundParameterChunking.chunks(
			of: accepted,
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

		/* What the client believes the server already holds: the address book's
		 tracked nicknames and the open queries, minus the ones this call is
		 about — `populateISONTrackedUsersList` records an addition before it
		 sends it, so counting those again would leave no room for them. */
		let pending = Set(nicknames.map(casefoldNickname))
		let held = Set(trackedUsers.trackedUsers.keys.map(casefoldNickname))
			.union(queryPeerNicknames.map(casefoldNickname))
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
			toConsole: IRCISupportStrings.presenceListIsFull(
				droppedCount: nicknames.count - room,
				ceiling: ceiling
			)
		)

		return Array(nicknames.prefix(room))
	}

	private func modifyWatchListGroup(byAdding adding: Bool, nicknames: [String]) {
		guard isLoggedIn, nicknames.isEmpty == false else { return }
		if isCapabilityEnabled(.monitorCommand) {
			send("MONITOR", arguments: [adding ? "+" : "-", nicknames.joined(separator: ",")])
		} else if isCapabilityEnabled(.watchCommand) {
			/* One parameter per nickname. Joined into one, the group became a
			 trailing parameter and went out as `WATCH :+alice +bob`, which the
			 server reads as a single name. */
			let modifier = adding ? "+" : "-"
			send("WATCH", arguments: nicknames.map { modifier + $0 })
		}
	}
}
