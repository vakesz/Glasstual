/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
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

@MainActor
public extension TXMenuController {
	@IBAction func showFindPrompt(_ sender: Any?) {
		edit(.showFindPrompt, sender)
	}

	@IBAction func copy(_ sender: Any?) {
		edit(.copy, sender)
	}

	@IBAction func paste(_ sender: Any?) {
		edit(.paste, sender)
	}

	@IBAction func print(_ sender: Any?) {
		edit(.print, sender)
	}

	func messageReplyMenuItems(messageIdentifier: String, nickname: String?, excerpt: String?) -> [NSMenuItem] {
		actionCoordinator.messageReplyItems(
			messageIdentifier: messageIdentifier,
			nickname: nickname,
			excerpt: excerpt
		)
	}

	@nonobjc
	func messageReplyMenuItems(
		forMessageIdentifier messageIdentifier: String,
		nickname: String?,
		excerpt: String?
	) -> [NSMenuItem] {
		messageReplyMenuItems(messageIdentifier: messageIdentifier, nickname: nickname, excerpt: excerpt)
	}

	@IBAction func replyToMessage(_ sender: Any?) {
		channelView(.reply, sender)
	}

	@IBAction func reactToMessage(_ sender: Any?) {
		channelView(.react, sender)
	}

	@IBAction func reactToMessageWithOtherEmoji(_ sender: Any?) {
		channelView(.reactWithOtherEmoji, sender)
	}

	@IBAction func copyLogAsHtml(_ sender: Any?) {
		channelView(.copyLogAsHTML, sender)
	}

	@IBAction func openWebInspector(_ sender: Any?) {
		channelView(.openWebInspector, sender)
	}

	@IBAction func markScrollback(_ sender: Any?) {
		channelView(.markScrollback, sender)
	}

	@IBAction func gotoScrollbackMarker(_ sender: Any?) {
		channelView(.goToScrollbackMarker, sender)
	}

	@IBAction func clearScrollback(_ sender: Any?) {
		channelView(.clearScrollback, sender)
	}

	@IBAction func increaseLogFontSize(_ sender: Any?) {
		channelView(.increaseFontSize, sender)
	}

	@IBAction func decreaseLogFontSize(_ sender: Any?) {
		channelView(.decreaseFontSize, sender)
	}

	@IBAction func searchGoogle(_ sender: Any?) {
		channelView(.searchWeb, sender)
	}

	@IBAction func lookUpInDictionary(_ sender: Any?) {
		channelView(.lookUpInDictionary, sender)
	}

	@IBAction func copyUrl(_ sender: Any?) {
		channelView(.copyURL, sender)
	}

	@IBAction func connect(_ sender: Any?) {
		serverChannel(.connect, sender)
	}

	@IBAction func connectBypassingProxy(_ sender: Any?) {
		serverChannel(.connectBypassingProxy, sender)
	}

	@IBAction func disconnect(_ sender: Any?) {
		serverChannel(.disconnect, sender)
	}

	@IBAction func cancelReconnection(_ sender: Any?) {
		serverChannel(.cancelReconnection, sender)
	}

	@IBAction func showServerChannelList(_ sender: Any?) {
		serverChannel(.showChannelList, sender)
	}

	@IBAction func addServer(_ sender: Any?) {
		serverChannel(.addServer, sender)
	}

	@IBAction func duplicateServer(_ sender: Any?) {
		serverChannel(.duplicateServer, sender)
	}

	@IBAction func deleteServer(_ sender: Any?) {
		serverChannel(.deleteServer, sender)
	}

	@IBAction func joinChannel(_ sender: Any?) {
		serverChannel(.joinChannel, sender)
	}

	@IBAction func leaveChannel(_ sender: Any?) {
		serverChannel(.leaveChannel, sender)
	}

	@IBAction func addChannel(_ sender: Any?) {
		serverChannel(.addChannel, sender)
	}

	@IBAction func deleteChannel(_ sender: Any?) {
		serverChannel(.deleteChannel, sender)
	}

	@IBAction func copyUniqueIdentifier(_ sender: Any?) {
		serverChannel(.copyUniqueIdentifier, sender)
	}

	@IBAction func joinChannelClicked(_ sender: Any?) {
		serverChannel(.joinClickedChannel, sender)
	}

	@IBAction func emptyAction(_ sender: Any?) {
		serverChannel(.empty, sender)
	}

	func shareMenuItem(for items: [Any]) -> NSMenuItem {
		actionCoordinator.shareMenuItem(for: items)
	}

	@nonobjc
	func shareMenuItem(forItems items: [Any]) -> NSMenuItem {
		shareMenuItem(for: items)
	}

	@IBAction func memberAddIgnore(_ sender: Any?) {
		member(.addIgnore, sender)
	}

	@IBAction func memberRemoveIgnore(_ sender: Any?) {
		member(.removeIgnore, sender)
	}

	@IBAction func memberModifyIgnore(_ sender: Any?) {
		member(.modifyIgnore, sender)
	}

