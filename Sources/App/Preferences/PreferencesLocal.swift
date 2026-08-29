/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
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

import AppKit
import CocoaExtensions
import Combine
import Synchronization

/** Computed, not stored: `TextualUserDefaults.shared()` is already the process's
 one instance, and a second global reference to it would need a second isolation
 exception for the very same object. This way the exception lives in exactly one
 place, where the instance is made. */
private nonisolated var preferences: TextualUserDefaults { // nonisolated: pure
	TextualUserDefaults.shared()
}

/** Highlight keywords are rewritten by a defaults observation on whichever thread
 wrote the default and read by message rendering on the IRC threads, so the cache
 is a value behind a lock rather than a pair of unguarded globals. */
private struct HighlightKeywords {
	var match: [String]?
	var exclude: [String]?
}

private nonisolated let highlightKeywords = Mutex(HighlightKeywords())
private nonisolated let highlightKeywordObservation = Mutex<AnyCancellable?>(nil)

// MARK: - Identity

public nonisolated extension TextualPreferences {
	class func defaultNicknamePrefix() -> String {
		Preferences.Identity.nickname.defaultValue
	}

	class func populateDefaultNickname() {
		let nickname = "\(defaultNicknamePrefix())\(randomNumber(100))"
		preferences.registerDefault(nickname, for: Preferences.Identity.nickname)
	}

	class func defaultNickname() -> String {
		Preferences.Identity.nickname.value
	}

	class func setDefaultNickname(_ value: String) {
		Preferences.Identity.nickname.value = value
	}

	class func defaultAwayNickname() -> String? {
		Preferences.Identity.awayNickname.storedValue
	}

	class func defaultUsername() -> String {
		Preferences.Identity.username.value
	}

	class func defaultRealName() -> String {
		Preferences.Identity.realName.value
	}

	class func setDefaultRealName(_ value: String) {
		Preferences.Identity.realName.value = value
	}

	class func masqueradeCTCPVersion() -> String? {
		Preferences.Identity.ctcpVersionMasquerade.storedValue
	}

	class func setOnboardingCompleted(_ value: Bool) {
		Preferences.Identity.onboardingCompleted.value = value
	}

	class func onboardingCompleted() -> Bool {
		Preferences.Identity.onboardingCompleted.value
	}
}

// MARK: - Connection

public nonisolated extension TextualPreferences {
	class func autojoinMaximumChannelJoins() -> UInt {
		Preferences.Connection.autojoinMaximumChannelJoins.value
	}

	class func autojoinDelayBetweenChannelJoins() -> TimeInterval {
		Preferences.Connection.autojoinDelayBetweenChannelJoins.value
	}

	class func autojoinDelayAfterIdentification() -> TimeInterval {
		Preferences.Connection.autojoinDelayAfterIdentification.value
	}

	class func autoJoinOnInvite() -> Bool {
		Preferences.Connection.autojoinOnInvite.value
	}

	class func setAwayOnScreenSleep() -> Bool {
		Preferences.Connection.awayOnScreenSleep.value
	}

	class func disconnectOnSleep() -> Bool {
		Preferences.Connection.disconnectOnSleep.value
	}

	class func displayServerMOTD() -> Bool {
		Preferences.Connection.displayServerMOTD.value
	}

	class func preferModernCiphers() -> Bool {
		Preferences.Connection.preferModernCiphers.value
	}

	class func rejoinOnKick() -> Bool {
		Preferences.Connection.rejoinOnKick.value
	}

	class func sendTypingNotifications() -> Bool {
		Preferences.Connection.sendTypingNotifications.value
	}

	class func confirmQuit() -> Bool {
		Preferences.Connection.confirmQuit.value
	}

	class func enableEchoMessageCapability() -> Bool {
		false
	}

	class func clientList() -> [[String: Any]]? {
		Preferences.Connection.clientList.object as? [[String: Any]]
	}

	class func setClientList(_ value: [[String: Any]]?) {
		Preferences.Connection.clientList.object = value
	}
}

// MARK: - Commands

