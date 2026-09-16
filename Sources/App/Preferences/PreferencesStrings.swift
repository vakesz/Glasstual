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

enum PreferencesStrings {
	static var accessibilityTitle: String {
		String(localized: .Settings.accessibilityLabelSettings)
	}

	static var downloadDestinationAccessibilityLabel: String {
		String(localized: .Settings.downloadDestination)
	}

	static var noDownloadDestination: String {
		String(localized: .Settings.noLocationSelected)
	}

	static var noSelectionMessage: String {
		String(localized: .Settings.noSelectionMessage)
	}

	static var noSelectionTitle: String {
		String(localized: .Settings.noSelectionTitle)
	}

	static var noTranscriptFolder: String {
		String(localized: .Settings.noLogLocationSelected)
	}

	static var transcriptFolderAccessibilityLabel: String {
		String(localized: .Settings.transcriptFolder)
	}
}
