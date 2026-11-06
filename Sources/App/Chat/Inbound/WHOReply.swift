// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

struct WHOFlags: Equatable {
	let isAway: Bool
	let isIRCop: Bool
	let isBot: Bool
	let userModes: String

	/// - Parameter botFlag: The character ISUPPORT `BOT=` names, which is the
	///   one a bot is flagged with; `nil` where the server advertised none.
	static func parse(
		_ flags: String,
		monitorAwayStatus: Bool,
		botFlag: String?,
		modeForPrefix: (String) -> String?
	) -> WHOFlags {
		var isAway = false
		var isIRCop = false
		var isBot = false
		var modes = ""
		for character in flags.map(String.init) {
			switch character {
			case "G": isAway = monitorAwayStatus
			case "*": isIRCop = true
			case botFlag: isBot = true
			default:
				if let mode = modeForPrefix(character) {
					modes += mode
				}
			}
		}
		return WHOFlags(isAway: isAway, isIRCop: isIRCop, isBot: isBot, userModes: modes)
	}
}

struct WHOReply {
	let nickname: String
	let username: String
	let address: String
	let flags: String
	let realName: String
	let account: String?
	let updatesAccount: Bool
}
