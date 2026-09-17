// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** Where each channel's read marker has got to.

 Marking a channel read is debounced: the user scrolls through several channels
 in a second and the server only needs the newest point in each. The tracker
 holds what has been sent, what is waiting to be, and the timer that sends it. */
struct ReadMarkerTracker {
	/// The newest marker sent per channel, keyed by channel identifier.
	var sentDates: [String: Date] = [:]
	/// Markers waiting for the debounce to expire, keyed by channel identifier.
	var pendingChannels: [String: Date] = [:]
	var timer: ClientTimer!
}

@MainActor
extension Client {
	func readMarkerIsAvailable(for channel: Channel) -> Bool {
		ChatHistoryPolicy.canUseServerHistory(
			isLoggedIn: isLoggedIn,
			capabilityEnabled: environment.preferences.synchronizeReadMarkers
				&& isCapabilityEnabled(.readMarker),
			isUtility: channel.isUtility,
			isDirectChat: channel.isDirectChat,
			isZNCQuery: channel.isPrivateMessage && channel.isPrivateMessageForZNCUser,
			targetFailed: false
		)
	}

	func requestReadMarker(for channel: Channel) {
		guard readMarkerIsAvailable(for: channel) else { return }
		send("MARKREAD", arguments: [channel.name])
	}

	func markChannel(asRead channel: Channel) {
		/* Without a view, the stored conversation is what was read. */
		let viewedDate = if let presentation = channel.presentation {
			presentation.lastRenderedLineDate()
		} else {
			Scrollback.shared.newestConversationLineDate(forView: channel.uniqueIdentifier)
		}
		guard let date = viewedDate else { return }
		scheduleReadMarker(for: channel, date: date)
	}

	func scheduleReadMarker(for channel: Channel, date: Date) {
		guard readMarkerIsAvailable(for: channel),
		      ChatHistoryPolicy.shouldAdvanceMarker(
		      	candidate: date,
		      	previous: readMarkers.sentDates[channel.uniqueIdentifier]
		      )
		else { return }
		let identifier = channel.uniqueIdentifier
		readMarkers.pendingChannels[identifier] = max(date, readMarkers.pendingChannels[identifier] ?? .distantPast)
		if !readMarkers.timer.isActive {
			readMarkers.timer.start(ChatHistoryPolicy.readMarkerDebounceInterval)
		}
	}

	func onReadMarkerTimer() {
		let channels = readMarkers.pendingChannels
		readMarkers.pendingChannels.removeAll()
		for (identifier, date) in channels {
			guard let channel = channelList.first(where: { $0.uniqueIdentifier == identifier }) else { continue }
			sendReadMarker(for: channel, date: date)
		}
	}

	func sendReadMarker(for channel: Channel, date newestDate: Date) {
		guard !isTerminating, readMarkerIsAvailable(for: channel),
		      ChatHistoryPolicy.shouldAdvanceMarker(
		      	candidate: newestDate,
		      	previous: readMarkers.sentDates[channel.uniqueIdentifier]
		      )
		else { return }
		readMarkers.sentDates[channel.uniqueIdentifier] = newestDate
		send("MARKREAD", arguments: [channel.name, chatHistoryTimestamp(for: newestDate)])
	}

	func receiveReadMarker(_ message: Message) {
		guard message.params.count >= 2, let channel = findChannel(message.params[0]),
		      message.params[1].hasPrefix("timestamp="),
		      let date = DateFormatting.date(fromISO8601: String(message.params[1].dropFirst(10)))
		else { return }
		if ChatHistoryPolicy.shouldAdvanceMarker(
			candidate: date,
			previous: readMarkers.sentDates[channel.uniqueIdentifier]
		) {
			readMarkers.sentDates[channel.uniqueIdentifier] = date
		}
		applyReadMarker(readMarkers.sentDates[channel.uniqueIdentifier] ?? date, to: channel)
	}

	/** Brings `channel`'s badge in line with the point the server says was read.

	 Only what a person said counts on either side of the comparison. A join
	 prints its own line, the topic and the channel modes stamped with now, so a
	 marker from before the join is older than the newest line in the view while
	 nothing in it is unread. */
	func applyReadMarker(_ date: Date, to channel: Channel) {
		let newestDate = newestKnownConversationLineDate(for: channel)
		if newestDate.map({ $0 > date }) != true {
			if channel.isUnread || channel.nicknameHighlightCount > 0 {
				channel.resetState()
				output?.refreshMessageCount(for: channel)
				DockIcon.updateDockIcon()
			}
			return
		}

		guard let output,
		      !output.isItemVisible(channel) || !output.isKeyWindow
		else { return }
		channel.presentation?.mark(at: date)
		/* The lines past the marker may have arrived in a join burst, which is
		 printed without touching the unread count. The server has just said they
		 are unread, so the badge comes from here instead. setUnreadState leaves a
		 channel selected in the key window alone, and this only ever raises a
		 badge the channel does not already have: the count is the number of
		 messages past the marker, so it says "these went unread" rather than
		 adding one to whatever a live line had already counted. */
		if channel.isUnread == false {
			let unreadCount = channel.presentation?.conversationLineCount(after: date) ?? 0
			setUnreadState(for: channel, count: max(1, unreadCount))
		}
	}
}
