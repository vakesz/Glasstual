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

private nonisolated(unsafe) let preferences = TPCPreferencesUserDefaults.shared()
private nonisolated(unsafe) var excludeKeywords: [String]?
private nonisolated(unsafe) var matchKeywords: [String]?
private nonisolated(unsafe) var keywordObserver: KeywordDefaultsObserver?

private final class KeywordDefaultsObserver: NSObject {
	override func observeValue(
		forKeyPath keyPath: String?,
		of object: Any?,
		change: [NSKeyValueChangeKey: Any]?,
		context: UnsafeMutableRawPointer?
	) {
		switch keyPath {
		case "Highlight List -> Primary Matches":
			TPCPreferences.local_loadMatchKeywords()
		case "Highlight List -> Excluded Matches":
			TPCPreferences.local_loadExcludeKeywords()
		default:
			super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
		}
	}
}

public extension TPCPreferences {
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

	@objc(_defaultNicknamePrefix)
	class func local_defaultNicknamePrefix() -> String {
		local_defaultPreferences()["DefaultIdentity -> Nickname"] as! String
	}

	@objc(_populateDefaultNickname)
	class func local_populateDefaultNickname() {
		let nickname = "\(local_defaultNicknamePrefix())\(randomNumber(100))"
		preferences.register(defaults: ["DefaultIdentity -> Nickname": nickname])
	}

	@objc(defaultNickname) class func local_defaultNickname() -> String {
		string("DefaultIdentity -> Nickname")!
	}

	@objc(defaultAwayNickname) class func local_defaultAwayNickname()
		-> String?
	{
		string("DefaultIdentity -> AwayNickname")
	}

	@objc(defaultUsername) class func local_defaultUsername() -> String {
		string("DefaultIdentity -> Username")!
	}

	@objc(defaultRealName) class func local_defaultRealName() -> String {
		string("DefaultIdentity -> Realname")!
	}

	@objc(autojoinMaximumChannelJoins) class func local_autojoinMaximumChannelJoins()
		-> UInt
	{
		uint("AutojoinMaximumChannelJoinCount")
	}

	@objc(autojoinDelayBetweenChannelJoins) class func local_autojoinDelayBetweenChannelJoins()
		-> TimeInterval
	{
		double("AutojoinDelayBetweenChannelJoins")
	}

	@objc(autojoinDelayAfterIdentification) class func local_autojoinDelayAfterIdentification()
		-> TimeInterval
	{
		double("AutojoinDelayAfterIdentification")
	}

	@objc(defaultKickMessage) class func local_defaultKickMessage()
		-> String
	{
		string("ChannelOperatorDefaultLocalization -> Kick Reason")!
	}

	@objc(IRCopDefaultKillMessage) class func local_IRCopDefaultKillMessage()
		-> String
	{
		string("IRCopDefaultLocalizaiton -> Kill Reason")!
	}

	@objc(IRCopDefaultGlineMessage) class func local_IRCopDefaultGlineMessage()
		-> String
	{
		string("IRCopDefaultLocalizaiton -> G:Line Reason")!
	}

	@objc(IRCopDefaultShunMessage) class func local_IRCopDefaultShunMessage()
		-> String
	{
		string("IRCopDefaultLocalizaiton -> Shun Reason")!
	}

	@objc(masqueradeCTCPVersion) class func local_masqueradeCTCPVersion()
		-> String?
	{
		string("ApplicationCTCPVersionMasquerade")
	}

	@objc(channelNavigationIsServerSpecific) class func local_channelNavigationIsServerSpecific()
		-> Bool
	{
		bool("ChannelNavigationIsServerSpecific")
	}

	@objc(setAwayOnScreenSleep) class func local_setAwayOnScreenSleep() -> Bool {
		bool("SetAwayOnScreenSleep")
	}

	@objc(disconnectOnSleep) class func local_disconnectOnSleep() -> Bool {
		bool("AutomaticallyDisconnectForSleepMode")
	}

	@objc(disableSidebarTranslucency) class func local_disableSidebarTranslucency()
		-> Bool
	{
		bool("DisableSidebarTranslucency")
	}

	@objc(logHighlights) class func local_logHighlights() -> Bool {
		bool("LogHighlights")
	}

	@objc(clearAllConnections) class func local_clearAllConnections()
		-> Bool
	{
		bool("ApplyCommandToAllConnections -> clearall")
	}

	@objc(enableEchoMessageCapability) class func local_enableEchoMessageCapability() -> Bool {
		false
	}

	@objc(displayServerMOTD) class func local_displayServerMOTD()
		-> Bool
	{
		bool("DisplayServerMessageOfTheDayOnConnect")
	}

	@objc(copyOnSelect) class func local_copyOnSelect() -> Bool {
		bool("CopyTextSelectionOnMouseUp")
	}

