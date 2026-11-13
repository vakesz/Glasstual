// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// The decisions printing a line makes, as pure functions of what the caller
/// already knows, so each one can be asked without a window or a connection.
enum LinePresentationPolicy {
	static func memberType(nickname: String?, localNickname: String) -> ChatLineMemberKind {
		nickname == localNickname ? .localUser : .normal
	}

	/// The body a printed line keeps. "Remove formatting from incoming
	/// messages" strips the control codes of everything but the local user's
	/// own lines, and only the text: the line was parsed as it arrived.
	static func messageBody(
		_ body: String,
		memberType: ChatLineMemberKind,
		removesIncomingFormatting: Bool
	) -> String {
		guard removesIncomingFormatting, memberType != .localUser else { return body }
		return (body as NSString).stripIRCEffects
	}

	static func normalized(_ lineType: ChatLineKind) -> ChatLineKind {
		switch lineType {
		case .actionNoHighlight:
			.action
		case .privateMessageNoHighlight:
			.privateMessage
		default:
			lineType
		}
	}

	static func allowsHighlightMatching(
		conversationExists: Bool,
		ignoresHighlights: Bool,
		lineType: ChatLineKind,
		memberType: ChatLineMemberKind
	) -> Bool {
		conversationExists && ignoresHighlights == false &&
			(lineType == .privateMessage || lineType == .action) && memberType == .normal
	}

	/** Whether the unread boundary goes above the line being printed.

	 It does for the first line to arrive unseen and for no line after it,
	 until the reader has read the conversation again. `boundaryIsPlaced` is
	 what says so within a burst: the unread count is raised only once a line
	 has rendered, by which time the lines behind it have been printed too. */
	static func needsUnreadMarker(
		autoMark: Bool,
		itemIsVisible: Bool,
		windowIsMain: Bool,
		conversationIsUnread: Bool,
		boundaryIsPlaced: Bool,
		lineType: ChatLineKind
	) -> Bool {
		guard autoMark, itemIsVisible == false || windowIsMain == false,
		      conversationIsUnread == false, boundaryIsPlaced == false
		else {
			return false
		}
		return lineType == .privateMessage || lineType == .action || lineType == .notice
	}

	static func isFirstForDay(receivedAt: Date, previousDate: Date?) -> Bool {
		guard let previousDate else { return true }
		return Calendar.current.isDate(receivedAt, inSameDayAs: previousDate) == false
	}
}
