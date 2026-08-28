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
	let upstreamAttribution: String
	let acknowledgementsButtonTitle: String
	let applicationIconAccessibilityLabel: String

	static var current: Self {
		let applicationName = ApplicationInfo.applicationNameWithoutVersion()
		let version = ApplicationInfo.applicationVersionShort()

		return Self(
			applicationName: applicationName,
			versionDescription: AboutStrings.versionDescription(
				applicationName: applicationName,
				version: version
			),
			upstreamAttribution: AboutStrings.upstreamAttribution,
			acknowledgementsButtonTitle: AboutStrings.acknowledgementsButtonTitle,
			applicationIconAccessibilityLabel: AboutStrings.applicationIconAccessibilityLabel(
				applicationName: applicationName
			)
		)
	}
}