	@objc(replyToCTCPRequests) class func local_replyToCTCPRequests()
		-> Bool
	{
		bool("ReplyUnignoredExternalCTCPRequests")
	}

	@objc(autoAddScrollbackMark) class func local_autoAddScrollbackMark()
		-> Bool
	{
		bool("AutomaticallyAddScrollbackMarker")
	}

	@objc(removeAllFormatting) class func local_removeAllFormatting() -> Bool {
		bool("RemoveIRCTextFormatting")
	}

	@objc(automaticallyDetectHighlightSpam) class func local_automaticallyDetectHighlightSpam()
		-> Bool
	{
		bool("AutomaticallyDetectHighlightSpam")
	}

	@objc(disableNicknameColorHashing) class func local_disableNicknameColorHashing()
		-> Bool
	{
		bool("DisableRemoteNicknameColorHashing")
	}

	@objc(conversationTrackingIncludesUserModeSymbol) class func local_conversationTrackingIncludesUserModeSymbol()
		-> Bool
	{
		bool("ConversationTrackingIncludesUserModeSymbol")
	}

	@objc(rightToLeftFormatting) class func local_rightToLeftFormatting() -> Bool {
		bool("RightToLeftTextFormatting")
	}

	@objc(displayDockBadge) class func local_displayDockBadge() -> Bool {
		bool("DisplayDockBadges")
	}

	@objc(amsgAllConnections) class func local_amsgAllConnections()
		-> Bool
	{
		bool("ApplyCommandToAllConnections -> amsg")
	}

	@objc(awayAllConnections) class func local_awayAllConnections()
		-> Bool
	{
		bool("ApplyCommandToAllConnections -> away")
	}

	@objc(giveFocusOnMessageCommand) class func local_giveFocusOnMessageCommand()
		-> Bool
	{
		bool("FocusSelectionOnMessageCommandExecution")
	}

	@objc(memberListSortFavorsServerStaff) class func local_memberListSortFavorsServerStaff()
		-> Bool
	{
		bool("MemberListSortFavorsServerStaff")
	}

	@objc(memberListUpdatesUserInfoPopoverOnScroll) class func local_memberListUpdatesUserInfoPopoverOnScroll()
		-> Bool
	{
		bool("MemberListUpdatesUserInfoPopoverOnScroll")
	}

	@objc(memberListDisplayNoModeSymbol) class func local_memberListDisplayNoModeSymbol()
		-> Bool
	{
		bool("DisplayUserListNoModeSymbol")
	}

	@objc(postNotificationsWhileInFocus) class func local_postNotificationsWhileInFocus()
		-> Bool
	{
		bool("PostNotificationsWhileInFocus")
	}

	@objc(automaticallyFilterUnicodeTextSpam) class func local_automaticallyFilterUnicodeTextSpam()
		-> Bool
	{
		bool("AutomaticallyFilterUnicodeTextSpam")
	}

	@objc(nickAllConnections) class func local_nickAllConnections()
		-> Bool
	{
		bool("ApplyCommandToAllConnections -> nick")
	}

	@objc(confirmQuit) class func local_confirmQuit() -> Bool {
		bool("ConfirmApplicationQuit")
	}

	@objc(rememberServerListQueryStates) class func local_rememberServerListQueryStates()
		-> Bool
	{
		bool("ServerListRetainsQueriesBetweenRestarts")
	}

	@objc(rejoinOnKick) class func local_rejoinOnKick() -> Bool {
		bool("RejoinChannelOnLocalKick")
	}

	@objc(reloadScrollbackOnLaunch) class func local_reloadScrollbackOnLaunch()
		-> Bool
	{
		bool("ReloadScrollbackOnLaunch")
	}

	@objc(autoJoinOnInvite) class func local_autoJoinOnInvite() -> Bool {
		bool("AutojoinChannelOnInvite")
	}

	@objc(connectOnDoubleclick) class func local_connectOnDoubleclick()
		-> Bool
	{
		bool("ServerListDoubleClickConnectServer")
	}

	@objc(disconnectOnDoubleclick) class func local_disconnectOnDoubleclick()
		-> Bool
	{
		bool("ServerListDoubleClickDisconnectServer")
	}

	@objc(joinOnDoubleclick) class func local_joinOnDoubleclick() -> Bool {
		bool("ServerListDoubleClickJoinChannel")
	}

	@objc(leaveOnDoubleclick) class func local_leaveOnDoubleclick() -> Bool {
		bool("ServerListDoubleClickLeaveChannel")
	}

	@objc(logToDisk) class func local_logToDisk() -> Bool {
		bool("LogTranscript")
	}

	@objc(setLogToDisk:) class func local_setLogToDisk(_ value: Bool) {
		set(value, "LogTranscript")
	}

