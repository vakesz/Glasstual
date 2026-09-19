// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/** What a stored line reads as in plain text.

 The transcript log is what this exists for: a line written to disk carries its
 own clock and nickname decoration because nothing replays a theme over it
 later. It sits beside the logger rather than on ``ChatLine`` so that the stored
 value stays a value — these are the only members that would give it a theme, a
 conversation and the main actor. */
nonisolated extension ChatLine {
	@MainActor
	func formattedNickname(in conversation: Conversation?) -> String? {
		formattedNickname(in: conversation, with: nil)
	}

	@MainActor
	func formattedNickname(in conversation: Conversation?, with format: String?) -> String? {
		guard let nickname else {
			return nil
		}

		if format == nil, let decorated = decoratedNicknameForLineType(nickname) {
			return decorated
		}

		return conversation?.associatedSession?.formatNickname(nickname, in: conversation, withFormat: format)
	}

	/// Actions and notices carry their own decoration instead of the theme format.
	private func decoratedNicknameForLineType(_ nickname: String) -> String? {
		switch lineType {
		case .action:
			String(format: ChatLineFormat.actionNickname, nickname)
		case .notice:
			String(format: ChatLineFormat.noticeNickname, nickname)
		default:
			nil
		}
	}

	@MainActor var renderedBodyForTranscriptLog: String {
		renderedBodyForTranscriptLog(in: nil)
	}

	@MainActor
	func renderedBodyForTranscriptLog(in conversation: Conversation?) -> String {
		/* The transcript log writes its own clock, not the theme's: a line on
		 disk is read without one. */
		var components = [DateFormatting.timestamp(receivedAt, format: ChatLineFormat.loggerClock) ?? ""]

		let nicknameFormat = switch lineType {
		case .action: ChatLineFormat.loggerActionNickname
		case .notice: ChatLineFormat.loggerNoticeNickname
		default: ChatLineFormat.loggerUndefinedNickname
		}

		if let formattedNickname = formattedNickname(in: conversation, with: nicknameFormat) {
			components.append(formattedNickname)
		}

		components.append(messageBody)

		return (components.joined(separator: " ") as NSString).stripIRCEffects
	}
}