public nonisolated extension TextualPreferences {
	class func defaultKickMessage() -> String {
		Preferences.Commands.kickMessage.value
	}

	class func irCopDefaultKillMessage() -> String {
		Preferences.Commands.irCopKillMessage.value
	}

	class func irCopDefaultGlineMessage() -> String {
		Preferences.Commands.irCopGlineMessage.value
	}

	class func irCopDefaultShunMessage() -> String {
		Preferences.Commands.irCopShunMessage.value
	}

	class func amsgAllConnections() -> Bool {
		Preferences.Commands.amsgAllConnections.value
	}

	class func awayAllConnections() -> Bool {
		Preferences.Commands.awayAllConnections.value
	}

	class func clearAllConnections() -> Bool {
		Preferences.Commands.clearAllConnections.value
	}

	class func nickAllConnections() -> Bool {
		Preferences.Commands.nickAllConnections.value
	}

	class func giveFocusOnMessageCommand() -> Bool {
		Preferences.Commands.giveFocusOnMessageCommand.value
	}

	class func banFormat() -> TXHostmaskBanFormat {
		Preferences.Commands.banFormat.value
	}

	class func locationToSendNotices() -> TXNoticeSendLocation {
		Preferences.Commands.noticeDestination.value
	}

	class func setLocationToSendNotices(_ value: TXNoticeSendLocation) {
		Preferences.Commands.noticeDestination.value = value
	}

	class func setDeveloperModeEnabled(_ value: Bool) {
		Preferences.Commands.developerMode.value = value
	}

	class func developerModeEnabled() -> Bool {
		Preferences.Commands.developerMode.value
	}
}

// MARK: - Messages

public nonisolated extension TextualPreferences {
	class func showDateChanges() -> Bool {
		Preferences.Messages.showDateChanges.value
	}

	class func showInlineMedia() -> Bool {
		Preferences.Messages.showInlineMedia.value
	}

	class func setShowInlineMedia(_ value: Bool) {
		Preferences.Messages.showInlineMedia.value = value
	}

	class func showJoinLeave() -> Bool {
		Preferences.Messages.showJoinLeave.value
	}

	class func autoAddScrollbackMark() -> Bool {
		Preferences.Messages.autoAddScrollbackMark.value
	}

	class func copyOnSelect() -> Bool {
		Preferences.Messages.copyOnSelect.value
	}

	class func removeAllFormatting() -> Bool {
		Preferences.Messages.removeAllFormatting.value
	}

	class func rightToLeftFormatting() -> Bool {
		Preferences.Messages.rightToLeftFormatting.value
	}

	class func replyToCTCPRequests() -> Bool {
		Preferences.Messages.replyToCTCPRequests.value
	}

	class func automaticallyDetectHighlightSpam() -> Bool {
		Preferences.Messages.detectHighlightSpam.value
	}

	class func automaticallyFilterUnicodeTextSpam() -> Bool {
		Preferences.Messages.filterUnicodeTextSpam.value
	}

	class func openBrowserInBackground() -> Bool {
		Preferences.Messages.openBrowserInBackground.value
	}

	class func disableNicknameColorHashing() -> Bool {
		Preferences.Messages.disableNicknameColorHashing.value
	}
}

// MARK: - Logging

public nonisolated extension TextualPreferences {
	class func logToDisk() -> Bool {
		Preferences.Logging.logToDisk.value
	}

	class func setLogToDisk(_ value: Bool) {
		Preferences.Logging.logToDisk.value = value
	}

	class func logToDiskIsEnabled() -> Bool {
		logToDisk() && PathInfo.transcriptFolderURL != nil
	}

	class func logHighlights() -> Bool {
		Preferences.Logging.logHighlights.value
	}

	class func reloadScrollbackOnLaunch() -> Bool {
		Preferences.Logging.reloadScrollbackOnLaunch.value
	}

	class func loadHistoryLazily() -> Bool {
		Preferences.Logging.loadHistoryLazily.value
	}

	class func scrollbackSaveLimit() -> UInt {
		Preferences.Logging.scrollbackSaveLimit.value
	}

	class func setScrollbackSaveLimit(_ value: UInt) {
		Preferences.Logging.scrollbackSaveLimit.value = value
	}

	class func scrollbackVisibleLimit() -> UInt {
		Preferences.Logging.scrollbackVisibleLimit.value
	}

	class func setScrollbackVisibleLimit(_ value: UInt) {
		Preferences.Logging.scrollbackVisibleLimit.value = value
	}
}

