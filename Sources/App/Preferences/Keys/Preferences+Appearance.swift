/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import Foundation

// MARK: - Appearance

public nonisolated extension Preferences { // nonisolated: value
	/// Window chrome, the two sidebars, and the web view hosting the channel.
	enum Appearance {
		public static let preferredAppearance = PreferenceKey(
			"Appearance",
			default: TXPreferredAppearance.inherited
		)

		public static let disableSidebarTranslucency = PreferenceKey("DisableSidebarTranslucency", default: false)
		public static let memberListNoModeSymbol = PreferenceKey("DisplayUserListNoModeSymbol", default: true)
		public static let memberListSortFavorsServerStaff = PreferenceKey(
			"MemberListSortFavorsServerStaff",
			default: false
		)

		public static let memberListUpdatesPopoverOnScroll = PreferenceKey(
			"MemberListUpdatesUserInfoPopoverOnScroll",
			default: true
		)

		public static let conversationTrackingIncludesModeSymbol = PreferenceKey(
			"ConversationTrackingIncludesUserModeSymbol",
			default: false
		)

		public static let trackUserAwayStatusMaximumChannelSize = PreferenceKey(
			"TrackUserAwayStatusMaximumChannelSize",
			default: UInt(300)
		)

		public static let channelNavigationIsServerSpecific = PreferenceKey(
			"ChannelNavigationIsServerSpecific",
			default: true
		)

		public static let connectOnDoubleClick = PreferenceKey(
			"ServerListDoubleClickConnectServer",
			default: false
		)

		public static let disconnectOnDoubleClick = PreferenceKey(
			"ServerListDoubleClickDisconnectServer",
			default: false
		)

		public static let joinOnDoubleClick = PreferenceKey("ServerListDoubleClickJoinChannel", default: false)
		public static let leaveOnDoubleClick = PreferenceKey("ServerListDoubleClickLeaveChannel", default: false)

		public static let rememberQueryStates = PreferenceKey(
			"ServerListRetainsQueriesBetweenRestarts",
			default: false
		)

		public static let webViewCustomScrollersDisabled = PreferenceKey(
			"WebViewDoNotUsesCustomScrollers",
			default: false
		)

		public static let webViewPreviewLinks = PreferenceKey("WebViewPreviewLinks", default: false)
		public static let webViewProcessPoolLimited = PreferenceKey("WebViewProcessPoolSizeIsLimited", default: true)

		static let all: [any AnyPreferenceKey] = [
			preferredAppearance, disableSidebarTranslucency, memberListNoModeSymbol,
			memberListSortFavorsServerStaff, memberListUpdatesPopoverOnScroll,
			conversationTrackingIncludesModeSymbol, trackUserAwayStatusMaximumChannelSize,
			channelNavigationIsServerSpecific, connectOnDoubleClick, disconnectOnDoubleClick,
			joinOnDoubleClick, leaveOnDoubleClick, rememberQueryStates, webViewCustomScrollersDisabled,
			webViewPreviewLinks, webViewProcessPoolLimited,
		]
	}
}

// MARK: - Theme

public nonisolated extension Preferences { // nonisolated: value
	/// The active style and the font and format overrides layered on top of it.
	enum Theme {
		public static let name = PreferenceKey("Theme -> Name", default: "resource:Lines")
		public static let fontName = PreferenceKey("Theme -> Font Name", default: ".AppleSystemUIFont")
		public static let fontSize = PreferenceKey("Theme -> Font Size", default: 13.0)
		public static let nicknameFormat = PreferenceKey("Theme -> Nickname Format", default: "<%@%n>")
		public static let timestampFormat = PreferenceKey("Theme -> Timestamp Format", default: "%H:%M:%S")

		public static let userStyleSheetRules = PreferenceKey(
			"Theme -> User Style Sheet Rules",
			default: "",
			traits: .unregistered
		)

		public static let reloadCustomThemesOnChange = PreferenceKey(
			"AutomaticallyReloadCustomThemesWhenTheyChange",
			default: false
		)

		/* The four "-> Did Not Exist During Last Sync" and "Preference Enabled"
		 keys describe the machine this copy of the application is running on,
		 not a choice the user made, so they stay out of an exported file. The
		 three "Preference Enabled" keys are written into the registration domain
		 by the theme controller at every launch rather than persisted. */

		public static let nameMissingLocally = PreferenceKey(
			"Theme -> Name -> Did Not Exist During Last Sync",
			default: false,
			traits: [.unregistered, .excludedFromExport]
		)

		public static let fontNameMissingLocally = PreferenceKey(
			"Theme -> Font Name -> Did Not Exist During Last Sync",
			default: false,
			traits: [.unregistered, .excludedFromExport]
		)

		public static let fontIsUserConfigurable = PreferenceKey(
			"Theme -> Channel Font Preference Enabled",
			default: false,
			traits: [.unregistered, .excludedFromExport]
		)

		public static let nicknameFormatIsUserConfigurable = PreferenceKey(
			"Theme -> Nickname Format Preference Enabled",
			default: false,
			traits: [.unregistered, .excludedFromExport]
		)

		public static let timestampFormatIsUserConfigurable = PreferenceKey(
			"Theme -> Timestamp Format Preference Enabled",
			default: false,
			traits: [.unregistered, .excludedFromExport]
		)

		static let all: [any AnyPreferenceKey] = [
			name, fontName, fontSize, nicknameFormat, timestampFormat, userStyleSheetRules,
			reloadCustomThemesOnChange, nameMissingLocally, fontNameMissingLocally,
			fontIsUserConfigurable, nicknameFormatIsUserConfigurable, timestampFormatIsUserConfigurable,
		]
	}
}

