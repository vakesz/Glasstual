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

/// Channel modes edited by the channel-modes feature.
///
/// IRC mode letters are a wire-format boundary. Keeping that mapping here
/// prevents view and presentation code from passing unvalidated magic strings.
enum ChannelMode: String, CaseIterable, Sendable {
	case inviteOnly = "i"
	case moderated = "m"
	case noExternalMessages = "n"
	case privateChannel = "p"
	case secretChannel = "s"
	case operatorTopic = "t"
	case key = "k"
	case userLimit = "l"

	static let booleanModes: [Self] = [
		.secretChannel,
		.privateChannel,
		.noExternalMessages,
		.operatorTopic,
		.inviteOnly,
		.moderated,
	]
}