// MARK: - Appearance

public nonisolated extension TextualPreferences {
	class func setAppearance(_ value: TXPreferredAppearance) {
		Preferences.Appearance.preferredAppearance.value = value
	}

	class func appearance() -> TXPreferredAppearance {
		Preferences.Appearance.preferredAppearance.value
	}

	class func channelViewArrangement() -> TXChannelViewArrangement {
		Preferences.Appearance.channelViewArrangement.value
	}

	class func disableSidebarTranslucency() -> Bool {
		Preferences.Appearance.disableSidebarTranslucency.value
	}

	class func memberListDisplayNoModeSymbol() -> Bool {
		Preferences.Appearance.memberListNoModeSymbol.value
	}

	class func memberListSortFavorsServerStaff() -> Bool {
		Preferences.Appearance.memberListSortFavorsServerStaff.value
	}

	class func memberListUpdatesUserInfoPopoverOnScroll() -> Bool {
		Preferences.Appearance.memberListUpdatesPopoverOnScroll.value
	}

	class func conversationTrackingIncludesUserModeSymbol() -> Bool {
		Preferences.Appearance.conversationTrackingIncludesModeSymbol.value
	}

	class func trackUserAwayStatusMaximumChannelSize() -> UInt {
		Preferences.Appearance.trackUserAwayStatusMaximumChannelSize.value
	}

	class func channelNavigationIsServerSpecific() -> Bool {
		Preferences.Appearance.channelNavigationIsServerSpecific.value
	}

	class func connectOnDoubleclick() -> Bool {
		Preferences.Appearance.connectOnDoubleClick.value
	}

	class func disconnectOnDoubleclick() -> Bool {
		Preferences.Appearance.disconnectOnDoubleClick.value
	}

	class func joinOnDoubleclick() -> Bool {
		Preferences.Appearance.joinOnDoubleClick.value
	}

	class func leaveOnDoubleclick() -> Bool {
		Preferences.Appearance.leaveOnDoubleClick.value
	}

	class func rememberServerListQueryStates() -> Bool {
		Preferences.Appearance.rememberQueryStates.value
	}

	class func webKit2ProcessPoolSizeLimited() -> Bool {
		Preferences.Appearance.webViewProcessPoolLimited.value
	}

	class func webKit2PreviewLinks() -> Bool {
		Preferences.Appearance.webViewPreviewLinks.value
	}

	class func themeChannelViewUsesCustomScrollers() -> Bool {
		Preferences.Appearance.webViewCustomScrollersDisabled.value == false
	}
}

// MARK: - Theme

