/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation

nonisolated enum MessageMenuStrings { // nonisolated: value
	static var otherReaction: String {
		String(localized: .MainWindow.messageContextMenuRepliesOther)
	}

	static var react: String {
		String(localized: .MainWindow.messageContextMenuRepliesReact)
	}

	static var reply: String {
		String(localized: .MainWindow.messageContextMenuRepliesReply)
	}

	static var share: String {
		String(localized: .MainWindow.titleOfTheStandardShare)
	}
}