	@objc func memberInMemberListDoubleClicked(_ sender: Any) {
		member(.memberListDoubleClick, sender)
	}

	@IBAction func memberInChannelViewDoubleClicked(_ sender: Any?) {
		member(.channelViewDoubleClick, sender)
	}

	func memberInsertNameIntoTextField(_ sender: Any) {
		member(.insertNickname, sender)
	}

	@IBAction func memberSendWhois(_ sender: Any?) {
		member(.whois, sender)
	}

	func whoisSelectedMembers(_ sender: Any) {
		member(.whois, sender)
	}

	@IBAction func memberStartPrivateMessage(_ sender: Any?) {
		member(.privateMessage, sender)
	}

	@IBAction func memberChangeColor(_ sender: Any?) {
		member(.changeColor, sender)
	}

	@IBAction func memberSendCTCPPing(_ sender: Any?) {
		member(.ctcpPing, sender)
	}

	@IBAction func memberSendCTCPFinger(_ sender: Any?) {
		member(.ctcpFinger, sender)
	}

	@IBAction func memberSendCTCPTime(_ sender: Any?) {
		member(.ctcpTime, sender)
	}

	@IBAction func memberSendCTCPVersion(_ sender: Any?) {
		member(.ctcpVersion, sender)
	}

	@IBAction func memberSendCTCPUserinfo(_ sender: Any?) {
		member(.ctcpUserinfo, sender)
	}

	@IBAction func memberSendCTCPClientInfo(_ sender: Any?) {
		member(.ctcpClientInfo, sender)
	}

	@IBAction func memberModeGiveOp(_ sender: Any?) {
		member(.giveOp, sender)
	}

	@IBAction func memberModeTakeOp(_ sender: Any?) {
		member(.takeOp, sender)
	}

	@IBAction func memberModeGiveHalfop(_ sender: Any?) {
		member(.giveHalfop, sender)
	}

	@IBAction func memberModeTakeHalfop(_ sender: Any?) {
		member(.takeHalfop, sender)
	}

	@IBAction func memberModeGiveVoice(_ sender: Any?) {
		member(.giveVoice, sender)
	}

	@IBAction func memberModeTakeVoice(_ sender: Any?) {
		member(.takeVoice, sender)
	}

	@IBAction func memberKickFromChannel(_ sender: Any?) {
		member(.kick, sender)
	}

	@IBAction func memberBanFromChannel(_ sender: Any?) {
		member(.ban, sender)
	}

	@IBAction func memberKickbanFromChannel(_ sender: Any?) {
		member(.kickban, sender)
	}

	@IBAction func memberKillFromServer(_ sender: Any?) {
		member(.kill, sender)
	}

	@IBAction func memberBanFromServer(_ sender: Any?) {
		member(.gline, sender)
	}

	@IBAction func memberShunOnServer(_ sender: Any?) {
		member(.shun, sender)
	}

	@IBAction func showSetVhostPrompt(_ sender: Any?) {
		member(.setVhost, sender)
	}

	@IBAction func memberSendFileRequest(_ sender: Any?) {
		member(.sendFile, sender)
	}

	var fileTransferController: TDCFileTransferDialog {
		SharedApplication.sharedFileTransferDialog()
	}

	@IBAction func showFileTransfersWindow(_: Any?) {
		fileTransferController.show(true, restorePosition: true)
	}

	func memberSendDroppedFiles(toSelectedChannel files: [String]) {
		actionCoordinator.sendDroppedFilesToSelectedChannel(files)
	}

	func memberSendDroppedFiles(_ files: [String], row: UInt) {
		actionCoordinator.sendDroppedFiles(files, row: row)
	}

	func memberSendDroppedFiles(_ files: [String], to nickname: String) {
		actionCoordinator.sendDroppedFiles(files, nickname: nickname)
	}

	@IBAction func openLogLocation(_ sender: Any?) {
		support(.openLogLocation, sender)
	}

	@IBAction func openChannelLogs(_ sender: Any?) {
		support(.openChannelLogs, sender)
	}

	@IBAction func openAcknowledgements(_ sender: Any?) {
		support(.openAcknowledgements, sender)
	}

	@IBAction func contactSupport(_ sender: Any?) {
		support(.contactSupport, sender)
	}

	@IBAction func connectToGlasstualHelpChannel(_ sender: Any?) {
		support(.connectToHelpChannel, sender)
	}

	@IBAction func connectToGlasstualTestingChannel(_ sender: Any?) {
		support(.connectToTestingChannel, sender)
	}

	@IBAction func showChannelBanList(_ sender: Any?) {
		irc(.showBanList, sender)
	}

	@IBAction func showChannelBanExceptionList(_ sender: Any?) {
		irc(.showBanExceptionList, sender)
	}

	@IBAction func showChannelInviteExceptionList(_ sender: Any?) {
		irc(.showInviteExceptionList, sender)
	}

	@IBAction func showChannelQuietList(_ sender: Any?) {
		irc(.showQuietList, sender)
	}

	@IBAction func toggleChannelModerationMode(_ sender: Any?) {
		irc(.toggleModerationMode, sender)
	}

