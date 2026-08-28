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

nonisolated enum PreferencesFileTransfersStrings {
	static var destinationLabel: String {
		String(localized: .TDCPreferencesController.fileTransfersDestinationLabel)
	}

	static var destinationNote: String {
		String(localized: .TDCPreferencesController.fileTransfersDestinationNote)
	}

	static var detectionAccessibility: String {
		String(localized: .TDCPreferencesController.fileTransfersDetectionAccessibility)
	}

	static var detectionLabel: String {
		String(localized: .TDCPreferencesController.fileTransfersDetectionLabel)
	}

	static var detectionManual: String {
		String(localized: .TDCPreferencesController.fileTransfersDetectionManual)
	}

	static var detectionRouterFirstParty: String {
		String(localized: .TDCPreferencesController.fileTransfersDetectionRouterFirstParty)
	}

	static var detectionRouterOnly: String {
		String(localized: .TDCPreferencesController.fileTransfersDetectionRouterOnly)
	}

	static var detectionRouterThirdParty: String {
		String(localized: .TDCPreferencesController.fileTransfersDetectionRouterThirdParty)
	}

	static var manualAddressAccessibility: String {
		String(localized: .TDCPreferencesController.fileTransfersManualAddressAccessibility)
	}

	static var manualAddressLabel: String {
		String(localized: .TDCPreferencesController.fileTransfersManualAddressLabel)
	}

	static var portRangeFirst: String {
		String(localized: .TDCPreferencesController.fileTransfersPortRangeFirst)
	}

	static var portRangeLabel: String {
		String(localized: .TDCPreferencesController.fileTransfersPortRangeLabel)
	}

	static var portRangeLast: String {
		String(localized: .TDCPreferencesController.fileTransfersPortRangeLast)
	}

	static var portRangeSeparator: String {
		String(localized: .TDCPreferencesController.fileTransfersPortRangeSeparator)
	}

	static var preventSleep: String {
		String(localized: .TDCPreferencesController.fileTransfersPreventSleep)
	}

	static var replyActionAccessibility: String {
		String(localized: .TDCPreferencesController.fileTransfersReplyActionAccessibility)
	}

	static var replyActionLabel: String {
		String(localized: .TDCPreferencesController.fileTransfersReplyActionLabel)
	}

	static var replyDownload: String {
		String(localized: .TDCPreferencesController.fileTransfersReplyDownload)
	}

	static var replyIgnore: String {
		String(localized: .TDCPreferencesController.fileTransfersReplyIgnore)
	}

	static var replyOpenDialog: String {
		String(localized: .TDCPreferencesController.fileTransfersReplyOpenDialog)
	}

	static var reverseDcc: String {
		String(localized: .TDCPreferencesController.fileTransfersReverseDcc)
	}
}

nonisolated enum PreferencesInlineMediaStrings {
	static var checkEverything: String {
		String(localized: .TDCPreferencesController.inlineMediaCheckEverything)
	}

	static var checkEverythingAccessibility: String {
		String(localized: .TDCPreferencesController.inlineMediaCheckEverythingAccessibility)
	}

	static var checkEverythingNote: String {
		String(localized: .TDCPreferencesController.inlineMediaCheckEverythingNote)
	}

	static var filesizeAccessibility: String {
		String(localized: .TDCPreferencesController.inlineMediaFilesizeAccessibility)
	}

	static var filesizeLabel: String {
		String(localized: .TDCPreferencesController.inlineMediaFilesizeLabel)
	}

	static var headingImages: String {
		String(localized: .TDCPreferencesController.inlineMediaHeadingImages)
	}

	static var headingLimitations: String {
		String(localized: .TDCPreferencesController.inlineMediaHeadingLimitations)
	}

	static var heightAccessibility: String {
		String(localized: .TDCPreferencesController.inlineMediaHeightAccessibility)
	}

	static var heightLabel: String {
		String(localized: .TDCPreferencesController.inlineMediaHeightLabel)
	}

	static var heightNote: String {
		String(localized: .TDCPreferencesController.inlineMediaHeightNote)
	}

	static var limitBasicsToFiles: String {
		String(localized: .TDCPreferencesController.inlineMediaLimitBasicsToFiles)
	}

	static var limitNaughty: String {
		String(localized: .TDCPreferencesController.inlineMediaLimitNaughty)
	}

	static var limitNaughtyNote: String {
		String(localized: .TDCPreferencesController.inlineMediaLimitNaughtyNote)
	}

	static var limitToBasics: String {
		String(localized: .TDCPreferencesController.inlineMediaLimitToBasics)
	}

	static var limitUnsafe: String {
		String(localized: .TDCPreferencesController.inlineMediaLimitUnsafe)
	}

	static var limitUnsafeNote: String {
		String(localized: .TDCPreferencesController.inlineMediaLimitUnsafeNote)
	}

	static func megabytes(count: Int) -> String {
		String(localized: .TDCPreferencesController.inlineMediaMegabytes(count))
	}

	static var oneMegabyte: String {
		String(localized: .TDCPreferencesController.inlineMediaOneMegabyte)
	}

	static var pixels: String {
		String(localized: .TDCPreferencesController.inlineMediaPixels)
	}

	static var pixelsWide: String {
		String(localized: .TDCPreferencesController.inlineMediaPixelsWide)
	}

	static var show: String {
		String(localized: .TDCPreferencesController.inlineMediaShow)
	}

	static var showNote: String {
		String(localized: .TDCPreferencesController.inlineMediaShowNote)
	}

	static var widthAccessibility: String {
		String(localized: .TDCPreferencesController.inlineMediaWidthAccessibility)
	}

	static var widthLabel: String {
		String(localized: .TDCPreferencesController.inlineMediaWidthLabel)
	}
}

nonisolated enum PreferencesLogLocationStrings {
	static var clearDestination: String {
		String(localized: .TDCPreferencesController.logLocationClearDestination)
	}

	static var label: String {
		String(localized: .TDCPreferencesController.logLocationLabel)
	}

	static var selectDestination: String {
		String(localized: .TDCPreferencesController.logLocationSelectDestination)
	}
}

nonisolated enum PreferencesHiddenStrings {
	static var appNap: String {
		String(localized: .TDCPreferencesController.hiddenAppNap)
	}

	static var customScrollbars: String {
		String(localized: .TDCPreferencesController.hiddenCustomScrollbars)
	}

	static var loadHistoryLazily: String {
		String(localized: .TDCPreferencesController.hiddenLoadHistoryLazily)
	}

	static var restartNote: String {
		String(localized: .TDCPreferencesController.hiddenRestartNote)
	}

	static var scrollbackVisibleLimit: String {
		String(localized: .TDCPreferencesController.hiddenScrollbackVisibleLimit)
	}

	static var scrollbackVisibleLimitNote: String {
		String(localized: .TDCPreferencesController.hiddenScrollbackVisibleLimitNote)
	}

	static var sidebarTranslucency: String {
		String(localized: .TDCPreferencesController.hiddenSidebarTranslucency)
	}

	static var warning: String {
		String(localized: .TDCPreferencesController.hiddenWarning)
	}

	static var warningLabel: String {
		String(localized: .TDCPreferencesController.hiddenWarningLabel)
	}

	static var webkitPreviewLinks: String {
		String(localized: .TDCPreferencesController.hiddenWebkitPreviewLinks)
	}

	static var webkitProcessPool: String {
		String(localized: .TDCPreferencesController.hiddenWebkitProcessPool)
	}
}
