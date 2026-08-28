/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation

nonisolated enum ChannelInviteStrings {
	static var cancelButtonTitle: String {
		String(localized: .TDCChannelInviteSheet.cancelButton)
	}

	static var channelPickerLabel: String {
		String(localized: .TDCChannelInviteSheet.channelPickerLabel)
	}

	static var inviteButtonTitle: String {
		String(localized: .TDCChannelInviteSheet.inviteButton)
	}

	static var windowTitle: String {
		String(localized: .TDCChannelInviteSheet.windowTitle)
	}

	static func inviteeCount(_ count: Int) -> String {
		String(localized: .TDCChannelInviteSheet.describesAnInvitationUsers(count))
	}

	static func inviteePair(_ firstNickname: String, _ secondNickname: String) -> String {
		String(localized: .TDCChannelInviteSheet.joinsExactlyTwoNicknames(firstNickname, secondNickname))
	}

	static func invitationTitle(inviteeDescription: String) -> String {
		String(localized: .TDCChannelInviteSheet.headingAboveTheChannelInvite(inviteeDescription))
	}
}
