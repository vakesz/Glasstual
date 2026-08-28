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

struct ProgressIndicatorContent: Equatable, Sendable {
	let statusMessage: String
	let windowTitle: String

	static var current: Self {
		Self(
			statusMessage: ProgressIndicatorStrings.statusMessage,
			windowTitle: ProgressIndicatorStrings.windowTitle
		)
	}
}
