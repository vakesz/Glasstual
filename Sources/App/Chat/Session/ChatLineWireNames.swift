// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** The tokens and templates a printed line is spelled with.

 `defaultCommand` and the two nickname decorations are read by the printing
 path; the `logger…` templates are read by the transcript log. They are
 gathered here rather than on ``ChatLine`` because the stored line is a value
 and none of these are part of what is stored. */
nonisolated enum ChatLineFormat {
	static let actionNickname = "%@ "
	/// The command a line Glasstual printed itself carries, in place of the
	/// server command a line off the wire has.
	static let defaultCommand = "-100"
	static let loggerActionNickname = "\u{2022} %n:"
	static let loggerClock = "[%Y-%m-%dT%H:%M:%S%z]"
	static let loggerNoticeNickname = "-%n-"
	static let loggerUndefinedNickname = "<%@%n>"
	static let noticeNickname = "-%@-"
	static let specialNoticeMessage = "[%@]: %@"
}

/** How a line's enumerations are named outside the model.

 These strings are the renderer's attribute-dictionary values and the tokens
 the link parser matches on, so they are a contract with the transcript rather
 than presentation: a line type keeps its name whatever theme is loaded. */
nonisolated extension ChatLine {
	static func string(for type: ChatLineKind) -> String? {
		switch type {
		case .action, .actionNoHighlight:
			"action"
		case .ctcp, .ctcpQuery, .ctcpReply:
			"ctcp"
		case .dccFileTransfer:
			"dcc-file-transfer"
		case .debug:
			"debug"
		case .invite:
			"invite"
		case .join:
			"join"
		case .kick:
			"kick"
		case .kill:
			"kill"
		case .mode:
			"mode"
		case .nick:
			"nick"
		case .notice:
			"notice"
		case .offTheRecordEncryptionStatus:
			"off-the-record-encryption-status"
		case .part:
			"part"
		case .privateMessage, .privateMessageNoHighlight:
			"privmsg"
		case .quit:
			"quit"
		case .topic:
			"topic"
		case .website:
			"website"
		default:
			nil
		}
	}

	static func string(for type: ChatLineMemberKind) -> String {
		type == .localUser ? "myself" : "normal"
	}

	static func string(for state: ChatLineDeliveryState) -> String? {
		switch state {
		case .pending:
			"pending"
		case .delivered:
			"delivered"
		case .failed:
			"failed"
		default:
			nil
		}
	}

	var lineTypeString: String? {
		Self.string(for: lineType)
	}
}
