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

nonisolated enum ServerNicknameChangeStrings { // nonisolated: value
	static var changeButtonTitle: String {
		String(localized: .ServerProperties.changeButton)
	}

	static var currentNicknameLabel: String {
		String(localized: .ServerProperties.currentNicknameLabel)
	}

	static var newNicknameLabel: String {
		String(localized: .ServerProperties.newNicknameLabel)
	}

	static var newNicknamePlaceholder: String {
		String(localized: .ServerProperties.newNicknamePlaceholder)
	}

	static var changeDescription: String {
		String(localized: .ServerProperties.nicknameChangeDescription)
	}
}
