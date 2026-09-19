// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

enum UserTrackingWhoBatchPolicy {
	/// One tick covers the starting position in the conversation list plus four
	/// more, so a long list is walked over several ticks.
	static let maximumConversationOffset = 4
	static let maximumInitialChannelSize: UInt = 5000
	static let maximumTotalChannelSize: UInt = 2000

	static func indexRange(startingAt requestedStart: Int, conversationCount: Int) -> ClosedRange<Int>? {
		guard conversationCount > 0 else { return nil }

		let start = requestedStart < conversationCount ? requestedStart : 0
		let end = min(start + maximumConversationOffset, conversationCount - 1)
		return start ... end
	}
}

extension ServerSession {
	func clearTrackedUsers() {
		trackedUsers.clearTrackedUsers()
	}

	func setTrackedNickname(_ nickname: String, status: AddressBookUserTrackingStatus) {
		setTrackedNickname(nickname, status: status, notify: false)
	}

	func setTrackedNickname(
		_ nickname: String,
		status: AddressBookUserTrackingStatus,
		notify: Bool
	) {
		trackedUsers.status(ofTrackedNickname: nickname, changedTo: status)

		if notify {
			notifyTrackedNickname(nickname, status: status)
		}
	}

	private func notifyTrackedNickname(_ nickname: String, status: AddressBookUserTrackingStatus) {
		/* Only the three states a person would want telling about say anything;
		 the rest are bookkeeping the tracker does for itself. */
		let message: String? = switch status {
		case .signedOn: String(localized: .Notifications.bodyUserNowAvailable(nickname))
		case .signedOff: String(localized: .Notifications.bodyUserNoLongerAvailable(nickname))
		case .available: String(localized: .Notifications.bodyUserAvailable(nickname))
		default: nil
		}

		guard let message else {
			return
		}

		notifyEvent(
			.addressBookMatch,
			lineType: .notice,
			target: nil,
			nickname: nickname,
			text: message
		)
	}

	@MainActor func populateISONTrackedUsersList() {
		guard isLoggedIn else { return }

		var additions: [String] = []
		var removals: [String] = []
		let previousNicknames = Array(trackedUsers.trackedUsers.keys)
		var currentNicknames: [String] = []

		for entry in config.ignoreList where entry.trackUserActivity {
			guard let nickname = entry.trackingNickname else { continue }

			if trackedUsers.status(ofUser: nickname) != .unknown {
				currentNicknames.append(nickname)
				continue
			}

			additions.append(nickname)
			trackedUsers.addTrackedUserWithoutDuplicateCheck(nickname)
		}

		/* Folded the way the server folds nicknames: `caseInsensitiveCompare`
		 is Unicode folding, under which `nick[home]` and `nick{home}` are two
		 people and the tracked one is dropped from the watch list. */
		let foldedCurrentNicknames = Set(currentNicknames.map(casefoldNickname))
		for nickname in previousNicknames
			where foldedCurrentNicknames.contains(casefoldNickname(nickname)) == false
		{
			removals.append(nickname)
			trackedUsers.removeTrackedUserWithoutLookup(nickname)
		}

		modifyWatchList(byAdding: true, nicknames: additions)
		modifyWatchList(byAdding: false, nicknames: removals)
		modifyWatchList(byAdding: true, nicknames: directPeerNicknames)
		startISONTimer()
	}

	// MARK: - Direct conversation peers

	/// The people the open direct conversations are with. The sidebar draws each
	/// of them in the colour of its peer's presence, so that presence is worth
	/// asking for.
	var directPeerNicknames: [String] {
		conversationList.filter(\.isDirect).map(\.name)
	}

	/// Has the server report the peer signing on and off, where it can. With
	/// neither MONITOR nor WATCH this sends nothing, and the ISON poll — which
	/// already covers every direct conversation — is what the row follows
	/// instead.
	func trackDirectPeer(_ nickname: String) {
		modifyWatchList(byAdding: true, nicknames: [nickname])
	}

	/// The address book may track the same person; that entry keeps its place.
	func stopTrackingDirectPeer(_ nickname: String) {
		guard findUserTrackingAddressBookEntry(forNickname: nickname) == nil else { return }
		modifyWatchList(byAdding: false, nicknames: [nickname])
	}

	/// Applies a presence report to the direct conversation with that peer, if
	/// one is open.
	func applyPresence(_ isOnline: Bool, toDirectWith nickname: String) {
		guard let direct = findConversation(nickname), direct.isDirect else { return }
		applyPresence(isOnline, to: direct)
	}

	/// The one place a direct conversation follows its peer on and off line,
	/// whichever source reported it: MONITOR, WATCH, ISON, a QUIT, a message
	/// arriving, or login. Address-book tracking is a separate concern with its
	/// own notifications; this only recolours the row.
	func applyPresence(_ isOnline: Bool, to direct: Conversation) {
		guard direct.isActive != isOnline else { return }
		if isOnline {
			direct.activate()
		} else {
			direct.deactivate()
		}
		output?.reloadChatItem(direct)
	}