	@objc(logToDiskIsEnabled) class func local_logToDiskIsEnabled() -> Bool {
		bool("LogTranscript") && PathInfo.transcriptFolderURL != nil
	}

	@objc(openBrowserInBackground) class func local_openBrowserInBackground()
		-> Bool
	{
		bool("OpenClickedLinksInBackgroundBrowser")
	}

	@objc(sendTypingNotifications) class func local_sendTypingNotifications() -> Bool {
		bool("SendTypingNotifications")
	}

	@objc(showDateChanges) class func local_showDateChanges() -> Bool {
		bool("DisplayEventInLogView -> Date Changes")
	}

	@objc(setShowInlineMedia:) class func local_setShowInlineMedia(_ value: Bool) {
		set(
			value,
			"DisplayEventInLogView -> Inline Media"
		)
	}

	@objc(showInlineMedia) class func local_showInlineMedia() -> Bool {
		bool("DisplayEventInLogView -> Inline Media")
	}

	@objc(showJoinLeave) class func local_showJoinLeave() -> Bool {
		bool("DisplayEventInLogView -> Join, Part, Quit")
	}

	@objc(commandReturnSendsMessageAsAction) class func local_commandReturnSendsMessageAsAction()
		-> Bool
	{
		bool("CommandReturnSendsMessageAsAction")
	}

	@objc(controlEnterSendsMessage) class func local_controlEnterSendsMessage()
		-> Bool
	{
		bool("ControlEnterSendsMessage")
	}

	@objc(displayPublicMessageCountOnDockBadge) class func local_displayPublicMessageCountOnDockBadge()
		-> Bool
	{
		bool("DisplayPublicMessageCountInDockBadge")
	}

	@objc(setHighlightCurrentNickname:) class func local_setHighlightCurrentNickname(_ value: Bool) {
		set(
			value,
			"TrackNicknameHighlightsOfLocalUser"
		)
	}

	@objc(highlightCurrentNickname) class func local_highlightCurrentNickname()
		-> Bool
	{
		bool("TrackNicknameHighlightsOfLocalUser")
	}

	@objc(inputHistoryIsChannelSpecific) class func local_inputHistoryIsChannelSpecific()
		-> Bool
	{
		bool("SaveInputHistoryPerSelection")
	}

	@objc(swipeMinimumLength) class func local_swipeMinimumLength() -> CGFloat {
		double("SwipeMinimumLength")
	}

	@objc(trackUserAwayStatusMaximumChannelSize) class func local_trackUserAwayStatusMaximumChannelSize()
		-> UInt
	{
		uint("TrackUserAwayStatusMaximumChannelSize")
	}

	@objc(tabKeyAction) class func local_tabKeyAction()
		-> TXTabKeyAction
	{
		TXTabKeyAction(rawValue: uint("Keyboard -> Tab Key Action")) ?? .nicknameComplete
	}

	@objc(highlightMatchingMethod) class func local_highlightMatchingMethod()
		-> TXNicknameHighlightMatchType
	{
		TXNicknameHighlightMatchType(
			rawValue: uint("NicknameHighlightMatchingType")
		) ??
			.partial
	}

	@objc(userDoubleClickOption) class func local_userDoubleClickOption()
		-> TXUserDoubleClickAction
	{
		TXUserDoubleClickAction(rawValue: uint("UserListDoubleClickAction")) ?? .whois
	}

	@objc(locationToSendNotices) class func local_locationToSendNotices()
		-> TXNoticeSendLocation
	{
		TXNoticeSendLocation(rawValue: uint("DestinationOfNonserverNotices")) ??
			.serverConsole
	}

	@objc(setLocationToSendNotices:) class func local_setLocationToSendNotices(_ value: TXNoticeSendLocation) {
		preferences.setUnsignedInteger(
			value.rawValue,
			forKey: "DestinationOfNonserverNotices"
		)
	}

	@objc(commandWKeyAction) class func local_commandWKeyAction()
		-> TXCommandWKeyAction
	{
		TXCommandWKeyAction(rawValue: uint("Keyboard -> Command+W Key Action")) ??
			.closeWindow
	}

	@objc(banFormat) class func local_banFormat()
		-> TXHostmaskBanFormat
	{
		TXHostmaskBanFormat(rawValue: uint("DefaultBanCommandHostmaskFormat")) ?? TXHostmaskBanFormat(rawValue: 0)!
	}

	@objc(mainTextViewFontSize) class func local_mainTextViewFontSize()
		-> TVCMainWindowTextViewFontSize
	{
		TVCMainWindowTextViewFontSize(rawValue: uint("Main Input Text Field -> Font Size")) ?? .normal
	}

	@objc(focusMainTextViewOnSelectionChange) class func local_focusMainTextViewOnSelectionChange()
		-> Bool
	{
		bool("Main Input Text Field -> Focus When Changing Views")
	}

