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

struct ServerNicknameChangeContent: Equatable, Sendable {
	let currentNicknameLabel: String
	let newNicknameLabel: String
	let changeButtonTitle: String
	let cancelButtonTitle: String
	let windowTitle: String

	static var current: Self {
		let changeButtonTitle = ServerNicknameChangeStrings.changeButtonTitle

		return Self(
			currentNicknameLabel: ServerNicknameChangeStrings.currentNicknameLabel,
			newNicknameLabel: ServerNicknameChangeStrings.newNicknameLabel,
			changeButtonTitle: changeButtonTitle,
			cancelButtonTitle: PromptStrings.Action.cancel,
			windowTitle: changeButtonTitle
		)
	}
}
