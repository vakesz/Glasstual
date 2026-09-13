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

enum PreferencesFileTransfersStrings {
	static var destinationLabel: String {
		String(localized: .Settings.fileTransfersDestinationLabel)
	}

	static var destinationNote: String {
		String(localized: .Settings.fileTransfersDestinationNote)
	}

	static var detectionAccessibility: String {
		String(localized: .Settings.fileTransfersDetectionAccessibility)
	}

	static var detectionLabel: String {
		String(localized: .Settings.fileTransfersDetectionLabel)
	}

	static var detectionManual: String {
		String(localized: .Settings.fileTransfersDetectionManual)
	}

	static var detectionRouterFirstParty: String {
		String(localized: .Settings.fileTransfersDetectionRouterFirstParty)
	}

	static var detectionRouterOnly: String {
		String(localized: .Settings.fileTransfersDetectionRouterOnly)
	}

	static var detectionRouterThirdParty: String {
		String(localized: .Settings.fileTransfersDetectionRouterThirdParty)
	}

	static var manualAddressAccessibility: String {
		String(localized: .Settings.fileTransfersManualAddressAccessibility)
	}

	static var manualAddressLabel: String {
		String(localized: .Settings.fileTransfersManualAddressLabel)
	}

	static var portRangeFirst: String {
		String(localized: .Settings.fileTransfersPortRangeFirst)
	}

	static var portRangeLabel: String {
		String(localized: .Settings.fileTransfersPortRangeLabel)
	}

	static var portRangeLast: String {
		String(localized: .Settings.fileTransfersPortRangeLast)
	}

	static var portRangeSeparator: String {
		String(localized: .Settings.fileTransfersPortRangeSeparator)
	}

	static var preventSleep: String {
		String(localized: .Settings.fileTransfersPreventSleep)
	}

	static var replyActionAccessibility: String {
		String(localized: .Settings.fileTransfersReplyActionAccessibility)
	}

	static var replyActionLabel: String {
		String(localized: .Settings.fileTransfersReplyActionLabel)
	}

	static var replyDownload: String {
		String(localized: .Settings.fileTransfersReplyDownload)
	}

	static var replyIgnore: String {
		String(localized: .Settings.fileTransfersReplyIgnore)
	}

	static var replyOpenDialog: String {
		String(localized: .Settings.fileTransfersReplyOpenDialog)
	}

	static var reverseDcc: String {
		String(localized: .Settings.fileTransfersReverseDcc)
	}
}

enum PreferencesLogLocationStrings {
	static var clearDestination: String {
		String(localized: .Settings.logLocationClearDestination)
	}

	static var folderLabel: String {
		String(localized: .Settings.logLocationFolderLabel)
	}

	static var logToDisk: String {
		String(localized: .Settings.logLocationToggle)
	}

	static var selectDestination: String {
		String(localized: .Settings.logLocationSelectDestination)
	}
}

enum PreferencesHiddenStrings {
	static var appNap: String {
		String(localized: .Settings.hiddenAppNap)
	}

	static var loadHistoryLazily: String {
		String(localized: .Settings.hiddenLoadHistoryLazily)
	}

	static var restartNote: String {
		String(localized: .Settings.hiddenRestartNote)
	}

	static var scrollbackVisibleLimit: String {
		String(localized: .Settings.hiddenScrollbackVisibleLimit)
	}

	static var scrollbackVisibleLimitNote: String {
		String(localized: .Settings.hiddenScrollbackVisibleLimitNote)
	}

	static var sidebarTranslucency: String {
		String(localized: .Settings.hiddenSidebarTranslucency)
	}

	static var warning: String {
		String(localized: .Settings.hiddenWarning)
	}
}