	@objc(preferModernCiphers) class func local_preferModernCiphers() -> Bool {
		bool("PreferModernCiphers")
	}

	@objc(appNapEnabled) class func local_appNapEnabled() -> Bool {
		!UserDefaults.standard
			.bool(forKey: "NSAppSleepDisabled")
	}

	@objc(setAppNapEnabled:) class func local_setAppNapEnabled(_ value: Bool) {
		UserDefaults.standard.set(
			!value,
			forKey: "NSAppSleepDisabled"
		)
	}

	@objc(setDeveloperModeEnabled:) class func local_setDeveloperModeEnabled(_ value: Bool) {
		set(
			value,
			"GlasstualDeveloperEnvironment"
		)
	}

	@objc(developerModeEnabled) class func local_developerModeEnabled() -> Bool {
		bool("GlasstualDeveloperEnvironment")
	}

	@objc(setOnboardingCompleted:) class func local_setOnboardingCompleted(_ value: Bool) {
		set(
			value,
			"Onboarding -> Completed"
		)
	}

	@objc(onboardingCompleted) class func local_onboardingCompleted() -> Bool {
		bool("Onboarding -> Completed")
	}

	@objc(setAppearance:) class func local_setAppearance(_ value: TXPreferredAppearance) {
		preferences.setUnsignedInteger(
			value.rawValue,
			forKey: "Appearance"
		)
	}

	@objc(appearance) class func local_appearance()
		-> TXPreferredAppearance
	{
		TXPreferredAppearance(rawValue: uint("Appearance")) ?? .inherited
	}

	@objc(themeNameDefault) class func local_themeNameDefault()
		-> String
	{
		local_defaultPreferences()[TPCPreferencesThemeNameDefaultsKey] as! String
	}

	@objc(themeName) class func local_themeName() -> String {
		string(TPCPreferencesThemeNameDefaultsKey)!
	}

	@objc(setThemeName:) class func local_setThemeName(_ value: String) {
		set(
			value,
			TPCPreferencesThemeNameDefaultsKey
		); preferences.removeObject(forKey: TPCPreferencesThemeNameMissingLocallyDefaultsKey)
	}

	@objc(setThemeNameWithExistenceCheck:) class func local_setThemeNameWithExistenceCheck(_ value: String) {
		let themeExists: Bool = if Thread.isMainThread {
			MainActor.assumeIsolated {
				TXSharedApplication.sharedThemeController().themeExists(value)
			}
		} else {
			DispatchQueue.main.sync {
				MainActor.assumeIsolated {
					TXSharedApplication.sharedThemeController().themeExists(value)
				}
			}
		}

		if themeExists {
			local_setThemeName(value)
		} else {
			set(
				true,
				TPCPreferencesThemeNameMissingLocallyDefaultsKey
			)
		}
	}

	@objc(themeChannelViewFontNameDefault) class func local_themeChannelViewFontNameDefault()
		-> String
	{
		local_defaultPreferences()[TPCPreferencesThemeFontNameDefaultsKey] as! String
	}

	@objc(themeChannelViewFontName) class func local_themeChannelViewFontName()
		-> String
	{
		string(TPCPreferencesThemeFontNameDefaultsKey)!
	}

	@objc(setThemeChannelViewFontName:) class func local_setThemeChannelViewFontName(_ value: String) {
		set(
			value,
			TPCPreferencesThemeFontNameDefaultsKey
		); preferences.removeObject(forKey: TPCPreferencesThemeFontNameMissingLocallyDefaultsKey)
	}

	@objc(setThemeChannelViewFontNameWithExistenceCheck:) class func local_setThemeChannelViewFontNameWithExistenceCheck(
		_ value: String
	) {
		if NSFont.fontIsAvailable(value) {
			local_setThemeChannelViewFontName(value)
		} else {
			set(
				true,
				TPCPreferencesThemeFontNameMissingLocallyDefaultsKey
			)
		}
	}

	@objc(themeChannelViewFontSize) class func local_themeChannelViewFontSize()
		-> CGFloat
	{
		double(TPCPreferencesThemeFontSizeDefaultsKey)
	}

	@objc(setThemeChannelViewFontSize:) class func local_setThemeChannelViewFontSize(_ value: CGFloat) {
		preferences.set(
			value,
			forKey: TPCPreferencesThemeFontSizeDefaultsKey
		)
	}

	@objc(themeChannelViewFont) class func local_themeChannelViewFont() -> NSFont? {
		NSFont(
			name: local_themeChannelViewFontName(),
			size: local_themeChannelViewFontSize()
		)
	}

	@objc(
		themeChannelViewFontPreferenceUserConfigurable
	) class func local_themeChannelViewFontPreferenceUserConfigurable()
		-> Bool
	{
		bool("Theme -> Channel Font Preference Enabled")
	}

