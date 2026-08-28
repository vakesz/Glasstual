/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
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

import AppKit
import CocoaExtensions
import Combine

private nonisolated(unsafe) let preferences = TextualUserDefaults.shared()
private nonisolated(unsafe) var excludeKeywords: [String]?
private nonisolated(unsafe) var matchKeywords: [String]?
private nonisolated(unsafe) var keywordDefaultsObservation: AnyCancellable?

public nonisolated extension TextualPreferences {
	private class func bool(_ key: String) -> Bool {
		preferences.bool(forKey: key)
	}

	private class func uint(_ key: String) -> UInt {
		preferences.unsignedInteger(forKey: key)
	}

	private class func double(_ key: String) -> Double {
		preferences.double(forKey: key)
	}

	private class func string(_ key: String) -> String? {
		preferences.object(forKey: key) as? String
	}

	private class func set(_ value: Any?, _ key: String) {
		preferences.set(value, forKey: key)
	}

	private class func defaultString(_ key: String) -> String {
		guard let value = defaultPreferences()[key] as? String else {
			preconditionFailure("Missing string default for preference key: \(key)")
		}
		return value
	}

	class func defaultNicknamePrefix() -> String {
		defaultString("DefaultIdentity -> Nickname")
	}

	class func populateDefaultNickname() {
		let nickname = "\(defaultNicknamePrefix())\(randomNumber(100))"
		preferences.register(defaults: ["DefaultIdentity -> Nickname": nickname])
	}

	class func defaultNickname() -> String {
		string("DefaultIdentity -> Nickname")!
	}

	class func defaultAwayNickname()
		-> String?
	{
		string("DefaultIdentity -> AwayNickname")
	}

	class func defaultUsername() -> String {
		string("DefaultIdentity -> Username")!
	}

	class func defaultRealName() -> String {
		string("DefaultIdentity -> Realname")!
	}

	class func autojoinMaximumChannelJoins()
		-> UInt
	{
		uint("AutojoinMaximumChannelJoinCount")
	}

	class func autojoinDelayBetweenChannelJoins()
		-> TimeInterval
	{
		double("AutojoinDelayBetweenChannelJoins")
	}

	class func autojoinDelayAfterIdentification()
		-> TimeInterval
	{
		double("AutojoinDelayAfterIdentification")
	}

	class func defaultKickMessage()
		-> String
	{
		string("ChannelOperatorDefaultLocalization -> Kick Reason")!
	}

	class func irCopDefaultKillMessage()
		-> String
	{
		string("IRCopDefaultLocalizaiton -> Kill Reason")!
	}

	class func irCopDefaultGlineMessage()
		-> String
	{
		string("IRCopDefaultLocalizaiton -> G:Line Reason")!
	}

	class func irCopDefaultShunMessage()
		-> String
	{
		string("IRCopDefaultLocalizaiton -> Shun Reason")!
	}

	class func masqueradeCTCPVersion()
		-> String?
	{
		string("ApplicationCTCPVersionMasquerade")
	}

	class func channelNavigationIsServerSpecific()
		-> Bool
	{
		bool("ChannelNavigationIsServerSpecific")
	}

	class func setAwayOnScreenSleep() -> Bool {
		bool("SetAwayOnScreenSleep")
	}

	class func disconnectOnSleep() -> Bool {
		bool("AutomaticallyDisconnectForSleepMode")
	}

	class func disableSidebarTranslucency()
		-> Bool
	{
		bool("DisableSidebarTranslucency")
	}

	class func logHighlights() -> Bool {
		bool("LogHighlights")
	}

	class func clearAllConnections()
		-> Bool
	{
		bool("ApplyCommandToAllConnections -> clearall")
	}

	class func enableEchoMessageCapability() -> Bool {
		false
	}

	class func displayServerMOTD()
		-> Bool
	{
		bool("DisplayServerMessageOfTheDayOnConnect")
	}

	class func copyOnSelect() -> Bool {
		bool("CopyTextSelectionOnMouseUp")
	}

	class func replyToCTCPRequests()
		-> Bool
	{
		bool("ReplyUnignoredExternalCTCPRequests")
	}

	class func autoAddScrollbackMark()
		-> Bool
	{
		bool("AutomaticallyAddScrollbackMarker")
	}

	class func removeAllFormatting() -> Bool {
		bool("RemoveIRCTextFormatting")
	}

	class func automaticallyDetectHighlightSpam()
		-> Bool
	{
		bool("AutomaticallyDetectHighlightSpam")
	}

	class func disableNicknameColorHashing()
		-> Bool
	{
		bool("DisableRemoteNicknameColorHashing")
	}

	class func conversationTrackingIncludesUserModeSymbol()
		-> Bool
	{
		bool("ConversationTrackingIncludesUserModeSymbol")
	}

	class func rightToLeftFormatting() -> Bool {
		bool("RightToLeftTextFormatting")
	}

	class func displayDockBadge() -> Bool {
		bool("DisplayDockBadges")
	}

	class func amsgAllConnections()
		-> Bool
	{
		bool("ApplyCommandToAllConnections -> amsg")
	}

	class func awayAllConnections()
		-> Bool
	{
		bool("ApplyCommandToAllConnections -> away")
	}

	class func giveFocusOnMessageCommand()
		-> Bool
	{
		bool("FocusSelectionOnMessageCommandExecution")
	}

	class func memberListSortFavorsServerStaff()
		-> Bool
	{
		bool("MemberListSortFavorsServerStaff")
	}

	class func memberListUpdatesUserInfoPopoverOnScroll()
		-> Bool
	{
		bool("MemberListUpdatesUserInfoPopoverOnScroll")
	}

	class func memberListDisplayNoModeSymbol()
		-> Bool
	{
		bool("DisplayUserListNoModeSymbol")
	}

	class func postNotificationsWhileInFocus()
		-> Bool
	{
		bool("PostNotificationsWhileInFocus")
	}

	class func automaticallyFilterUnicodeTextSpam()
		-> Bool
	{
		bool("AutomaticallyFilterUnicodeTextSpam")
	}

	class func nickAllConnections()
		-> Bool
	{
		bool("ApplyCommandToAllConnections -> nick")
	}

	class func confirmQuit() -> Bool {
		bool("ConfirmApplicationQuit")
	}

	class func rememberServerListQueryStates()
		-> Bool
	{
		bool("ServerListRetainsQueriesBetweenRestarts")
	}

	class func rejoinOnKick() -> Bool {
		bool("RejoinChannelOnLocalKick")
	}

	class func reloadScrollbackOnLaunch()
		-> Bool
	{
		bool("ReloadScrollbackOnLaunch")
	}

	class func autoJoinOnInvite() -> Bool {
		bool("AutojoinChannelOnInvite")
	}

	class func connectOnDoubleclick()
		-> Bool
	{
		bool("ServerListDoubleClickConnectServer")
	}

	class func disconnectOnDoubleclick()
		-> Bool
	{
		bool("ServerListDoubleClickDisconnectServer")
	}

	class func joinOnDoubleclick() -> Bool {
		bool("ServerListDoubleClickJoinChannel")
	}

	class func leaveOnDoubleclick() -> Bool {
		bool("ServerListDoubleClickLeaveChannel")
	}

	class func logToDisk() -> Bool {
		bool("LogTranscript")
	}

	class func setLogToDisk(_ value: Bool) {
		set(value, "LogTranscript")
	}

	class func logToDiskIsEnabled() -> Bool {
		bool("LogTranscript") && PathInfo.transcriptFolderURL != nil
	}

	class func openBrowserInBackground()
		-> Bool
	{
		bool("OpenClickedLinksInBackgroundBrowser")
	}

	class func sendTypingNotifications() -> Bool {
		bool("SendTypingNotifications")
	}

	class func showDateChanges() -> Bool {
		bool("DisplayEventInLogView -> Date Changes")
	}

	class func setShowInlineMedia(_ value: Bool) {
		set(
			value,
			"DisplayEventInLogView -> Inline Media"
		)
	}

	class func showInlineMedia() -> Bool {
		bool("DisplayEventInLogView -> Inline Media")
	}

	class func showJoinLeave() -> Bool {
		bool("DisplayEventInLogView -> Join, Part, Quit")
	}

	class func commandReturnSendsMessageAsAction()
		-> Bool
	{
		bool("CommandReturnSendsMessageAsAction")
	}

	class func controlEnterSendsMessage()
		-> Bool
	{
		bool("ControlEnterSendsMessage")
	}

	class func displayPublicMessageCountOnDockBadge()
		-> Bool
	{
		bool("DisplayPublicMessageCountInDockBadge")
	}

	class func setHighlightCurrentNickname(_ value: Bool) {
		set(
			value,
			"TrackNicknameHighlightsOfLocalUser"
		)
	}

	class func highlightCurrentNickname()
		-> Bool
	{
		bool("TrackNicknameHighlightsOfLocalUser")
	}

	class func inputHistoryIsChannelSpecific()
		-> Bool
	{
		bool("SaveInputHistoryPerSelection")
	}

	class func swipeMinimumLength() -> CGFloat {
		double("SwipeMinimumLength")
	}

	class func trackUserAwayStatusMaximumChannelSize()
		-> UInt
	{
		uint("TrackUserAwayStatusMaximumChannelSize")
	}

	class func tabKeyAction()
		-> TXTabKeyAction
	{
		TXTabKeyAction(rawValue: uint("Keyboard -> Tab Key Action")) ?? .nicknameComplete
	}

	class func highlightMatchingMethod()
		-> TXNicknameHighlightMatchType
	{
		TXNicknameHighlightMatchType(
			rawValue: uint("NicknameHighlightMatchingType")
		) ??
			.partial
	}

	class func userDoubleClickOption()
		-> TXUserDoubleClickAction
	{
		TXUserDoubleClickAction(rawValue: uint("UserListDoubleClickAction")) ?? .whois
	}

	class func locationToSendNotices()
		-> TXNoticeSendLocation
	{
		TXNoticeSendLocation(rawValue: uint("DestinationOfNonserverNotices")) ??
			.serverConsole
	}

	class func setLocationToSendNotices(_ value: TXNoticeSendLocation) {
		preferences.setUnsignedInteger(
			value.rawValue,
			forKey: "DestinationOfNonserverNotices"
		)
	}

	class func commandWKeyAction()
		-> TXCommandWKeyAction
	{
		TXCommandWKeyAction(rawValue: uint("Keyboard -> Command+W Key Action")) ??
			.closeWindow
	}

	class func banFormat()
		-> TXHostmaskBanFormat
	{
		TXHostmaskBanFormat(rawValue: uint("DefaultBanCommandHostmaskFormat")) ?? TXHostmaskBanFormat(rawValue: 0)!
	}

	class func mainTextViewFontSize()
		-> TVCMainWindowTextViewFontSize
	{
		TVCMainWindowTextViewFontSize(rawValue: uint("Main Input Text Field -> Font Size")) ?? .normal
	}

	class func focusMainTextViewOnSelectionChange()
		-> Bool
	{
		bool("Main Input Text Field -> Focus When Changing Views")
	}

	class func preferModernCiphers() -> Bool {
		bool("PreferModernCiphers")
	}

	class func appNapEnabled() -> Bool {
		!UserDefaults.standard
			.bool(forKey: "NSAppSleepDisabled")
	}

	class func setAppNapEnabled(_ value: Bool) {
		UserDefaults.standard.set(
			!value,
			forKey: "NSAppSleepDisabled"
		)
	}

	class func setDeveloperModeEnabled(_ value: Bool) {
		set(
			value,
			"GlasstualDeveloperEnvironment"
		)
	}

	class func developerModeEnabled() -> Bool {
		bool("GlasstualDeveloperEnvironment")
	}

	class func setOnboardingCompleted(_ value: Bool) {
		set(
			value,
			"Onboarding -> Completed"
		)
	}

	class func onboardingCompleted() -> Bool {
		bool("Onboarding -> Completed")
	}

	class func setAppearance(_ value: TXPreferredAppearance) {
		preferences.setUnsignedInteger(
			value.rawValue,
			forKey: "Appearance"
		)
	}

	class func appearance()
		-> TXPreferredAppearance
	{
		TXPreferredAppearance(rawValue: uint("Appearance")) ?? .inherited
	}

	class func themeNameDefault()
		-> String
	{
		defaultString(TPCPreferencesThemeNameDefaultsKey)
	}

	class func themeName() -> String {
		string(TPCPreferencesThemeNameDefaultsKey)!
	}

	class func setThemeName(_ value: String) {
		set(
			value,
			TPCPreferencesThemeNameDefaultsKey
		); preferences.removeObject(forKey: TPCPreferencesThemeNameMissingLocallyDefaultsKey)
	}

	class func setThemeNameWithExistenceCheck(_ value: String) {
		let themeExists: Bool = if Thread.isMainThread {
			MainActor.assumeIsolated {
				SharedApplication.sharedThemeController().themeExists(value)
			}
		} else {
			DispatchQueue.main.sync {
				MainActor.assumeIsolated {
					SharedApplication.sharedThemeController().themeExists(value)
				}
			}
		}

		if themeExists {
			setThemeName(value)
		} else {
			set(
				true,
				TPCPreferencesThemeNameMissingLocallyDefaultsKey
			)
		}
	}

	class func themeChannelViewFontNameDefault()
		-> String
	{
		defaultString(TPCPreferencesThemeFontNameDefaultsKey)
	}

	class func themeChannelViewFontName()
		-> String
	{
		string(TPCPreferencesThemeFontNameDefaultsKey)!
	}

	class func setThemeChannelViewFontName(_ value: String) {
		set(
			value,
			TPCPreferencesThemeFontNameDefaultsKey
		); preferences.removeObject(forKey: TPCPreferencesThemeFontNameMissingLocallyDefaultsKey)
	}

	class func setThemeChannelViewFontNameWithExistenceCheck(
		_ value: String
	) {
		if NSFont.textual_fontIsAvailable(value) {
			setThemeChannelViewFontName(value)
		} else {
			set(
				true,
				TPCPreferencesThemeFontNameMissingLocallyDefaultsKey
			)
		}
	}

	class func themeChannelViewFontSize()
		-> CGFloat
	{
		double(TPCPreferencesThemeFontSizeDefaultsKey)
	}

	class func setThemeChannelViewFontSize(_ value: CGFloat) {
		preferences.set(
			value,
			forKey: TPCPreferencesThemeFontSizeDefaultsKey
		)
	}

	class func themeChannelViewFont() -> NSFont? {
		NSFont(
			name: themeChannelViewFontName(),
			size: themeChannelViewFontSize()
		)
	}

	class func themeChannelViewFontPreferenceUserConfigurable()
		-> Bool
	{
		bool("Theme -> Channel Font Preference Enabled")
	}

	class func setThemeChannelViewFontPreferenceUserConfigurable(_ value: Bool) {
		preferences.registerDefault(
			value as NSNumber,
			forKey: "Theme -> Channel Font Preference Enabled"
		)
	}

	class func themeNicknameFormatDefault()
		-> String
	{
		defaultString("Theme -> Nickname Format")
	}

	class func themeNicknameFormat() -> String {
		string("Theme -> Nickname Format")!
	}

	class func themeNicknameFormatPreferenceUserConfigurable(
	)
		-> Bool
	{
		bool("Theme -> Nickname Format Preference Enabled")
	}

	class func setThemeNicknameFormatPreferenceUserConfigurable(_ value: Bool) {
		preferences.registerDefault(
			value as NSNumber,
			forKey: "Theme -> Nickname Format Preference Enabled"
		)
	}

	class func themeTimestampFormatDefault()
		-> String
	{
		defaultString("Theme -> Timestamp Format")
	}

	class func themeTimestampFormat()
		-> String
	{
		string("Theme -> Timestamp Format")!
	}

	class func themeTimestampFormatPreferenceUserConfigurable()
		-> Bool
	{
		bool("Theme -> Timestamp Format Preference Enabled")
	}

	class func setThemeTimestampFormatPreferenceUserConfigurable(_ value: Bool) {
		preferences.registerDefault(
			value as NSNumber,
			forKey: "Theme -> Timestamp Format Preference Enabled"
		)
	}

	/** The rules are interpolated into a `<style>` element in the log view, so
	 the one sequence that would escape that element is neutralised here. */
	class func themeUserStyleSheetRules()
		-> String?
	{
		LogViewContentPolicy.sanitizedStyleSheetText(string("Theme -> User Style Sheet Rules"))
	}

	class func setThemeUserStyleSheetRules(_ value: String?) {
		set(
			value,
			"Theme -> User Style Sheet Rules"
		)
	}

	class func automaticallyReloadCustomThemesWhenTheyChange(
	)
		-> Bool
	{
		bool("AutomaticallyReloadCustomThemesWhenTheyChange")
	}

	class func webKit2ProcessPoolSizeLimited()
		-> Bool
	{
		bool("WebViewProcessPoolSizeIsLimited")
	}

	class func webKit2PreviewLinks() -> Bool {
		bool("WebViewPreviewLinks")
	}

	class func themeChannelViewUsesCustomScrollers()
		-> Bool
	{
		!bool("WebViewDoNotUsesCustomScrollers")
	}

	class func channelViewArrangement()
		-> TXChannelViewArrangement
	{
		TXChannelViewArrangement(rawValue: uint("ChannelViewArrangement")) ?? .horizontal
	}

	class func tabCompletionSuffix()
		-> String?
	{
		string("Keyboard -> Tab Key Completion Suffix")
	}

	class func setTabCompletionSuffix(_ value: String) {
		set(
			value,
			"Keyboard -> Tab Key Completion Suffix"
		)
	}

	class func tabCompletionDoNotAppendWhitespace()
		-> Bool
	{
		bool("Tab Completion -> Do Not Use Whitespace for Missing Completion Suffix")
	}

	class func tabCompletionCutForwardToFirstWhitespace()
		-> Bool
	{
		bool("Tab Completion -> Completion Suffix Cut Forward Until Space")
	}

	class func fileTransferRequestReplyAction()
		-> TXFileTransferRequestReply
	{
		TXFileTransferRequestReply(rawValue: uint("File Transfers -> File Transfer Request Reply Action")) ?? .ignore
	}

	class func fileTransferIPAddressDetectionMethod()
		-> TXFileTransferIPAddressMethodDetection
	{
		TXFileTransferIPAddressMethodDetection(
			rawValue: uint("File Transfers -> File Transfer IP Address Detection Method")
		) ??
			.routerOnly
	}

	class func fileTransferRequestsAreReversed()
		-> Bool
	{
		bool("File Transfers -> File Transfer Requests Use Reverse DCC")
	}

	class func fileTransfersPreventIdleSystemSleep()
		-> Bool
	{
		bool("File Transfers -> Idle System Sleep Prevented During File Transfer")
	}

	class func fileTransferPortRangeStart() -> UInt16 {
		preferences
			.unsignedShort(forKey: "File Transfers -> File Transfer Port Range Start")
	}

	class func setFileTransferPortRangeStart(_ value: UInt16) {
		preferences.setUnsignedShort(
			value,
			forKey: "File Transfers -> File Transfer Port Range Start"
		)
	}

	class func fileTransferPortRangeEnd() -> UInt16 {
		preferences
			.unsignedShort(forKey: "File Transfers -> File Transfer Port Range End")
	}

	class func setFileTransferPortRangeEnd(_ value: UInt16) {
		preferences.setUnsignedShort(
			value,
			forKey: "File Transfers -> File Transfer Port Range End"
		)
	}

	class func fileTransferManuallyEnteredIPAddress()
		-> String?
	{
		string("File Transfers -> File Transfer Manually Entered IP Address")
	}

	class func fileTransferIPAddressInterfaceName()
		-> String?
	{
		string("File Transfers -> File Transfer IP Address Interface Name")
	}

	class func scrollbackSaveLimit() -> UInt {
		uint("ScrollbackMaximumSavedLineCount")
	}

	class func setScrollbackSaveLimit(_ value: UInt) {
		preferences.setUnsignedInteger(
			value,
			forKey: "ScrollbackMaximumSavedLineCount"
		)
	}

	class func scrollbackVisibleLimit()
		-> UInt
	{
		uint("ScrollbackMaximumVisibleLineCount")
	}

	class func setScrollbackVisibleLimit(_ value: UInt) {
		preferences.setUnsignedInteger(
			value,
			forKey: "ScrollbackMaximumVisibleLineCount"
		)
	}

	class func soundIsMuted() -> Bool {
		bool("Notification Sound Is Muted")
	}

	class func setSoundIsMuted(_ value: Bool) {
		set(value, "Notification Sound Is Muted")
	}

	class func key(for event: TXNotificationType, category: String) -> String? {
		let prefix: String

		switch event {
		case .addressBookMatch: prefix = "NotificationType -> Address Book Match -> "
		case .channelMessage: prefix = "NotificationType -> Public Message -> "
		case .channelNotice: prefix = "NotificationType -> Public Notice -> "
		case .connect: prefix = "NotificationType -> Connected -> "
		case .disconnect: prefix = "NotificationType -> Disconnected -> "
		case .highlight: prefix = "NotificationType -> Highlight -> "
		case .invite: prefix = "NotificationType -> Channel Invitation -> "
		case .kick: prefix = "NotificationType -> Kicked from Channel -> "
		case .newPrivateMessage: prefix = "NotificationType -> Private Message (New) -> "
		case .privateMessage: prefix = "NotificationType -> Private Message -> "
		case .privateNotice: prefix = "NotificationType -> Private Notice -> "
		case .fileTransferSendSuccessful: prefix = "NotificationType -> Successful File Transfer (Sending) -> "
		case .fileTransferReceiveSuccessful: prefix = "NotificationType -> Successful File Transfer (Receiving) -> "
		case .fileTransferSendFailed: prefix = "NotificationType -> Failed File Transfer (Sending) -> "
		case .fileTransferReceiveFailed: prefix = "NotificationType -> Failed File Transfer (Receiving) -> "
		case .fileTransferReceiveRequested: prefix = "NotificationType -> File Transfer Request -> "
		case .userJoined: prefix = "NotificationType -> User Joined -> "
		case .userParted: prefix = "NotificationType -> User Parted -> "
		case .userDisconnected: prefix = "NotificationType -> User Disconnected -> "
		default: return nil
		}

		return prefix + category
	}

	class func sound(for event: TXNotificationType) -> String? {
		key(
			for: event,
			category: "Sound"
		).flatMap(string)
	}

	class func setSound(_ value: String?, for event: TXNotificationType) {
		if let key = key(
			for: event,
			category: "Sound"
		) {
			set(value, key)
		}
	}

	class func notificationEnabled(for event: TXNotificationType)
		-> Bool
	{
		key(
			for: event,
			category: "Enabled"
		).map(bool) ?? false
	}

	class func setNotificationEnabled(
		_ value: Bool,
		for event: TXNotificationType
	) {
		if let key = key(for: event, category: "Enabled") {
			set(value, key)
		}
	}

	class func disabledWhileAway(for event: TXNotificationType)
		-> Bool
	{
		key(
			for: event,
			category: "Disable While Away"
		).map(bool) ?? false
	}

	class func setDisabledWhileAway(
		_ value: Bool,
		for event: TXNotificationType
	) {
		if let key = key(for: event, category: "Disable While Away") {
			set(value, key)
		}
	}

	class func bounceDockIcon(for event: TXNotificationType) -> Bool {
		key(
			for: event,
			category: "Bounce Dock Icon"
		).map(bool) ?? false
	}

	class func setBounceDockIcon(
		_ value: Bool,
		for event: TXNotificationType
	) {
		if let key = key(
			for: event,
			category: "Bounce Dock Icon"
		) {
			set(value, key)
		}
	}

	class func bounceDockIconRepeatedly(for event: TXNotificationType)
		-> Bool
	{
		key(
			for: event,
			category: "Bounce Dock Icon Repeatedly"
		).map(bool) ?? false
	}

	class func setBounceDockIconRepeatedly(
		_ value: Bool,
		for event: TXNotificationType
	) {
		if let key = key(for: event, category: "Bounce Dock Icon Repeatedly") {
			set(value, key)
		}
	}

	class func speak(_ event: TXNotificationType) -> Bool {
		key(
			for: event,
			category: "Speak"
		).map(bool) ?? false
	}

	class func setEventIsSpoken(_ value: Bool, for event: TXNotificationType) {
		if let key = key(
			for: event,
			category: "Speak"
		) {
			set(value, key)
		}
	}

	class func onlySpeakEventsForSelection()
		-> Bool
	{
		bool("OnlySpeakNotificationsForSelection")
	}

	class func setOnlySpeakEventsForSelection(_ value: Bool) {
		set(
			value,
			"OnlySpeakNotificationsForSelection"
		)
	}

	class func channelMessageSpeakChannelName() -> Bool {
		bool(key(
			for: .channelMessage,
			category: "Speak Channel Name"
		)!)
	}

	class func setChannelMessageSpeakChannelName(_ value: Bool) {
		set(
			value,
			key(for: .channelMessage, category: "Speak Channel Name")!
		)
	}

	class func channelMessageSpeakNickname() -> Bool {
		bool(key(
			for: .channelMessage,
			category: "Speak Nickname"
		)!)
	}

	class func setChannelMessageSpeakNickname(_ value: Bool) {
		set(
			value,
			key(for: .channelMessage, category: "Speak Nickname")!
		)
	}

	class func clientList() -> [[String: Any]]? {
		preferences
			.object(forKey: IRCWorldClientListDefaultsKey) as? [[String: Any]]
	}

	class func setClientList(_ value: [[String: Any]]?) {
		set(
			value,
			IRCWorldClientListDefaultsKey
		)
	}

	private class func loadKeywords(for key: String) -> [String] {
		(preferences.array(forKey: key) as? [[String: Any]] ?? []).compactMap { dictionary in
			guard let value = dictionary["string"] as? String, value.isEmpty == false else { return nil }
			return value
		}
	}

	private class func reloadHighlightKeywords() {
		matchKeywords = loadKeywords(for: "Highlight List -> Primary Matches")
		excludeKeywords = loadKeywords(for: "Highlight List -> Excluded Matches")
	}

	class func loadExcludeKeywords() {
		excludeKeywords = loadKeywords(for: "Highlight List -> Excluded Matches")
	}

	class func loadMatchKeywords() {
		matchKeywords = loadKeywords(for: "Highlight List -> Primary Matches")
	}

	private class func cleanKeywords(for key: String) {
		let strings = loadKeywords(for: key).sorted { $0.caseInsensitiveCompare($1) == .orderedAscending }
		set(strings.map { ["string": $0] }, key)
	}

	class func cleanUpKeywords(_ key: String) {
		cleanKeywords(for: key)
	}

	class func cleanUpHighlightKeywords() {
		cleanKeywords(for: "Highlight List -> Primary Matches")
		cleanKeywords(for: "Highlight List -> Excluded Matches")
	}

	class func highlightMatchKeywords() -> [String]? {
		matchKeywords
	}

	class func highlightExcludeKeywords() -> [String]? {
		excludeKeywords
	}

	class func registerWebKit2DynamicDefaults() {
		UserDefaults.standard.set(false, forKey: "__WebInspectorPageGroupLevel1__.WebKit2InspectorStartsAttached")
	}

	class func registerPreferencesDictionaryVersion() {
		guard uint("TPCPreferencesDictionaryVersion") < TPCPreferencesDictionaryVersion else { return }
		preferences.setUnsignedInteger(TPCPreferencesDictionaryVersion, forKey: "TPCPreferencesDictionaryVersion")
	}

	class func defaultPreferences() -> [String: Any] {
		preferences
			.volatileDomain(forName: UserDefaults.registrationDomain)
	}

	class func registerDynamicDefaults() {
		populateDefaultNickname()
		registerWebKit2DynamicDefaults()
		registerPreferencesDictionaryVersion()
	}

	class func registerDefaults() {
		let local = ResourceManager.dictionary(
			fromResources: "RegisteredUserDefaults",
			inDirectory: "Preferences"
		) ?? [:]
		UserDefaults.standard.register(defaults: local)
		let container = ResourceManager.dictionary(
			fromResources: "RegisteredUserDefaultsInContainer",
			inDirectory: "Preferences"
		) ?? [:]
		preferences.register(defaults: container)
		registerDynamicDefaults()
	}

	class func initPreferences() {
		ApplicationInfo.incrementApplicationRunCount()
		registerDefaults()
		PathInfo.startUsingTranscriptFolderURL()
		keywordDefaultsObservation = NotificationCenter.default.publisher(
			for: UserDefaults.didChangeNotification,
			object: preferences
		)
		.sink { _ in
			loadMatchKeywords()
			loadExcludeKeywords()
		}
		reloadHighlightKeywords()
	}

	class func textFieldAutomaticSpellCheck()
		-> Bool
	{
		bool("TextFieldAutomaticSpellCheck")
	}

	class func setTextFieldAutomaticSpellCheck(_ value: Bool) {
		set(
			value,
			"TextFieldAutomaticSpellCheck"
		)
	}

	class func textFieldAutomaticGrammarCheck()
		-> Bool
	{
		bool("TextFieldAutomaticGrammarCheck")
	}

	class func setTextFieldAutomaticGrammarCheck(_ value: Bool) {
		set(
			value,
			"TextFieldAutomaticGrammarCheck"
		)
	}

	class func textFieldAutomaticSpellCorrection()
		-> Bool
	{
		bool("TextFieldAutomaticSpellCorrection")
	}

	class func setTextFieldAutomaticSpellCorrection(_ value: Bool) {
		set(
			value,
			"TextFieldAutomaticSpellCorrection"
		)
	}

	class func textFieldSmartCopyPaste() -> Bool {
		bool("TextFieldSmartCopyPaste")
	}

	class func setTextFieldSmartCopyPaste(_ value: Bool) {
		set(
			value,
			"TextFieldSmartCopyPaste"
		)
	}

	class func textFieldSmartQuotes() -> Bool {
		bool("TextFieldSmartQuotes")
	}

	class func setTextFieldSmartQuotes(_ value: Bool) {
		set(
			value,
			"TextFieldSmartQuotes"
		)
	}

	class func textFieldSmartDashes() -> Bool {
		bool("TextFieldSmartDashes")
	}

	class func setTextFieldSmartDashes(_ value: Bool) {
		set(
			value,
			"TextFieldSmartDashes"
		)
	}

	class func textFieldSmartLinks() -> Bool {
		bool("TextFieldSmartLinks")
	}

	class func setTextFieldSmartLinks(_ value: Bool) {
		set(
			value,
			"TextFieldSmartLinks"
		)
	}

	class func textFieldDataDetectors() -> Bool {
		bool("TextFieldDataDetectors")
	}

	class func setTextFieldDataDetectors(_ value: Bool) {
		set(
			value,
			"TextFieldDataDetectors"
		)
	}

	class func textFieldTextReplacement()
		-> Bool
	{
		bool("TextFieldTextReplacement")
	}

	class func setTextFieldTextReplacement(_ value: Bool) {
		set(
			value,
			"TextFieldTextReplacement"
		)
	}
}
