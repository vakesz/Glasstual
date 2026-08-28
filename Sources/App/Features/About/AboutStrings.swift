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

nonisolated enum AboutStrings {
	static var acknowledgementsButtonTitle: String {
		String(localized: .TDCAboutDialog.acknowledgementsButton)
	}

	static var upstreamAttribution: String {
		String(localized: .TDCAboutDialog.upstreamAttribution)
	}

	static func applicationIconAccessibilityLabel(applicationName: String) -> String {
		String(localized: .TDCAboutDialog.iconAccessibility(applicationName))
	}

	static func versionDescription(applicationName: String, version: String) -> String {
		String(localized: .TDCAboutDialog.applicationNameFollowed(applicationName, version))
	}
}
