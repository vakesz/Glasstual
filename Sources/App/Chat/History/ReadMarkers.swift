// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** Where each conversation's read marker has got to.

 Marking a conversation read is debounced: the user scrolls through several
 conversations in a second and the server only needs the newest point in each.
 The tracker holds what has been sent, what is waiting to be, and the timer
 that sends it. */
struct ReadMarkerTracker {
	/// The newest marker sent per conversation, keyed by conversation identifier.
	var sentDates: [String: Date] = [:]
	/// Markers waiting for the debounce to expire, keyed by conversation identifier.
	var pendingConversations: [String: Date] = [:]
	/// Fires once the debounce window closes, sending what is pending.
	let timer: SessionTimer
}

@MainActor
extension ServerSession {
	func readMarkerIsAvailable(for conversation: Conversation) -> Bool {
		ChatHistoryPolicy.canUseServerHistory(
			isLoggedIn: isLoggedIn,
			capabilityEnabled: environment.settings.synchronizeReadMarkers
				&& isCapabilityEnabled(.readMarker),
			isConsole: conversation.isConsole,
			isDirectChat: conversation.isDirectChat,
			isZNCDirectConversation: conversation.isDirect && conversation.isDirectForZNCUser,
			targetFailed: false
		)
	}

	func requestReadMarker(for conversation: Conversation) {
		guard readMarkerIsAvailable(for: conversation) else { return }
		send(.markread, arguments: [conversation.name])
	}

	func markConversation(asRead conversation: Conversation) {
		/* Without a view, the stored conversation is what was read. */
		let viewedDate = if let presentation = conversation.presentation {
			presentation.lastRenderedLineDate()
		} else {
			Scrollback.shared.duplicates.newestConversationLineDate(forView: conversation.uniqueIdentifier)
		}
		guard let date = viewedDate else { return }
		scheduleReadMarker(for: conversation, date: date)
	}

	func scheduleReadMarker(for conversation: Conversation, date: Date) {
		guard readMarkerIsAvailable(for: conversation),
		      ChatHistoryPolicy.shouldAdvanceMarker(
		      	candidate: date,
		      	previous: readMarkers.sentDates[conversation.uniqueIdentifier]
		      )
		else { return }
		let identifier = conversation.uniqueIdentifier
		readMarkers.pendingConversations[identifier] = max(date, readMarkers.pendingConversations[identifier] ?? .distantPast)
		if !readMarkers.timer.isActive {
			readMarkers.timer.start(ChatHistoryPolicy.readMarkerDebounceInterval)
		}
	}

	func onReadMarkerTimer() {
		let pending = readMarkers.pendingConversations
		readMarkers.pendingConversations.removeAll()
		for (identifier, date) in pending {
			guard let conversation = conversationList.first(where: { $0.uniqueIdentifier == identifier }) else { continue }
			sendReadMarker(for: conversation, date: date)
		}
	}

	func sendReadMarker(for conversation: Conversation, date newestDate: Date) {
		guard !isTerminating, readMarkerIsAvailable(for: conversation),
		      ChatHistoryPolicy.shouldAdvanceMarker(
		      	candidate: newestDate,
		      	previous: readMarkers.sentDates[conversation.uniqueIdentifier]
		      )
		else { return }
		readMarkers.sentDates[conversation.uniqueIdentifier] = newestDate
		send(.markread, arguments: [conversation.name, chatHistoryTimestamp(for: newestDate)])
	}

	func receiveReadMarker(_ message: Message) {
		guard message.params.count >= 2, let conversation = findConversation(message.params[0]),
		      message.params[1].hasPrefix("timestamp="),
		      let date = DateFormatting.date(fromISO8601: String(message.params[1].dropFirst(10)))
		else { return }
		if ChatHistoryPolicy.shouldAdvanceMarker(
			candidate: date,
			previous: readMarkers.sentDates[conversation.uniqueIdentifier]
		) {
			readMarkers.sentDates[conversation.uniqueIdentifier] = date
		}
		applyReadMarker(readMarkers.sentDates[conversation.uniqueIdentifier] ?? date, to: conversation)
	}

	/** Brings `conversation`'s badge in line with the point the server says was read.

	 Only what a person said counts on either side of the comparison. A join
	 prints its own line, the topic and the channel modes stamped with now, so a
	 marker from before the join is older than the newest line in the view while
	 nothing in it is unread. */
	func applyReadMarker(_ date: Date, to conversation: Conversation) {
		let newestDate = newestKnownConversationLineDate(for: conversation)
		if newestDate.map({ $0 > date }) != true {
			if conversation.isUnread || conversation.nicknameHighlightCount > 0 {
				conversation.resetState()
				output?.refreshMessageCount(for: conversation)
				environment.services.updateDockBadge()
			}
			return
		}

		guard let output,
		      !output.isItemVisible(conversation) || !output.isKeyWindow
		else { return }
		conversation.presentation?.mark(at: date)
		/* The lines past the marker may have arrived in a join burst, which is
		 printed without touching the unread count. The server has just said they
		 are unread, so the badge comes from here instead. setUnreadState leaves a
		 conversation selected in the key window alone, and this only ever raises a
		 badge the conversation does not already have: the count is the number of
		 messages past the marker, so it says "these went unread" rather than
		 adding one to whatever a live line had already counted. */
		if conversation.isUnread == false {
			let unreadCount = conversation.presentation?.conversationLineCount(after: date) ?? 0
			setUnreadState(for: conversation, count: max(1, unreadCount))
		}
	}
}
