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

private nonisolated let joinLogger = Logger( // nonisolated: let
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "IRCJoin"
)

/** What `JOIN` accepts for a channel name and a key.

 `JOIN` takes two comma-separated lists that line up with each other, and every
 entry of both is one wire token. A key with a space in it cannot be sent at
 all — as the trailing parameter it would swallow whatever followed, and
 without the colon the server would read only its first word — so it is cut at
 the space rather than colonised. A key with a comma in it cannot be sent
 either: the server would read it as two keys, and hand the second to the next
 channel. */
nonisolated enum OutboundJoinPolicy { // nonisolated: value
	/// `key` as `JOIN` can carry it, or `nil` when nothing is left of it.
	///
	/// Everything from the first space on is dropped: the protocol has no way
	/// to spell a key with a space in it, and `KEYLEN` bounds what is left. A
	/// key with a comma in it is refused outright, because cutting it would
	/// send a different key.
	static func sanitizedKey(_ key: String?, maximumLength: UInt) -> String? {
		guard let firstToken = key?.split(separator: " ", maxSplits: 1).first,
		      firstToken.contains(",") == false
		else {
			return nil
		}

		let bounded = ClientWireUtilities.truncated(
			String(firstToken),
			toByteCount: Int(min(maximumLength, UInt(firstToken.utf8.count)))
		)

		return bounded.isEmpty ? nil : bounded
	}

	/// `channelNames` paired with the keys the user typed for them.
	///
	/// The user types keys separated by spaces, commas, or both, and the *n*th
	/// key belongs to the *n*th channel. Space-separated on the wire they became
	/// one trailing parameter, which is one key for the first channel and
	/// nothing for the rest.
	static func targets(
		channelNames: [String],
		keyText: String,
		maximumKeyLength: UInt
	) -> [JoinBatching.Target] {
		let keys = keyText.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\t" })

		return channelNames.enumerated().map { index, name in
			JoinBatching.Target(
				name: name,
				key: index < keys.count ? sanitizedKey(String(keys[index]), maximumLength: maximumKeyLength) : nil
			)
		}
	}

	/// Whether `channelName` fits the server's `CHANNELLEN`.
	///
	/// A name over the limit is refused rather than cut: a truncated channel
	/// name is a different channel, so joining it would put the user somewhere
	/// they never asked to be. Zero is the server naming no limit.
	static func channelNameFits(_ channelName: String, maximumLength: UInt) -> Bool {
		maximumLength == 0 || UInt(channelName.utf8.count) <= maximumLength
	}
}

@MainActor
extension Client {
	var canJoinChannels: Bool {
		isLoggedIn && !isQuitting && !isDisconnecting && !isTerminating
	}

	func canJoin(_ channel: Channel) -> Bool {
		canJoinChannels && channel.associatedClient === self
			&& channelList.contains { $0 === channel }
			&& channel.isChannel && !channel.isActive && channel.status != .terminated
	}

	func join(_ channel: Channel, password: String? = nil) {
		guard canJoin(channel) else { return }
		markJoining(channel)
		forceJoinChannel(channel.name, password: password ?? channel.secretKey)
	}

	func joinUnlistedChannel(_ channelName: String, password: String? = nil) {
		guard stringIsChannelName(channelName) else {
			if channelName == "0" {
				forceJoinChannel(channelName, password: password)
			}
			return
		}
		if let channel = findChannel(channelName) {
			join(channel, password: password)
		} else {
			forceJoinChannel(channelName, password: password)
		}
	}

	/// Shows `channel` as on its way in until the server answers the JOIN.
	private func markJoining(_ channel: Channel) {
		channel.errorOnLastJoinAttempt = false
		channel.status = .joining
		output?.reloadTreeItem(channel)
		output?.updateTitle(for: channel)
	}

	func forceJoinChannel(_ channelName: String, password: String?) {
		guard canJoinChannels, channelName.isEmpty == false else { return }
		guard let channelName = channelNamesWithinServerLimit([channelName]).first else { return }
		warnIfJoiningChannelsExceedsLimit([channelName])
		var arguments = [channelName]
		if let key = OutboundJoinPolicy.sanitizedKey(password, maximumLength: supportInfo.maximumKeyLength) {
			arguments.append(key)
		}
		send("JOIN", arguments: arguments)
	}