public nonisolated extension TextualPreferences {
	class func themeNameDefault() -> String {
		Preferences.Theme.name.defaultValue
	}

	class func themeName() -> String {
		Preferences.Theme.name.value
	}

	class func setThemeName(_ value: String) {
		Preferences.Theme.name.value = value
		Preferences.Theme.nameMissingLocally.reset()
	}

	/** Main-actor because it asks the theme controller whether a style is on disk.
	 The translation blocked the calling thread on the main queue instead, which
	 deadlocks when the caller is what the main thread is waiting for. */
	@MainActor
	class func setThemeNameWithExistenceCheck(_ value: String) {
		if SharedApplication.sharedThemeController().themeExists(value) {
			setThemeName(value)
		} else {
			Preferences.Theme.nameMissingLocally.value = true
		}
	}

	class func themeChannelViewFontNameDefault() -> String {
		Preferences.Theme.fontName.defaultValue
	}

	class func themeChannelViewFontName() -> String {
		Preferences.Theme.fontName.value
	}

	class func setThemeChannelViewFontName(_ value: String) {
		Preferences.Theme.fontName.value = value
		Preferences.Theme.fontNameMissingLocally.reset()
	}

	class func setThemeChannelViewFontNameWithExistenceCheck(_ value: String) {
		if NSFont.textual_fontIsAvailable(value) {
			setThemeChannelViewFontName(value)
		} else {
			Preferences.Theme.fontNameMissingLocally.value = true
		}
	}

	class func themeChannelViewFontSize() -> CGFloat {
		Preferences.Theme.fontSize.value
	}

	class func setThemeChannelViewFontSize(_ value: CGFloat) {
		Preferences.Theme.fontSize.value = value
	}

	class func themeChannelViewFont() -> NSFont? {
		NSFont(name: themeChannelViewFontName(), size: themeChannelViewFontSize())
	}

	class func themeChannelViewFontPreferenceUserConfigurable() -> Bool {
		Preferences.Theme.fontIsUserConfigurable.value
	}

	class func setThemeChannelViewFontPreferenceUserConfigurable(_ value: Bool) {
		preferences.registerDefault(value, for: Preferences.Theme.fontIsUserConfigurable)
	}

	class func themeNicknameFormatDefault() -> String {
		Preferences.Theme.nicknameFormat.defaultValue
	}

	class func themeNicknameFormat() -> String {
		Preferences.Theme.nicknameFormat.value
	}

	class func themeNicknameFormatPreferenceUserConfigurable() -> Bool {
		Preferences.Theme.nicknameFormatIsUserConfigurable.value
	}

	class func setThemeNicknameFormatPreferenceUserConfigurable(_ value: Bool) {
		preferences.registerDefault(value, for: Preferences.Theme.nicknameFormatIsUserConfigurable)
	}

	class func themeTimestampFormatDefault() -> String {
		Preferences.Theme.timestampFormat.defaultValue
	}

	class func themeTimestampFormat() -> String {
		Preferences.Theme.timestampFormat.value
	}

	class func themeTimestampFormatPreferenceUserConfigurable() -> Bool {
		Preferences.Theme.timestampFormatIsUserConfigurable.value
	}

	class func setThemeTimestampFormatPreferenceUserConfigurable(_ value: Bool) {
		preferences.registerDefault(value, for: Preferences.Theme.timestampFormatIsUserConfigurable)
	}

	/** The rules are interpolated into a `<style>` element in the log view, so
	 the one sequence that would escape that element is neutralised here. */
	class func themeUserStyleSheetRules() -> String? {
		LogViewContentPolicy.sanitizedStyleSheetText(Preferences.Theme.userStyleSheetRules.storedValue)
	}

	class func setThemeUserStyleSheetRules(_ value: String?) {
		Preferences.Theme.userStyleSheetRules.storedValue = value
	}

	class func automaticallyReloadCustomThemesWhenTheyChange() -> Bool {
		Preferences.Theme.reloadCustomThemesOnChange.value
	}
}

// MARK: - Input

