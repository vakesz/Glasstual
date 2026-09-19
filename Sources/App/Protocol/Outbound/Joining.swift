// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import os

private nonisolated let joinLogger = Logger(
	subsystem: LogSubsystem.current,
	category: "Joining"
)

@MainActor
extension ServerSession {
	var canJoinChannels: Bool {
		isLoggedIn && !isQuitting && !isDisconnecting && !isTerminating
	}

	func canJoin(_ channel: Conversation) -> Bool {
		canJoinChannels && channel.associatedSession === self
			&& conversationList.contains { $0 === channel }
			&& channel.isChannel && !channel.isActive && channel.status != .terminated
	}

	func join(_ channel: Conversation, password: String? = nil) {
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
		if let channel = findConversation(channelName) {
			join(channel, password: password)
		} else {
			forceJoinChannel(channelName, password: password)
		}
	}

	/// Shows `channel` as on its way in until the server answers the JOIN.
	private func markJoining(_ channel: Conversation) {
		channel.errorOnLastJoinAttempt = false
		channel.status = .joining
		output?.reloadChatItem(channel)
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
		send(.join, arguments: arguments)
	}

	/// `channelNames` less the ones the server would refuse for their length.
	///
	/// `CHANNELLEN` was parsed and never applied, so an over-long name went out
	/// and came back as an error numeric against a name the session had already
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
					toConsole: String(localized: .IRC.joinRefusedNameTooLong(refused, arg2: Int(clamping: maximumLength)))
				)
			}
		}

		return accepted
	}

	func joinChannels(_ channels: [Conversation]) {
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
			send(.join, arguments: arguments)
		}
	}

	func warnIfJoiningChannelsExceedsLimit(_ channelNames: [String]) {
		guard supportInfo.channelLimits.isEmpty == false else { return }

		var joinedCountByPrefix: [Character: UInt] = [:]
		for channel in conversationList where channel.isChannel && channel.isActive {
			guard let prefix = channel.name.first else { continue }
			joinedCountByPrefix[prefix, default: 0] += 1
		}

		var warnedPrefixes: Set<Character> = []
		for channelName in channelNames where stringIsChannelName(channelName) {
			if findConversation(channelName)?.isActive == true {
				continue
			}
			guard let prefix = channelName.first else { continue }
			let limit = supportInfo.channelLimit(forChannelNamed: channelName)
			guard limit > 0 else { continue }

			let joinedCount = joinedCountByPrefix[prefix, default: 0] + 1
			joinedCountByPrefix[prefix] = joinedCount
			guard joinedCount > limit, warnedPrefixes.insert(prefix).inserted else { continue }
			printDebugInformation(
				toConsole: String(localized: .IRC.joiningWouldExceedTheLimit(channelName, arg2: limit, String(prefix)))
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
			.compactMap { self.findConversationOrCreate($0) }
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
				guard let channel = findConversation(target.name), canJoin(channel) else { continue }
				markJoining(channel)
			}
			sendJoins(for: targets)
		}

		guard let selection else { return }
		output?.select(selection)
	}
}