	@objc(
		setThemeChannelViewFontPreferenceUserConfigurable:
	) class func local_setThemeChannelViewFontPreferenceUserConfigurable(_ value: Bool) {
		preferences.registerDefault(
			value as NSNumber,
			forKey: "Theme -> Channel Font Preference Enabled"
		)
	}

	@objc(themeNicknameFormatDefault) class func local_themeNicknameFormatDefault()
		-> String
	{
		local_defaultPreferences()["Theme -> Nickname Format"] as! String
	}

	@objc(themeNicknameFormat) class func local_themeNicknameFormat() -> String {
		string("Theme -> Nickname Format")!
	}

	@objc(themeNicknameFormatPreferenceUserConfigurable) class func local_themeNicknameFormatPreferenceUserConfigurable(
	)
		-> Bool
	{
		bool("Theme -> Nickname Format Preference Enabled")
	}

	@objc(
		setThemeNicknameFormatPreferenceUserConfigurable:
	) class func local_setThemeNicknameFormatPreferenceUserConfigurable(_ value: Bool) {
		preferences.registerDefault(
			value as NSNumber,
			forKey: "Theme -> Nickname Format Preference Enabled"
		)
	}

	@objc(themeTimestampFormatDefault) class func local_themeTimestampFormatDefault()
		-> String
	{
		local_defaultPreferences()["Theme -> Timestamp Format"] as! String
	}

	@objc(themeTimestampFormat) class func local_themeTimestampFormat()
		-> String
	{
		string("Theme -> Timestamp Format")!
	}

	@objc(
		themeTimestampFormatPreferenceUserConfigurable
	) class func local_themeTimestampFormatPreferenceUserConfigurable()
		-> Bool
	{
		bool("Theme -> Timestamp Format Preference Enabled")
	}

	@objc(
		setThemeTimestampFormatPreferenceUserConfigurable:
	) class func local_setThemeTimestampFormatPreferenceUserConfigurable(_ value: Bool) {
		preferences.registerDefault(
			value as NSNumber,
			forKey: "Theme -> Timestamp Format Preference Enabled"
		)
	}

	@objc(themeUserStyleSheetRules) class func local_themeUserStyleSheetRules()
		-> String?
	{
		string("Theme -> User Style Sheet Rules")
	}

	@objc(setThemeUserStyleSheetRules:) class func local_setThemeUserStyleSheetRules(_ value: String?) {
		set(
			value,
			"Theme -> User Style Sheet Rules"
		)
	}

	@objc(automaticallyReloadCustomThemesWhenTheyChange) class func local_automaticallyReloadCustomThemesWhenTheyChange(
	)
		-> Bool
	{
		bool("AutomaticallyReloadCustomThemesWhenTheyChange")
	}

	@objc(webKit2ProcessPoolSizeLimited) class func local_webKit2ProcessPoolSizeLimited()
		-> Bool
	{
		bool("WebViewProcessPoolSizeIsLimited")
	}

	@objc(webKit2PreviewLinks) class func local_webKit2PreviewLinks() -> Bool {
		bool("WebViewPreviewLinks")
	}

	@objc(themeChannelViewUsesCustomScrollers) class func local_themeChannelViewUsesCustomScrollers()
		-> Bool
	{
		!bool("WebViewDoNotUsesCustomScrollers")
	}

	@objc(channelViewArrangement) class func local_channelViewArrangement()
		-> TXChannelViewArrangement
	{
		TXChannelViewArrangement(rawValue: uint("ChannelViewArrangement")) ?? .horizontal
	}

	@objc(tabCompletionSuffix) class func local_tabCompletionSuffix()
		-> String?
	{
		string("Keyboard -> Tab Key Completion Suffix")
	}

	@objc(setTabCompletionSuffix:) class func local_setTabCompletionSuffix(_ value: String) {
		set(
			value,
			"Keyboard -> Tab Key Completion Suffix"
		)
	}

	@objc(tabCompletionDoNotAppendWhitespace) class func local_tabCompletionDoNotAppendWhitespace()
		-> Bool
	{
		bool("Tab Completion -> Do Not Use Whitespace for Missing Completion Suffix")
	}

	@objc(tabCompletionCutForwardToFirstWhitespace) class func local_tabCompletionCutForwardToFirstWhitespace()
		-> Bool
	{
		bool("Tab Completion -> Completion Suffix Cut Forward Until Space")
	}

	@objc(fileTransferRequestReplyAction) class func local_fileTransferRequestReplyAction()
		-> TXFileTransferRequestReply
	{
		TXFileTransferRequestReply(rawValue: uint("File Transfers -> File Transfer Request Reply Action")) ?? .ignore
	}

	@objc(fileTransferIPAddressDetectionMethod) class func local_fileTransferIPAddressDetectionMethod()
		-> TXFileTransferIPAddressMethodDetection
	{
		TXFileTransferIPAddressMethodDetection(
			rawValue: uint("File Transfers -> File Transfer IP Address Detection Method")
		) ??
			.routerOnly
	}

