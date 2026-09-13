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

nonisolated enum AboutStrings { // nonisolated: value
	static var acknowledgementsButtonTitle: String {
		String(localized: .TDCAboutDialog.acknowledgementsButton)
	}

	static func applicationIconAccessibilityLabel(applicationName: String) -> String {
		String(localized: .TDCAboutDialog.iconAccessibility(applicationName))
	}

	/// The application name is drawn above this, so the line under it says what
	/// version that name is at rather than repeating the name.
	static func versionDescription(version: String, build: String) -> String {
		guard build.isEmpty == false, build != version else {
			return String(localized: .TDCAboutDialog.applicationVersion(version))
		}

		return String(localized: .TDCAboutDialog.applicationVersionWithBuild(version, build))
	}
}
