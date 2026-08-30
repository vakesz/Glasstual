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

struct ChannelInviteContent: Equatable, Sendable {
	let headerTitle: String
	let channels: [String]
	let channelPickerLabel: String
	let inviteButtonTitle: String
	let cancelButtonTitle: String
	let windowTitle: String

	init(nicknames: [String], channels: [String]) {
		let inviteeDescription: String = switch nicknames.count {
		case 0:
			""
		case 1:
			nicknames[0]
		case 2:
			ChannelInviteStrings.inviteePair(nicknames[0], nicknames[1])
		default:
			ChannelInviteStrings.inviteeCount(nicknames.count)
		}

		headerTitle = ChannelInviteStrings.invitationTitle(inviteeDescription: inviteeDescription)
		self.channels = channels
		channelPickerLabel = ChannelInviteStrings.channelPickerLabel
		inviteButtonTitle = ChannelInviteStrings.inviteButtonTitle
		cancelButtonTitle = ChannelInviteStrings.cancelButtonTitle
		windowTitle = ChannelInviteStrings.windowTitle
	}
}