	@IBAction func toggleChannelInviteMode(_ sender: Any?) {
		irc(.toggleInviteMode, sender)
	}

	@IBAction func closeWindow(_ sender: Any?) {
		window(.close, sender)
	}

	@IBAction func showMainWindow(_ sender: Any?) {
		window(.showMainWindow, sender)
	}

	@IBAction func centerMainWindow(_ sender: Any?) {
		window(.centerMainWindow, sender)
	}

	@IBAction func resetMainWindowFrame(_ sender: Any?) {
		window(.resetMainWindowFrame, sender)
	}

	@IBAction func sortChannelListNames(_ sender: Any?) {
		window(.sortChannelList, sender)
	}

	@IBAction func markAllAsRead(_ sender: Any?) {
		window(.markAllAsRead, sender)
	}

	@IBAction func importPreferences(_ sender: Any?) {
		window(.importPreferences, sender)
	}

	@IBAction func exportPreferences(_ sender: Any?) {
		window(.exportPreferences, sender)
	}

	func toggleMuteOnNotificationsShortcut(on: Bool) {
		actionCoordinator.setNotificationsMuted(on)
	}

	func toggleMuteOnNotificationSoundsShortcut(on: Bool) {
		actionCoordinator.setNotificationSoundsMuted(on)
	}

	@IBAction func toggleMuteOnNotificationSounds(_ sender: Any?) {
		window(.toggleNotificationSounds, sender)
	}

	@IBAction func toggleMuteOnNotifications(_ sender: Any?) {
		window(.toggleNotifications, sender)
	}

	@IBAction func resetMainWindowAppearance(_ sender: Any?) {
		window(.resetAppearance, sender)
	}

	@IBAction func toggleMainWindowAppearance(_ sender: Any?) {
		window(.toggleAppearance, sender)
	}

	@IBAction func toggleServerListVisibility(_ sender: Any?) {
		window(.toggleServerList, sender)
	}

	@IBAction func toggleMemberListVisibility(_ sender: Any?) {
		window(.toggleMemberList, sender)
	}

	@IBAction func forceReloadTheme(_ sender: Any?) {
		window(.reloadTheme, sender)
	}

	@IBAction func toggleDeveloperMode(_ sender: Any?) {
		window(.toggleDeveloperMode, sender)
	}

	@IBAction func resetDoNotAskMePopupWarnings(_ sender: Any?) {
		window(.resetSuppressedWarnings, sender)
	}

	func navigateToTreeItem(at url: URL) {
		actionCoordinator.navigateToTreeItem(at: url)
	}

	func navigateToTreeItem(withIdentifier identifier: String) {
		actionCoordinator.navigateToTreeItem(withIdentifier: identifier)
	}

	func navigateToTreeItem(_ item: IRCTreeItem) {
		actionCoordinator.navigateToTreeItem(item)
	}

	func populateNavigationChannelList() {
		actionCoordinator.populateNavigationChannelList()
	}

	@objc func navigateToChannelInNavigationList(_ sender: NSMenuItem) {
		actionCoordinator.navigateToChannelInNavigationList(sender)
	}

	@IBAction func performNavigationAction(_ sender: Any?) {
		actionCoordinator.performNavigationAction(sender)
	}

	@IBAction func onNextHighlight(_: Any?) {
		actionCoordinator.moveHighlightOrScrollback(forTag: MenuNavigationTag.nextHighlight)
	}

	@IBAction func onPreviousHighlight(_: Any?) {
		actionCoordinator.moveHighlightOrScrollback(forTag: MenuNavigationTag.previousHighlight)
	}

	@IBAction func jumpToCurrentSession(_: Any?) {
		actionCoordinator.moveHighlightOrScrollback(forTag: MenuNavigationTag.jumpToCurrentSession)
	}

	@IBAction func jumpToPresent(_: Any?) {
		actionCoordinator.moveHighlightOrScrollback(forTag: MenuNavigationTag.jumpToPresent)
	}

	private func edit(_ action: TXMenuEditingAction, _ sender: Any?) {
		actionCoordinator.performEditingAction(action, sender: sender)
	}

	private func channelView(_ action: TXMenuChannelViewAction, _ sender: Any?) {
		actionCoordinator.performChannelViewAction(action, sender: sender)
	}

	private func serverChannel(_ action: TXMenuServerChannelAction, _ sender: Any?) {
		actionCoordinator.performServerChannelAction(action, sender: sender)
	}

	private func member(_ action: TXMenuMemberAction, _ sender: Any?) {
		actionCoordinator.performMemberAction(action, sender: sender)
	}

	private func support(_ action: TXMenuSupportAction, _ sender: Any?) {
		actionCoordinator.performSupportAction(action, sender: sender)
	}

	private func irc(_ action: TXMenuIRCAction, _ sender: Any?) {
		actionCoordinator.performIRCAction(action, sender: sender)
	}

	private func window(_ action: TXMenuWindowAction, _ sender: Any?) {
		actionCoordinator.performWindowAction(action, sender: sender)
	}
}