public nonisolated extension TextualPreferences {
	class func commandReturnSendsMessageAsAction() -> Bool {
		Preferences.Input.commandReturnSendsAction.value
	}

	class func controlEnterSendsMessage() -> Bool {
		Preferences.Input.controlEnterSendsMessage.value
	}

	class func inputHistoryIsChannelSpecific() -> Bool {
		Preferences.Input.historyIsChannelSpecific.value
	}

	class func swipeMinimumLength() -> CGFloat {
		Preferences.Input.swipeMinimumLength.value
	}

	class func tabKeyAction() -> TXTabKeyAction {
		Preferences.Input.tabKeyAction.value
	}

	class func commandWKeyAction() -> TXCommandWKeyAction {
		Preferences.Input.commandWKeyAction.value
	}

	class func userDoubleClickOption() -> TXUserDoubleClickAction {
		Preferences.Input.userDoubleClickAction.value
	}

	class func mainTextViewFontSize() -> TVCMainWindowTextViewFontSize {
		Preferences.Input.textViewFontSize.value
	}

	class func focusMainTextViewOnSelectionChange() -> Bool {
		Preferences.Input.focusTextViewOnSelectionChange.value
	}

	class func tabCompletionSuffix() -> String? {
		Preferences.Input.tabCompletionSuffix.storedValue
	}

	class func setTabCompletionSuffix(_ value: String) {
		Preferences.Input.tabCompletionSuffix.value = value
	}

	class func tabCompletionDoNotAppendWhitespace() -> Bool {
		Preferences.Input.tabCompletionNoWhitespace.value
	}

	class func tabCompletionCutForwardToFirstWhitespace() -> Bool {
		Preferences.Input.tabCompletionCutForward.value
	}

	class func textFieldAutomaticSpellCheck() -> Bool {
		Preferences.Input.automaticSpellCheck.value
	}

	class func setTextFieldAutomaticSpellCheck(_ value: Bool) {
		Preferences.Input.automaticSpellCheck.value = value
	}

	class func textFieldAutomaticGrammarCheck() -> Bool {
		Preferences.Input.automaticGrammarCheck.value
	}

	class func setTextFieldAutomaticGrammarCheck(_ value: Bool) {
		Preferences.Input.automaticGrammarCheck.value = value
	}

	class func textFieldAutomaticSpellCorrection() -> Bool {
		Preferences.Input.automaticSpellCorrection.value
	}

	class func setTextFieldAutomaticSpellCorrection(_ value: Bool) {
		Preferences.Input.automaticSpellCorrection.value = value
	}

	class func textFieldSmartCopyPaste() -> Bool {
		Preferences.Input.smartCopyPaste.value
	}

	class func setTextFieldSmartCopyPaste(_ value: Bool) {
		Preferences.Input.smartCopyPaste.value = value
	}

	class func textFieldSmartQuotes() -> Bool {
		Preferences.Input.smartQuotes.value
	}

	class func setTextFieldSmartQuotes(_ value: Bool) {
		Preferences.Input.smartQuotes.value = value
	}

	class func textFieldSmartDashes() -> Bool {
		Preferences.Input.smartDashes.value
	}

	class func setTextFieldSmartDashes(_ value: Bool) {
		Preferences.Input.smartDashes.value = value
	}

	class func textFieldSmartLinks() -> Bool {
		Preferences.Input.smartLinks.value
	}

	class func setTextFieldSmartLinks(_ value: Bool) {
		Preferences.Input.smartLinks.value = value
	}

	class func textFieldDataDetectors() -> Bool {
		Preferences.Input.dataDetectors.value
	}

	class func setTextFieldDataDetectors(_ value: Bool) {
		Preferences.Input.dataDetectors.value = value
	}

	class func textFieldTextReplacement() -> Bool {
		Preferences.Input.textReplacement.value
	}

	class func setTextFieldTextReplacement(_ value: Bool) {
		Preferences.Input.textReplacement.value = value
	}
}

// MARK: - File transfers

public nonisolated extension TextualPreferences {
	class func fileTransferRequestReplyAction() -> TXFileTransferRequestReply {
		Preferences.FileTransfers.requestReplyAction.value
	}

	class func fileTransferIPAddressDetectionMethod() -> TXFileTransferIPAddressMethodDetection {
		Preferences.FileTransfers.ipAddressDetectionMethod.value
	}

	class func fileTransferRequestsAreReversed() -> Bool {
		Preferences.FileTransfers.requestsAreReversed.value
	}

	class func fileTransfersPreventIdleSystemSleep() -> Bool {
		Preferences.FileTransfers.preventIdleSystemSleep.value
	}

	class func fileTransferPortRangeStart() -> UInt16 {
		Preferences.FileTransfers.portRangeStart.value
	}

	class func setFileTransferPortRangeStart(_ value: UInt16) {
		Preferences.FileTransfers.portRangeStart.value = value
	}

	class func fileTransferPortRangeEnd() -> UInt16 {
		Preferences.FileTransfers.portRangeEnd.value
	}

	class func setFileTransferPortRangeEnd(_ value: UInt16) {
		Preferences.FileTransfers.portRangeEnd.value = value
	}

	class func fileTransferManuallyEnteredIPAddress() -> String? {
		Preferences.FileTransfers.manuallyEnteredIPAddress.storedValue
	}

	class func fileTransferIPAddressInterfaceName() -> String? {
		Preferences.FileTransfers.ipAddressInterfaceName.storedValue
	}
}