	@objc(fileTransferRequestsAreReversed) class func local_fileTransferRequestsAreReversed()
		-> Bool
	{
		bool("File Transfers -> File Transfer Requests Use Reverse DCC")
	}

	@objc(fileTransfersPreventIdleSystemSleep) class func local_fileTransfersPreventIdleSystemSleep()
		-> Bool
	{
		bool("File Transfers -> Idle System Sleep Prevented During File Transfer")
	}

	@objc(fileTransferPortRangeStart) class func local_fileTransferPortRangeStart() -> UInt16 {
		preferences
			.unsignedShort(forKey: "File Transfers -> File Transfer Port Range Start")
	}

	@objc(setFileTransferPortRangeStart:) class func local_setFileTransferPortRangeStart(_ value: UInt16) {
		preferences.setUnsignedShort(
			value,
			forKey: "File Transfers -> File Transfer Port Range Start"
		)
	}

	@objc(fileTransferPortRangeEnd) class func local_fileTransferPortRangeEnd() -> UInt16 {
		preferences
			.unsignedShort(forKey: "File Transfers -> File Transfer Port Range End")
	}

	@objc(setFileTransferPortRangeEnd:) class func local_setFileTransferPortRangeEnd(_ value: UInt16) {
		preferences.setUnsignedShort(
			value,
			forKey: "File Transfers -> File Transfer Port Range End"
		)
	}

	@objc(fileTransferManuallyEnteredIPAddress) class func local_fileTransferManuallyEnteredIPAddress()
		-> String?
	{
		string("File Transfers -> File Transfer Manually Entered IP Address")
	}

	@objc(fileTransferIPAddressInterfaceName) class func local_fileTransferIPAddressInterfaceName()
		-> String?
	{
		string("File Transfers -> File Transfer IP Address Interface Name")
	}

	@objc(scrollbackSaveLimit) class func local_scrollbackSaveLimit() -> UInt {
		uint("ScrollbackMaximumSavedLineCount")
	}

	@objc(setScrollbackSaveLimit:) class func local_setScrollbackSaveLimit(_ value: UInt) {
		preferences.setUnsignedInteger(
			value,
			forKey: "ScrollbackMaximumSavedLineCount"
		)
	}

	@objc(scrollbackVisibleLimit) class func local_scrollbackVisibleLimit()
		-> UInt
	{
		uint("ScrollbackMaximumVisibleLineCount")
	}

	@objc(setScrollbackVisibleLimit:) class func local_setScrollbackVisibleLimit(_ value: UInt) {
		preferences.setUnsignedInteger(
			value,
			forKey: "ScrollbackMaximumVisibleLineCount"
		)
	}

	@objc(soundIsMuted) class func local_soundIsMuted() -> Bool {
		bool("Notification Sound Is Muted")
	}

	@objc(setSoundIsMuted:) class func local_setSoundIsMuted(_ value: Bool) {
		set(value, "Notification Sound Is Muted")
	}

	@objc(keyForEvent:category:)
	class func local_key(for event: TXNotificationType, category: String) -> String? {
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

	@objc(soundForEvent:) class func local_sound(for event: TXNotificationType) -> String? {
		local_key(
			for: event,
			category: "Sound"
		).flatMap(string)
	}

	@objc(setSound:forEvent:) class func local_setSound(_ value: String?, for event: TXNotificationType) {
		if let key = local_key(
			for: event,
			category: "Sound"
		) {
			set(value, key)
		}
	}

	@objc(notificationEnabledForEvent:) class func local_notificationEnabled(for event: TXNotificationType)
		-> Bool
	{
		local_key(
			for: event,
			category: "Enabled"
		).map(bool) ?? false
	}

	@objc(setNotificationEnabled:forEvent:) class func local_setNotificationEnabled(
		_ value: Bool,
		for event: TXNotificationType
	) {
		if let key = local_key(for: event, category: "Enabled") {
			set(value, key)
		}
	}

	@objc(disabledWhileAwayForEvent:) class func local_disabledWhileAway(for event: TXNotificationType)
		-> Bool
	{
		local_key(
			for: event,
			category: "Disable While Away"
		).map(bool) ?? false
	}

	@objc(setDisabledWhileAway:forEvent:) class func local_setDisabledWhileAway(
		_ value: Bool,
		for event: TXNotificationType
	) {
		if let key = local_key(for: event, category: "Disable While Away") {
			set(value, key)
		}
	}

	@objc(bounceDockIconForEvent:) class func local_bounceDockIcon(for event: TXNotificationType) -> Bool {
		local_key(
			for: event,
			category: "Bounce Dock Icon"
		).map(bool) ?? false
	}

