/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation

nonisolated enum ChannelInviteStrings { // nonisolated: value
	static var channelPickerLabel: String {
		String(localized: .TDCChannelInviteSheet.channelPickerLabel)
	}

	static var inviteButtonTitle: String {
		String(localized: .TDCChannelInviteSheet.inviteButton)
	}

	static var windowTitle: String {
		String(localized: .TDCChannelInviteSheet.windowTitle)
	}

	/// Who the invitation is for: the one nickname, both of them, or how many
	/// there are once naming them all would be a paragraph.
	static func invitationTitle(for nicknames: [String]) -> String {
		let invitees = switch nicknames.count {
		case 0:
			""
		case 1:
			nicknames[0]
		case 2:
			String(localized: .TDCChannelInviteSheet.joinsExactlyTwoNicknames(nicknames[0], nicknames[1]))
		default:
			String(localized: .TDCChannelInviteSheet.inviteeCount(nicknames.count))
		}

		return String(localized: .TDCChannelInviteSheet.headingAboveTheChannelInvite(invitees))
	}
}