// MARK: - Badges

/** The user-list mode badges, keyed by the mode symbol they colour.

 The symbol, the preference key, the shipped colour and the tag the colour well
 in the preferences nib carries used to be four separate literal lists in three
 files; they are one declaration here. */
public nonisolated enum UserListModeBadge: String, CaseIterable, Sendable { // nonisolated: value
	case ircOperator = "+y"
	case channelOwner = "+q"
	case superOperator = "+a"
	case normalOperator = "+o"
	case halfOperator = "+h"
	case voiced = "+v"

	public var modeSymbol: String {
		rawValue
	}

	/// The tag on the matching colour well in the preferences nib.
	public var preferencesTag: Int {
		switch self {
		case .ircOperator: 10
		case .channelOwner: 9
		case .superOperator: 8
		case .normalOperator: 7
		case .halfOperator: 6
		case .voiced: 5
		}
	}

	public static func badge(forPreferencesTag tag: Int) -> Self? {
		allCases.first { $0.preferencesTag == tag }
	}

	public static func badge(forPreferenceKeyNamed name: String) -> Self? {
		allCases.first { $0.preferenceKey.name == name }
	}

	private var defaultColor: PreferenceColor {
		switch self {
		case .ircOperator: PreferenceColor(red: 0.632, green: 0.335, blue: 0.226)
		case .channelOwner: PreferenceColor(red: 0.726, green: 0.0, blue: 0.0)
		case .superOperator: PreferenceColor(red: 0.613, green: 0.0, blue: 0.347)
		case .normalOperator: PreferenceColor(red: 0.351, green: 0.199, blue: 0.609)
		case .halfOperator: PreferenceColor(red: 0.066, green: 0.488, blue: 0.074)
		case .voiced: PreferenceColor(red: 0.199, green: 0.480, blue: 0.609)
		}
	}

	public var preferenceKey: PreferenceKey<PreferenceColor> {
		PreferenceKey("User List Mode Badge Colors -> \(rawValue)", default: defaultColor)
	}
}

public nonisolated extension Preferences { // nonisolated: value
	/// The colour wells in the "User List" and "Server List" preference panes.
	enum Badges {
		public static let userListMode = UserListModeBadge.allCases.map(\.preferenceKey)

		/** Unregistered on purpose: with nothing stored the server-list cell uses
		 the colour its appearance defines, which changes with the window's
		 active state and so cannot be written as a fixed default. Read it with
		 `storedColor(for:)`, not `color(for:)`. */
		public static let serverListUnreadHighlight = PreferenceKey(
			"Server List Unread Message Count Badge Colors -> Highlight",
			default: PreferenceColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0),
			traits: .unregistered
		)

		static let all: [any AnyPreferenceKey] = userListMode + [serverListUnreadHighlight]
	}
}

// MARK: - Main window state

public nonisolated extension Preferences { // nonisolated: value
	/// Where the main window last was and what it was showing. Restored state,
	/// not settings, so the whole family stays out of an exported file.
	enum MainWindow {
		public static let serverListVisible = PreferenceKey(
			"Window -> Main Window -> Server List is Visible",
			default: true,
			traits: .unregistered
		)

		public static let memberListVisible = PreferenceKey(
			"Window -> Main Window -> Member List is Visible",
			default: true,
			traits: .unregistered
		)

		public static let serverListSelection = PreferenceKey(
			"Window -> Main Window -> Server List Selection",
			default: "",
			traits: .unregistered
		)

		static let all: [any AnyPreferenceKey] = [
			serverListVisible, memberListVisible, serverListSelection,
		]
	}
}