	@objc(setBounceDockIcon:forEvent:) class func local_setBounceDockIcon(_ value: Bool,
	                                                                      for event: TXNotificationType)
	{
		if let key = local_key(
			for: event,
			category: "Bounce Dock Icon"
		) {
			set(value, key)
		}
	}

	@objc(bounceDockIconRepeatedlyForEvent:) class func local_bounceDockIconRepeatedly(for event: TXNotificationType)
		-> Bool
	{
		local_key(
			for: event,
			category: "Bounce Dock Icon Repeatedly"
		).map(bool) ?? false
	}

	@objc(setBounceDockIconRepeatedly:forEvent:) class func local_setBounceDockIconRepeatedly(
		_ value: Bool,
		for event: TXNotificationType
	) {
		if let key = local_key(for: event, category: "Bounce Dock Icon Repeatedly") {
			set(value, key)
		}
	}

	@objc(speakEvent:) class func local_speak(_ event: TXNotificationType) -> Bool {
		local_key(
			for: event,
			category: "Speak"
		).map(bool) ?? false
	}

	@objc(setEventIsSpoken:forEvent:) class func local_setEventIsSpoken(_ value: Bool, for event: TXNotificationType) {
		if let key = local_key(
			for: event,
			category: "Speak"
		) {
			set(value, key)
		}
	}

	@objc(onlySpeakEventsForSelection) class func local_onlySpeakEventsForSelection()
		-> Bool
	{
		bool("OnlySpeakNotificationsForSelection")
	}

	@objc(setOnlySpeakEventsForSelection:) class func local_setOnlySpeakEventsForSelection(_ value: Bool) {
		set(
			value,
			"OnlySpeakNotificationsForSelection"
		)
	}

	@objc(channelMessageSpeakChannelName) class func local_channelMessageSpeakChannelName() -> Bool {
		bool(local_key(
			for: .channelMessage,
			category: "Speak Channel Name"
		)!)
	}

	@objc(setChannelMessageSpeakChannelName:) class func local_setChannelMessageSpeakChannelName(_ value: Bool) {
		set(
			value,
			local_key(for: .channelMessage, category: "Speak Channel Name")!
		)
	}

	@objc(channelMessageSpeakNickname) class func local_channelMessageSpeakNickname() -> Bool {
		bool(local_key(
			for: .channelMessage,
			category: "Speak Nickname"
		)!)
	}

	@objc(setChannelMessageSpeakNickname:) class func local_setChannelMessageSpeakNickname(_ value: Bool) {
		set(
			value,
			local_key(for: .channelMessage, category: "Speak Nickname")!
		)
	}

	@objc(clientList) class func local_clientList() -> [[String: Any]]? {
		preferences
			.object(forKey: IRCWorldClientListDefaultsKey) as? [[String: Any]]
	}

	@objc(setClientList:) class func local_setClientList(_ value: [[String: Any]]?) {
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

	@objc(_loadExcludeKeywords) class func local_loadExcludeKeywords() {
		excludeKeywords = loadKeywords(for: "Highlight List -> Excluded Matches")
	}

	@objc(_loadMatchKeywords) class func local_loadMatchKeywords() {
		matchKeywords = loadKeywords(for: "Highlight List -> Primary Matches")
	}

	private class func cleanKeywords(for key: String) {
		let strings = loadKeywords(for: key).sorted { $0.caseInsensitiveCompare($1) == .orderedAscending }
		set(strings.map { ["string": $0] }, key)
	}

	@objc(_cleanUpKeywords:) class func local_cleanUpKeywords(_ key: String) {
		cleanKeywords(for: key)
	}

	@objc(cleanUpHighlightKeywords) class func local_cleanUpHighlightKeywords() {
		cleanKeywords(for: "Highlight List -> Primary Matches")
		cleanKeywords(for: "Highlight List -> Excluded Matches")
	}

	@objc(highlightMatchKeywords) class func local_highlightMatchKeywords() -> [String]? {
		matchKeywords
	}

	@objc(highlightExcludeKeywords) class func local_highlightExcludeKeywords() -> [String]? {
		excludeKeywords
	}

	@objc(registerWebKit2DynamicDefaults) class func local_registerWebKit2DynamicDefaults() {
		UserDefaults.standard.set(false, forKey: "__WebInspectorPageGroupLevel1__.WebKit2InspectorStartsAttached")
	}

	@objc(registerPreferencesDictionaryVersion) class func local_registerPreferencesDictionaryVersion() {
		guard uint("TPCPreferencesDictionaryVersion") < TPCPreferencesDictionaryVersion else { return }
		preferences.setUnsignedInteger(TPCPreferencesDictionaryVersion, forKey: "TPCPreferencesDictionaryVersion")
	}