	/// `channelNames` less the ones the server would refuse for their length.
	///
	/// `CHANNELLEN` was parsed and never applied, so an over-long name went out
	/// and came back as an error numeric against a name the client had already
	/// put in the sidebar.
	func channelNamesWithinServerLimit(_ channelNames: [String]) -> [String] {
		let maximumLength = supportInfo.maximumChannelNameLength
		let accepted = channelNames.filter {
			OutboundJoinPolicy.channelNameFits($0, maximumLength: maximumLength)
		}

		if accepted.count != channelNames.count {
			joinLogger.notice(
				"""
				Not joining \(channelNames.count - accepted.count, privacy: .public) channel(s) \
				whose names exceed the server's CHANNELLEN of \(maximumLength, privacy: .public)
				"""
			)
			/* The user asked for these by name — from the sidebar, from an
			 autojoin list, from `/join`. A refusal only the log records reads
			 as the join having been ignored, so each name is said out loud the
			 way `warnIfJoiningChannelsExceedsLimit` says its own. */
			for refused in channelNames where accepted.contains(refused) == false {
				printDebugInformation(
					toConsole: ISupportStrings.channelNameTooLong(
						channelName: refused,
						maximumLength: maximumLength
					)
				)
			}
		}

		return accepted
	}

	func joinChannels(_ channels: [Channel]) {
		guard canJoinChannels, channels.isEmpty == false else { return }
		let acceptedNames = Set(channelNamesWithinServerLimit(channels.map(\.name)))
		let pending = channels.filter { canJoin($0) && acceptedNames.contains($0.name) }
		guard pending.isEmpty == false else { return }
		warnIfJoiningChannelsExceedsLimit(pending.map(\.name))
		pending.forEach(markJoining)

		sendJoins(for: pending.map {
			JoinBatching.Target(
				name: $0.name,
				key: OutboundJoinPolicy.sanitizedKey($0.secretKey, maximumLength: supportInfo.maximumKeyLength)
			)
		})
	}

	/// Sends `targets` as one `JOIN` per line that fits the protocol budget; a
	/// single line naming every channel is truncated by the server.
	private func sendJoins(for targets: [JoinBatching.Target]) {
		let batches = JoinBatching.batches(
			for: targets,
			maximumLineLength: Int(supportInfo.maximumLineLength),
			maximumTargets: supportInfo.maximumTargets(forCommand: "JOIN"),
			channelLimits: supportInfo.channelLimits
		)
		for batch in batches {
			var arguments = [batch.channels.joined(separator: ",")]
			if batch.keys.isEmpty == false {
				arguments.append(batch.keys.joined(separator: ","))
			}
			send("JOIN", arguments: arguments)
		}
	}

	func warnIfJoiningChannelsExceedsLimit(_ channelNames: [String]) {
		guard supportInfo.channelLimits.isEmpty == false else { return }

		var joinedCountByPrefix: [Character: UInt] = [:]
		for channel in channelList where channel.isChannel && channel.isActive {
			guard let prefix = channel.name.first else { continue }
			joinedCountByPrefix[prefix, default: 0] += 1
		}

		var warnedPrefixes: Set<Character> = []
		for channelName in channelNames where stringIsChannelName(channelName) {
			if findChannel(channelName)?.isActive == true {
				continue
			}
			guard let prefix = channelName.first else { continue }
			let limit = supportInfo.channelLimit(forChannelNamed: channelName)
			guard limit > 0 else { continue }

			let joinedCount = joinedCountByPrefix[prefix, default: 0] + 1
			joinedCountByPrefix[prefix] = joinedCount
			guard joinedCount > limit, warnedPrefixes.insert(prefix).inserted else { continue }
			printDebugInformation(
				toConsole: ISupportStrings.channelLimitExceeded(
					channelName: channelName,
					limit: limit,
					prefix: String(prefix)
				)
			)
		}
	}

	func joinUnlistedChannelsAndSelectBestMatch(_ channelNames: String, passwords: String? = nil) {
		guard channelNames.isEmpty == false else { return }
		joinUnlistedChannelsAndSelectBestMatch(
			channelNames.components(separatedBy: ","),
			passwords: passwords
		)
	}

	func joinUnlistedChannelsAndSelectBestMatch(_ channelNames: [String], passwords: String? = nil) {
		guard canJoinChannels, channelNames.isEmpty == false else { return }

		let selection = channelNames.lazy
			.filter { self.stringIsChannelName($0) }
			.compactMap { self.findChannelOrCreate($0) }
			.first
		let shouldJoin = (selection.map { $0.isActive == false } ?? true) || channelNames.count > 1
		/* Keys pair with the names as typed, before any name is refused: a
		 refusal must not hand its key to the channel after it. */
		let typedTargets = OutboundJoinPolicy.targets(
			channelNames: channelNames,
			keyText: passwords ?? "",
			maximumKeyLength: supportInfo.maximumKeyLength
		)
		let acceptedNames = Set(channelNamesWithinServerLimit(channelNames))
		let targets = typedTargets.filter { acceptedNames.contains($0.name) }
		if shouldJoin, targets.isEmpty == false {
			warnIfJoiningChannelsExceedsLimit(targets.map(\.name))
			/* A channel the sidebar already lists shows it is on its way in, as
			 it does when it is joined from the sidebar. */
			for target in targets {
				guard let channel = findChannel(target.name), canJoin(channel) else { continue }
				markJoining(channel)
			}
			sendJoins(for: targets)
		}

		guard let selection else { return }
		output?.select(selection)
	}
}
