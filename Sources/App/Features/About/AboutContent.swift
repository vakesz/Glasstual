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

struct AboutContent: Equatable, Sendable {
	let applicationName: String
	let versionDescription: String
	/// `NSHumanReadableCopyright`, the same line the standard About panel
	/// shows. It already says this is a fork of Textual, so the panel says it
	/// once rather than twice.
	let copyright: String
	let acknowledgementsButtonTitle: String
	let applicationIconAccessibilityLabel: String

	static var current: Self {
		let applicationName = ApplicationInfo.applicationName()

		return Self(
			applicationName: applicationName,
			versionDescription: AboutStrings.versionDescription(
				version: ApplicationInfo.applicationVersionShort(),
				build: ApplicationInfo.applicationVersion()
			),
			copyright: ApplicationInfo.applicationCopyright(),
			acknowledgementsButtonTitle: AboutStrings.acknowledgementsButtonTitle,
			applicationIconAccessibilityLabel: AboutStrings.applicationIconAccessibilityLabel(
				applicationName: applicationName
			)
		)
	}
}
