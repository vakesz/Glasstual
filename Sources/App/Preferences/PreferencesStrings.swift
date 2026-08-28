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

enum PreferencesThemeOverride: Sendable {
	case channelViewFont
	case nicknameFormat
	case timestampFormat
}

nonisolated enum PreferencesStrings {
	static var accessibilityTitle: String {
		String(localized: .TDCPreferencesController.accessibilityLabelSettings)
	}

	static var addOnPaneTitle: String {
		String(localized: .TDCPreferencesController.fallbackTitleAdd)
	}

	static var addOnsGroupTitle: String {
		String(localized: .TDCPreferencesController.addOns)
	}

	static var advancedGroupTitle: String {
		String(localized: .TDCPreferencesController.titleOfTheAdvanced)
	}

	static var createStyleCopyButtonTitle: String {
		String(localized: .TDCPreferencesController.createCopy)
	}

	static var downloadDestinationAccessibilityLabel: String {
		String(localized: .TDCPreferencesController.downloadDestination)
	}

	static var editStyleButtonTitle: String {
		String(localized: .TDCPreferencesController.editStyle)
	}

	static var noDownloadDestination: String {
		String(localized: .TDCPreferencesController.noLocationSelected)
	}

	static var noTranscriptFolder: String {
		String(localized: .TDCPreferencesController.noLogLocationSelected)
	}

	static var preferredSelectionTitle: String {
		String(localized: .TDCPreferencesController.preferredSelection)
	}

	static var styleAccessibilityLabel: String {
		String(localized: .TDCPreferencesController.accessibilityLabelStyle)
	}

	static var styleModificationBody: String {
		String(localized: .TDCPreferencesController.itsPossibleToModifyTheAppearance)
	}

	static var styleModificationTitle: String {
		String(localized: .TDCPreferencesController.areYouOpeningThisStyleBecause)
	}

	static var transcriptFolderAccessibilityLabel: String {
		String(localized: .TDCPreferencesController.transcriptFolder)
	}

	static var viewStyleFilesButtonTitle: String {
		String(localized: .TDCPreferencesController.viewFiles)
	}

	static func paneTitle(_ identifier: PreferencesPaneIdentifier) -> String {
		let resource = switch identifier {
		case .addOns: LocalizedStringResource.TDCPreferencesController.installedAddOns
		case .behavior: LocalizedStringResource.TDCPreferencesController.titleOfTheBehavior
		case .channelManagement: LocalizedStringResource.TDCPreferencesController.channelManagement
		case .commandScope: LocalizedStringResource.TDCPreferencesController.commandScope
		case .compatibility: LocalizedStringResource.TDCPreferencesController.titleOfTheCompatibility
		case .controls: LocalizedStringResource.TDCPreferencesController.titleOfTheControls
		case .defaultIRCopMessages: LocalizedStringResource.TDCPreferencesController.ircopMessages
		case .defaultIdentity: LocalizedStringResource.TDCPreferencesController.defaultIdentity
		case .fileTransfers: LocalizedStringResource.TDCPreferencesController.fileTransfers
		case .floodControl: LocalizedStringResource.TDCPreferencesController.floodControl
		case .general: LocalizedStringResource.TDCPreferencesController.titleOfTheGeneral
		case .hidden: LocalizedStringResource.TDCPreferencesController.titleOfTheHidden
		case .highlights: LocalizedStringResource.TDCPreferencesController.titleOfTheHighlights
		case .incomingData: LocalizedStringResource.TDCPreferencesController.incomingData
		case .inlineMedia: LocalizedStringResource.TDCPreferencesController.inlineMedia
		case .interface: LocalizedStringResource.TDCPreferencesController.titleOfTheInterface
		case .logLocation: LocalizedStringResource.TDCPreferencesController.logLocation
		case .notifications: LocalizedStringResource.TDCPreferencesController.titleOfTheNotifications
		case .style: LocalizedStringResource.TDCPreferencesController.titleOfTheStyle
		}
		return String(localized: resource)
	}

	static func preferredSelectionBody(styleName: String, overrides: [PreferencesThemeOverride]) -> String {
		let overrideList = overrides.map(overrideTitle).joined(separator: "\n")
		return String(localized: .TDCPreferencesController.styleNamedHasChosenToOverride(styleName, overrideList))
	}

	private static func overrideTitle(_ override: PreferencesThemeOverride) -> String {
		switch override {
		case .channelViewFont:
			String(localized: .TDCPreferencesController.channelViewFont)
		case .nicknameFormat:
			String(localized: .TDCPreferencesController.nicknameFormat)
		case .timestampFormat:
			String(localized: .TDCPreferencesController.timestampFormat)
		}
	}
}