// MARK: - Notifications

public nonisolated extension TextualPreferences {
	class func displayDockBadge() -> Bool {
		Preferences.Notifications.displayDockBadge.value
	}

	class func displayPublicMessageCountOnDockBadge() -> Bool {
		Preferences.Notifications.publicMessageCountOnDockBadge.value
	}

	class func postNotificationsWhileInFocus() -> Bool {
		Preferences.Notifications.postWhileInFocus.value
	}

	class func soundIsMuted() -> Bool {
		Preferences.Notifications.soundIsMuted.value
	}

	class func setSoundIsMuted(_ value: Bool) {
		Preferences.Notifications.soundIsMuted.value = value
	}

	class func key(for event: TXNotificationType, category: String) -> String? {
		guard let setting = NotificationSetting(rawValue: category) else {
			return nil
		}

		return event.preferenceKeyName(for: setting)
	}

	class func sound(for event: TXNotificationType) -> String? {
		Preferences.Notifications.sound(event).storedValue
	}

	class func setSound(_ value: String?, for event: TXNotificationType) {
		Preferences.Notifications.sound(event).storedValue = value
	}

	class func notificationEnabled(for event: TXNotificationType) -> Bool {
		Preferences.Notifications.flag(event, .enabled).value
	}

	class func setNotificationEnabled(_ value: Bool, for event: TXNotificationType) {
		Preferences.Notifications.flag(event, .enabled).value = value
	}

	class func disabledWhileAway(for event: TXNotificationType) -> Bool {
		Preferences.Notifications.flag(event, .disabledWhileAway).value
	}

	class func setDisabledWhileAway(_ value: Bool, for event: TXNotificationType) {
		Preferences.Notifications.flag(event, .disabledWhileAway).value = value
	}

	class func bounceDockIcon(for event: TXNotificationType) -> Bool {
		Preferences.Notifications.flag(event, .bounceDockIcon).value
	}

	class func setBounceDockIcon(_ value: Bool, for event: TXNotificationType) {
		Preferences.Notifications.flag(event, .bounceDockIcon).value = value
	}

	class func bounceDockIconRepeatedly(for event: TXNotificationType) -> Bool {
		Preferences.Notifications.flag(event, .bounceDockIconRepeatedly).value
	}

	class func setBounceDockIconRepeatedly(_ value: Bool, for event: TXNotificationType) {
		Preferences.Notifications.flag(event, .bounceDockIconRepeatedly).value = value
	}

	class func speak(_ event: TXNotificationType) -> Bool {
		Preferences.Notifications.flag(event, .speak).value
	}

	class func setEventIsSpoken(_ value: Bool, for event: TXNotificationType) {
		Preferences.Notifications.flag(event, .speak).value = value
	}

	class func onlySpeakEventsForSelection() -> Bool {
		Preferences.Notifications.onlySpeakForSelection.value
	}

	class func setOnlySpeakEventsForSelection(_ value: Bool) {
		Preferences.Notifications.onlySpeakForSelection.value = value
	}

	class func channelMessageSpeakChannelName() -> Bool {
		Preferences.Notifications.flag(.channelMessage, .speakChannelName).value
	}

	class func setChannelMessageSpeakChannelName(_ value: Bool) {
		Preferences.Notifications.flag(.channelMessage, .speakChannelName).value = value
	}

	class func channelMessageSpeakNickname() -> Bool {
		Preferences.Notifications.flag(.channelMessage, .speakNickname).value
	}

	class func setChannelMessageSpeakNickname(_ value: Bool) {
		Preferences.Notifications.flag(.channelMessage, .speakNickname).value = value
	}
}