	func startISONTimer() {
		guard isonTimer.isActive == false else { return }
		isonTimer.start(30, repeats: true)
		startWhoTimer()
		/* The timer sleeps a full interval before its first fire, and login has
		 just marked every direct conversation active. Ask now, so a peer who is
		 offline is not drawn as present for the next thirty seconds. */
		onISONTimer()
	}

	func stopISONTimer() {
		guard isonTimer.isActive else { return }
		isonTimer.stop()
		stopWhoTimer()
	}

	/** Polls ISON for the tracked nicknames and the direct conversation peers.

	 Only where the server has neither MONITOR nor WATCH: with either, the
	 address book and every direct conversation are already on the server's list,
	 which reports each change as it happens, and a poll on top only re-derived
	 the same presence thirty seconds late. */
	@MainActor func onISONTimer() {
		guard isLoggedIn, isBrokenIRCdKnownAsTwitch == false, supportsAdvancedTracking == false else { return }

		var nicknames = Array(trackedUsers.trackedUsers.keys)
		nicknames.append(contentsOf: directPeerNicknames)
		sendIson(forNicknames: nicknames, hideResponse: true)
	}

	func startWhoTimer() {
		guard whoTimer.isActive == false else { return }
		whoTimer.start(120, repeats: true)
	}

	func stopWhoTimer() {
		guard whoTimer.isActive else { return }
		whoTimer.stop()
	}

	@MainActor func onWhoTimer() {
		guard isLoggedIn, isBrokenIRCdKnownAsTwitch == false else { return }
		sendTimedWhoRequests(to: conversationList)
	}

	/** A channel's first WHO goes out as soon as its members are known.

	 It is the reply that carries who was already away when the channel was
	 joined; away-notify only reports changes from then on. Left to the timer,
	 that first request waited for a two-minute tick that starts ten seconds
	 after login and takes five channels at a time. */
	@MainActor
	func sendInitialWhoRequest(to channel: Conversation) {
		guard isLoggedIn, isBrokenIRCdKnownAsTwitch == false,
		      channel.isActive, channel.isChannel, channel.sentInitialWhoRequest == false,
		      config.sendWhoCommandRequestsToChannels,
		      UInt(channel.numberOfMembers) <= UserTrackingWhoBatchPolicy.maximumInitialChannelSize
		else { return }
		channel.sentInitialWhoRequest = true
		sendWho(to: channel, hideResponse: true)
	}

	@MainActor
	func sendTimedWhoRequests(to conversations: [Conversation]) {
		guard isLoggedIn, isBrokenIRCdKnownAsTwitch == false,
		      let range = UserTrackingWhoBatchPolicy.indexRange(
		      	startingAt: Int(lastWhoRequestConversationListIndex),
		      	conversationCount: conversations.count
		      )
		else { return }

		var endIndex = range.upperBound
		var totalMemberCount: UInt = 0
		var channelsToQuery: [Conversation] = []

		for index in range {
			let channel = conversations[index]
			guard channel.isActive, channel.isChannel else { continue }

			let sentInitialRequest = channel.sentInitialWhoRequest
			if sentInitialRequest == false {
				channel.sentInitialWhoRequest = true
			}

			guard config.sendWhoCommandRequestsToChannels else { continue }

			let memberCount = UInt(channel.numberOfMembers)
			if sentInitialRequest == false {
				guard memberCount <= UserTrackingWhoBatchPolicy.maximumInitialChannelSize else { continue }
			} else {
				guard isCapabilityEnabled(.awayNotify) == false,
				      memberCount <= environment.settings.trackUserAwayStatusMaximumChannelSize
				else { continue }
			}

			channelsToQuery.append(channel)
			totalMemberCount += memberCount

			if totalMemberCount > UserTrackingWhoBatchPolicy.maximumTotalChannelSize {
				endIndex = index
				break
			}
		}

		lastWhoRequestConversationListIndex = UInt(endIndex + 1)

		for channel in channelsToQuery {
			sendWho(to: channel, hideResponse: true)
		}
	}

	func updateUserTrackingStatus(for entry: AddressBookEntry, message: Message) {
		guard supportsAdvancedTracking == false else { return }

		let trackingStatus = trackedUsers.status(of: entry)
		guard trackingStatus != .unknown, let senderNickname = message.senderNickname else { return }

		/* The entry's own nickname, not the sender's. A NICK is reported twice —
		 once for the entry the old nickname matched and once for the entry the
		 new one does — and both carry the same sender, who is the person under
		 their *old* name. Recording the second transition against that name
		 signed the wrong entry on and left the one renamed into unchanged. */
		let nickname = entry.trackingNickname ?? senderNickname
		let isAvailable = trackingStatus == .available
		switch message.command.uppercased() {
		case "JOIN" where isAvailable == false:
			setTrackedNickname(nickname, status: .signedOn, notify: true)
		case "QUIT" where isAvailable:
			setTrackedNickname(nickname, status: .signedOff, notify: true)
		case "NICK":
			setTrackedNickname(nickname, status: isAvailable ? .signedOff : .signedOn, notify: true)
		default:
			break
		}
	}
}