	@objc(defaultPreferences) class func local_defaultPreferences() -> [String: Any] {
		preferences
			.volatileDomain(forName: UserDefaults.registrationDomain)
	}

	@objc(registerDynamicDefaults) class func local_registerDynamicDefaults() {
		local_populateDefaultNickname()
		local_registerWebKit2DynamicDefaults()
		local_registerPreferencesDictionaryVersion()
	}

	@objc(registerDefaults) class func local_registerDefaults() {
		let local = TPCResourceManager.dictionary(
			fromResources: "RegisteredUserDefaults",
			inDirectory: "Preferences"
		) ?? [:]
		UserDefaults.standard.register(defaults: local)
		let container = TPCResourceManager.dictionary(
			fromResources: "RegisteredUserDefaultsInContainer",
			inDirectory: "Preferences"
		) ?? [:]
		preferences.register(defaults: container)
		local_registerDynamicDefaults()
	}

	@objc(initPreferences) class func local_initPreferences() {
		ApplicationInfo.incrementApplicationRunCount()
		local_registerDefaults()
		PathInfo.startUsingTranscriptFolderURL()
		let observer = KeywordDefaultsObserver()
		preferences.addObserver(
			observer,
			forKeyPath: "Highlight List -> Excluded Matches",
			options: .new,
			context: nil
		)
		preferences.addObserver(
			observer,
			forKeyPath: "Highlight List -> Primary Matches",
			options: .new,
			context: nil
		)
		keywordObserver = observer
		reloadHighlightKeywords()
	}

	@objc(textFieldAutomaticSpellCheck) class func local_textFieldAutomaticSpellCheck()
		-> Bool
	{
		bool("TextFieldAutomaticSpellCheck")
	}

	@objc(setTextFieldAutomaticSpellCheck:) class func local_setTextFieldAutomaticSpellCheck(_ value: Bool) {
		set(
			value,
			"TextFieldAutomaticSpellCheck"
		)
	}

	@objc(textFieldAutomaticGrammarCheck) class func local_textFieldAutomaticGrammarCheck()
		-> Bool
	{
		bool("TextFieldAutomaticGrammarCheck")
	}

	@objc(setTextFieldAutomaticGrammarCheck:) class func local_setTextFieldAutomaticGrammarCheck(_ value: Bool) {
		set(
			value,
			"TextFieldAutomaticGrammarCheck"
		)
	}

	@objc(textFieldAutomaticSpellCorrection) class func local_textFieldAutomaticSpellCorrection()
		-> Bool
	{
		bool("TextFieldAutomaticSpellCorrection")
	}

	@objc(setTextFieldAutomaticSpellCorrection:) class func local_setTextFieldAutomaticSpellCorrection(_ value: Bool) {
		set(
			value,
			"TextFieldAutomaticSpellCorrection"
		)
	}

	@objc(textFieldSmartCopyPaste) class func local_textFieldSmartCopyPaste() -> Bool {
		bool("TextFieldSmartCopyPaste")
	}

	@objc(setTextFieldSmartCopyPaste:) class func local_setTextFieldSmartCopyPaste(_ value: Bool) {
		set(
			value,
			"TextFieldSmartCopyPaste"
		)
	}

	@objc(textFieldSmartQuotes) class func local_textFieldSmartQuotes() -> Bool {
		bool("TextFieldSmartQuotes")
	}

	@objc(setTextFieldSmartQuotes:) class func local_setTextFieldSmartQuotes(_ value: Bool) {
		set(
			value,
			"TextFieldSmartQuotes"
		)
	}

	@objc(textFieldSmartDashes) class func local_textFieldSmartDashes() -> Bool {
		bool("TextFieldSmartDashes")
	}

	@objc(setTextFieldSmartDashes:) class func local_setTextFieldSmartDashes(_ value: Bool) {
		set(
			value,
			"TextFieldSmartDashes"
		)
	}

	@objc(textFieldSmartLinks) class func local_textFieldSmartLinks() -> Bool {
		bool("TextFieldSmartLinks")
	}

	@objc(setTextFieldSmartLinks:) class func local_setTextFieldSmartLinks(_ value: Bool) {
		set(
			value,
			"TextFieldSmartLinks"
		)
	}

	@objc(textFieldDataDetectors) class func local_textFieldDataDetectors() -> Bool {
		bool("TextFieldDataDetectors")
	}

	@objc(setTextFieldDataDetectors:) class func local_setTextFieldDataDetectors(_ value: Bool) {
		set(
			value,
			"TextFieldDataDetectors"
		)
	}

	@objc(textFieldTextReplacement) class func local_textFieldTextReplacement()
		-> Bool
	{
		bool("TextFieldTextReplacement")
	}

	@objc(setTextFieldTextReplacement:) class func local_setTextFieldTextReplacement(_ value: Bool) {
		set(
			value,
			"TextFieldTextReplacement"
		)
	}
}
