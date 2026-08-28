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

nonisolated enum ServerNicknameChangeStrings {
	static var changeButtonTitle: String {
		String(localized: .TDCServerChangeNicknameSheet.changeButton)
	}

	static var currentNicknameLabel: String {
		String(localized: .TDCServerChangeNicknameSheet.currentNicknameLabel)
	}

	static var newNicknameLabel: String {
		String(localized: .TDCServerChangeNicknameSheet.newNicknameLabel)
	}
}