// MARK: - Highlights

public nonisolated extension TextualPreferences {
	class func setHighlightCurrentNickname(_ value: Bool) {
		Preferences.Highlights.trackLocalNickname.value = value
	}

	class func highlightCurrentNickname() -> Bool {
		Preferences.Highlights.trackLocalNickname.value
	}

	class func highlightMatchingMethod() -> TXNicknameHighlightMatchType {
		Preferences.Highlights.matchingMethod.value
	}

	private class func loadKeywords(for key: PreferenceKey<[HighlightKeyword]>) -> [String] {
		key.value.map(\.string).filter { $0.isEmpty == false }
	}

	private class func reloadHighlightKeywords() {
		let match = loadKeywords(for: Preferences.Highlights.matchKeywords)
		let exclude = loadKeywords(for: Preferences.Highlights.excludeKeywords)

		highlightKeywords.withLock { keywords in
			keywords.match = match
			keywords.exclude = exclude
		}
	}

	class func loadExcludeKeywords() {
		let exclude = loadKeywords(for: Preferences.Highlights.excludeKeywords)

		highlightKeywords.withLock { $0.exclude = exclude }
	}

	class func loadMatchKeywords() {
		let match = loadKeywords(for: Preferences.Highlights.matchKeywords)

		highlightKeywords.withLock { $0.match = match }
	}

	private class func cleanKeywords(for key: PreferenceKey<[HighlightKeyword]>) {
		key.value = loadKeywords(for: key)
			.sorted { $0.caseInsensitiveCompare($1) == .orderedAscending }
			.map(HighlightKeyword.init(string:))
	}

	class func cleanUpHighlightKeywords() {
		cleanKeywords(for: Preferences.Highlights.matchKeywords)
		cleanKeywords(for: Preferences.Highlights.excludeKeywords)
	}

	class func highlightMatchKeywords() -> [String]? {
		highlightKeywords.withLock { $0.match }
	}

	class func highlightExcludeKeywords() -> [String]? {
		highlightKeywords.withLock { $0.exclude }
	}
}

// MARK: - Application

public nonisolated extension TextualPreferences {
	class func appNapEnabled() -> Bool {
		Preferences.Internals.appSleepDisabled.value == false
	}

	class func setAppNapEnabled(_ value: Bool) {
		Preferences.Internals.appSleepDisabled.value = (value == false)
	}

	class func registerWebKit2DynamicDefaults() {
		Preferences.Internals.webInspectorStartsAttached.value = false
	}

	class func registerPreferencesDictionaryVersion() {
		guard Preferences.Internals.dictionaryVersion.value < TPCPreferencesDictionaryVersion else {
			return
		}

		Preferences.Internals.dictionaryVersion.value = TPCPreferencesDictionaryVersion
	}

	class func defaultPreferences() -> [String: Any] {
		preferences.volatileDomain(forName: UserDefaults.registrationDomain)
	}

	class func registerDynamicDefaults() {
		populateDefaultNickname()
		registerWebKit2DynamicDefaults()
		registerPreferencesDictionaryVersion()
	}

	/** The registration domain is built from the key declarations rather than
	 read out of a plist, so a key that exists in the code always has a default
	 and a read of it cannot come back empty because a plist entry was renamed. */
	class func registerDefaults() {
		UserDefaults.standard.register(defaults: Preferences.registrationDomain(for: .standard))
		preferences.register(defaults: Preferences.registrationDomain(for: .container))
		registerDynamicDefaults()
	}

	class func initPreferences() {
		ApplicationInfo.incrementApplicationRunCount()
		registerDefaults()
		PathInfo.startUsingTranscriptFolderURL()
		highlightKeywordObservation.withLock { stored in
			stored = NotificationCenter.default.publisher(
				for: UserDefaults.didChangeNotification,
				object: preferences
			)
			.sink { _ in
				reloadHighlightKeywords()
			}
		}
		reloadHighlightKeywords()
	}
}
