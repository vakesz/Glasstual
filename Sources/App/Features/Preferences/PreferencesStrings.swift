/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
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

enum PreferencesStrings {
	static var accessibilityTitle: String {
		String(localized: .TDCPreferencesController.sbTt)
	}

	static var addOnPaneTitle: String {
		String(localized: .TDCPreferencesController.sbPlugin)
	}

	static var addOnsGroupTitle: String {
		String(localized: .TDCPreferencesController.sbGrAd)
	}

	static var advancedGroupTitle: String {
		String(localized: .TDCPreferencesController.sbGrAv)
	}

	static var backButtonTitle: String {
		String(localized: .TDCPreferencesController.tbBack)
	}

	static var createStyleCopyButtonTitle: String {
		String(localized: .TDCPreferencesController.dj81T)
	}

	static var downloadDestinationAccessibilityLabel: String {
		String(localized: .TDCPreferencesController.axDownloadFolder)
	}

	static var editStyleButtonTitle: String {
		String(localized: .TDCPreferencesController.aibIy)
	}

	static var forwardButtonTitle: String {
		String(localized: .TDCPreferencesController.tbForward)
	}

	static var noDownloadDestination: String {
		String(localized: .TDCPreferencesController._721Ie)
	}

	static var noTranscriptFolder: String {
		String(localized: .TDCPreferencesController._70SC6)
	}

	static var preferredSelectionTitle: String {
		String(localized: .TDCPreferencesController.uc0Z7)
	}

	static var styleAccessibilityLabel: String {
		String(localized: .TDCPreferencesController.axTheme)
	}

	static var styleModificationBody: String {
		String(localized: .TDCPreferencesController.ojjAp)
	}

	static var styleModificationTitle: String {
		String(localized: .TDCPreferencesController._5JvAw)
	}

	static var transcriptFolderAccessibilityLabel: String {
		String(localized: .TDCPreferencesController.axTranscriptFolder)
	}

	static var viewStyleFilesButtonTitle: String {
		String(localized: .TDCPreferencesController._6WsAv)
	}

	static func paneTitle(_ identifier: PreferencesPaneIdentifier) -> String {
		let resource = switch identifier {
		case .addOns: LocalizedStringResource.TDCPreferencesController.sbAddons
		case .behavior: LocalizedStringResource.TDCPreferencesController.sbBehavior
		case .channelManagement: LocalizedStringResource.TDCPreferencesController.sbChannelManagement
		case .commandScope: LocalizedStringResource.TDCPreferencesController.sbCommandScope
		case .compatibility: LocalizedStringResource.TDCPreferencesController.sbCompatibility
		case .controls: LocalizedStringResource.TDCPreferencesController.sbControls
		case .defaultIRCopMessages: LocalizedStringResource.TDCPreferencesController.sbDefaultIRCopMessages
		case .defaultIdentity: LocalizedStringResource.TDCPreferencesController.sbDefaultIdentity
		case .fileTransfers: LocalizedStringResource.TDCPreferencesController.sbFileTransfers
		case .floodControl: LocalizedStringResource.TDCPreferencesController.sbFloodControl
		case .general: LocalizedStringResource.TDCPreferencesController.sbGeneral
		case .hidden: LocalizedStringResource.TDCPreferencesController.sbHidden
		case .highlights: LocalizedStringResource.TDCPreferencesController.sbHighlights
		case .incomingData: LocalizedStringResource.TDCPreferencesController.sbIncomingData
		case .inlineMedia: LocalizedStringResource.TDCPreferencesController.sbInlineMedia
		case .interface: LocalizedStringResource.TDCPreferencesController.sbInterface
		case .logLocation: LocalizedStringResource.TDCPreferencesController.sbLogLocation
		case .notifications: LocalizedStringResource.TDCPreferencesController.sbNotifications
		case .style: LocalizedStringResource.TDCPreferencesController.sbStyle
		}
		return String(localized: resource)
	}

	static func preferredSelectionBody(styleName: String, overrides: [PreferencesThemeOverride]) -> String {
		let overrideList = overrides.map(overrideTitle).joined(separator: "\n")
		return String(localized: .TDCPreferencesController.q4O2F(styleName, overrideList))
	}

	static func version(marketingVersion: String, build: String) -> String {
		String(localized: .TDCPreferencesController.sbVers(marketingVersion, build))
	}

	private static func overrideTitle(_ override: PreferencesThemeOverride) -> String {
		switch override {
		case .channelViewFont:
			String(localized: .TDCPreferencesController.we8I8)
		case .nicknameFormat:
			String(localized: .TDCPreferencesController._77TDe)
		case .timestampFormat:
			String(localized: .TDCPreferencesController.ddhHr)
		}
	}
}
