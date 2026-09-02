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
public extension MenuController {
	@objc func showFindPrompt(_ sender: Any?) {
		edit(.showFindPrompt, sender)
	}

	@objc func paste(_ sender: Any?) {
		edit(.paste, sender)
	}

	@objc func print(_ sender: Any?) {
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

	@objc func replyToMessage(_ sender: Any?) {
		channelView(.reply, sender)
	}

	@objc func reactToMessage(_ sender: Any?) {
		channelView(.react, sender)
	}

	@objc func reactToMessageWithOtherEmoji(_ sender: Any?) {
		channelView(.reactWithOtherEmoji, sender)
	}

	@objc func markScrollback(_ sender: Any?) {
		channelView(.markScrollback, sender)
	}

	@objc func gotoScrollbackMarker(_ sender: Any?) {
		channelView(.goToScrollbackMarker, sender)
	}

	@objc func clearScrollback(_ sender: Any?) {
		channelView(.clearScrollback, sender)
	}

	@objc func increaseLogFontSize(_ sender: Any?) {
		channelView(.increaseFontSize, sender)
	}

	@objc func decreaseLogFontSize(_ sender: Any?) {
		channelView(.decreaseFontSize, sender)
	}

	@objc func searchGoogle(_ sender: Any?) {
		channelView(.searchWeb, sender)
	}

	@objc func lookUpInDictionary(_ sender: Any?) {
		channelView(.lookUpInDictionary, sender)
	}

	@objc func copyUrl(_ sender: Any?) {
		channelView(.copyURL, sender)
	}

	@objc func connect(_ sender: Any?) {
		serverChannel(.connect, sender)
	}

	@objc func connectBypassingProxy(_ sender: Any?) {
		serverChannel(.connectBypassingProxy, sender)
	}

	@objc func disconnect(_ sender: Any?) {
		serverChannel(.disconnect, sender)
	}

	@objc func cancelReconnection(_ sender: Any?) {
		serverChannel(.cancelReconnection, sender)
	}

	@objc func showServerChannelList(_ sender: Any?) {
		serverChannel(.showChannelList, sender)
	}

	@objc func addServer(_ sender: Any?) {
		serverChannel(.addServer, sender)
	}

	@objc func duplicateServer(_ sender: Any?) {
		serverChannel(.duplicateServer, sender)
	}

	@objc func deleteServer(_ sender: Any?) {
		serverChannel(.deleteServer, sender)
	}

	@objc func joinChannel(_ sender: Any?) {
		serverChannel(.joinChannel, sender)
	}

	@objc func leaveChannel(_ sender: Any?) {
		serverChannel(.leaveChannel, sender)
	}

	@objc func addChannel(_ sender: Any?) {
		serverChannel(.addChannel, sender)
	}

	@objc func deleteChannel(_ sender: Any?) {
		serverChannel(.deleteChannel, sender)
	}

	@objc func copyUniqueIdentifier(_ sender: Any?) {
		serverChannel(.copyUniqueIdentifier, sender)
	}

	@objc func joinChannelClicked(_ sender: Any?) {
		serverChannel(.joinClickedChannel, sender)
	}

	func shareMenuItem(for items: [Any]) -> NSMenuItem {
		actionCoordinator.shareMenuItem(for: items)
	}

	@nonobjc
	func shareMenuItem(forItems items: [Any]) -> NSMenuItem {
		shareMenuItem(for: items)
	}

	@objc func memberAddIgnore(_ sender: Any?) {
		member(.addIgnore, sender)
	}

	@objc func memberRemoveIgnore(_ sender: Any?) {
		member(.removeIgnore, sender)
	}

	@objc func memberModifyIgnore(_ sender: Any?) {
		member(.modifyIgnore, sender)
	}

	func memberInMemberListDoubleClicked(_ sender: Any) {
		member(.memberListDoubleClick, sender)
	}

	func memberInChannelViewDoubleClicked(_ sender: Any?) {
		member(.channelViewDoubleClick, sender)
	}

	func memberInsertNameIntoTextField(_ sender: Any) {
		member(.insertNickname, sender)
	}

	@objc func memberSendWhois(_ sender: Any?) {
		member(.whois, sender)
	}

	@objc func memberStartPrivateMessage(_ sender: Any?) {
		member(.privateMessage, sender)
	}

	@objc func memberChangeColor(_ sender: Any?) {
		member(.changeColor, sender)
	}

	@objc func memberSendCTCPPing(_ sender: Any?) {
		member(.ctcpPing, sender)
	}

	@objc func memberSendCTCPFinger(_ sender: Any?) {
		member(.ctcpFinger, sender)
	}

	@objc func memberSendCTCPTime(_ sender: Any?) {
		member(.ctcpTime, sender)
	}

	@objc func memberSendCTCPVersion(_ sender: Any?) {
		member(.ctcpVersion, sender)
	}

	@objc func memberSendCTCPUserinfo(_ sender: Any?) {
		member(.ctcpUserinfo, sender)
	}

	@objc func memberSendCTCPClientInfo(_ sender: Any?) {
		member(.ctcpClientInfo, sender)
	}

	@objc func memberModeGiveOp(_ sender: Any?) {
		member(.giveOp, sender)
	}

	@objc func memberModeTakeOp(_ sender: Any?) {
		member(.takeOp, sender)
	}

	@objc func memberModeGiveHalfop(_ sender: Any?) {
		member(.giveHalfop, sender)
	}

	@objc func memberModeTakeHalfop(_ sender: Any?) {
		member(.takeHalfop, sender)
	}

	@objc func memberModeGiveVoice(_ sender: Any?) {
		member(.giveVoice, sender)
	}

	@objc func memberModeTakeVoice(_ sender: Any?) {
		member(.takeVoice, sender)
	}

	@objc func memberKickFromChannel(_ sender: Any?) {
		member(.kick, sender)
	}

	@objc func memberBanFromChannel(_ sender: Any?) {
		member(.ban, sender)
	}

	@objc func memberKickbanFromChannel(_ sender: Any?) {
		member(.kickban, sender)
	}

	@objc func memberKillFromServer(_ sender: Any?) {
		member(.kill, sender)
	}

	@objc func memberBanFromServer(_ sender: Any?) {
		member(.gline, sender)
	}

	@objc func memberShunOnServer(_ sender: Any?) {
		member(.shun, sender)
	}

	@objc func showSetVhostPrompt(_ sender: Any?) {
		member(.setVhost, sender)
	}

	@objc func memberSendFileRequest(_ sender: Any?) {
		member(.sendFile, sender)
	}

	var fileTransferCenter: FileTransferCenter {
		SharedApplication.sharedFileTransferCenter()
	}

	@objc func showFileTransfersWindow(_: Any?) {
		fileTransferCenter.present()
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

	@objc func openLogLocation(_ sender: Any?) {
		support(.openLogLocation, sender)
	}

	@objc func openChannelLogs(_ sender: Any?) {
		support(.openChannelLogs, sender)
	}

	@objc func openAcknowledgements(_ sender: Any?) {
		support(.openAcknowledgements, sender)
	}

	@objc func connectToGlasstualHelpChannel(_ sender: Any?) {
		support(.connectToHelpChannel, sender)
	}

	@objc func connectToGlasstualTestingChannel(_ sender: Any?) {
		support(.connectToTestingChannel, sender)
	}

	@objc func showChannelBanList(_ sender: Any?) {
		irc(.showBanList, sender)
	}

	@objc func showChannelBanExceptionList(_ sender: Any?) {
		irc(.showBanExceptionList, sender)
	}

	@objc func showChannelInviteExceptionList(_ sender: Any?) {
		irc(.showInviteExceptionList, sender)
	}

	@objc func showChannelQuietList(_ sender: Any?) {
		irc(.showQuietList, sender)
	}

	@objc func toggleChannelModerationMode(_ sender: Any?) {
		irc(.toggleModerationMode, sender)
	}

	@objc func toggleChannelInviteMode(_ sender: Any?) {
		irc(.toggleInviteMode, sender)
	}

	@objc func closeWindow(_ sender: Any?) {
		window(.close, sender)
	}

	@objc func showMainWindow(_ sender: Any?) {
		window(.showMainWindow, sender)
	}

	@objc func centerMainWindow(_ sender: Any?) {
		window(.centerMainWindow, sender)
	}

	@objc func resetMainWindowFrame(_ sender: Any?) {
		window(.resetMainWindowFrame, sender)
	}

	@objc func sortChannelListNames(_ sender: Any?) {
		window(.sortChannelList, sender)
	}

	@objc func focusSearchField(_ sender: Any?) {
		window(.focusSearchField, sender)
	}

	@objc func markAllAsRead(_ sender: Any?) {
		window(.markAllAsRead, sender)
	}

	@objc func importPreferences(_ sender: Any?) {
		window(.importPreferences, sender)
	}

	@objc func exportPreferences(_ sender: Any?) {
		window(.exportPreferences, sender)
	}

	func toggleMuteOnNotificationsShortcut(on: Bool) {
		actionCoordinator.setNotificationsMuted(on)
	}

	func toggleMuteOnNotificationSoundsShortcut(on: Bool) {
		actionCoordinator.setNotificationSoundsMuted(on)
	}

	@objc func toggleMuteOnNotificationSounds(_ sender: Any?) {
		window(.toggleNotificationSounds, sender)
	}

	@objc func toggleMuteOnNotifications(_ sender: Any?) {
		window(.toggleNotifications, sender)
	}

	@objc func toggleMainWindowAppearance(_ sender: Any?) {
		window(.toggleAppearance, sender)
	}

	@objc func toggleServerListVisibility(_ sender: Any?) {
		window(.toggleServerList, sender)
	}

	@objc func toggleMemberListVisibility(_ sender: Any?) {
		window(.toggleMemberList, sender)
	}

	@objc func toggleDeveloperMode(_ sender: Any?) {
		window(.toggleDeveloperMode, sender)
	}

	@objc func resetDoNotAskMePopupWarnings(_ sender: Any?) {
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

	@objc func performNavigationAction(_ sender: Any?) {
		actionCoordinator.performNavigationAction(sender)
	}

	@objc func onNextHighlight(_: Any?) {
		actionCoordinator.moveHighlightOrScrollback(for: .nextHighlight)
	}

	@objc func onPreviousHighlight(_: Any?) {
		actionCoordinator.moveHighlightOrScrollback(for: .previousHighlight)
	}

	@objc func jumpToCurrentSession(_: Any?) {
		actionCoordinator.moveHighlightOrScrollback(for: .jumpToCurrentSession)
	}

	@objc func jumpToPresent(_: Any?) {
		actionCoordinator.moveHighlightOrScrollback(for: .jumpToPresent)
	}

	private func edit(_ action: MenuEditingAction, _ sender: Any?) {
		actionCoordinator.performEditingAction(action, sender: sender)
	}

	private func channelView(_ action: MenuChannelViewAction, _ sender: Any?) {
		actionCoordinator.performChannelViewAction(action, sender: sender)
	}

	private func serverChannel(_ action: MenuServerChannelAction, _ sender: Any?) {
		actionCoordinator.performServerChannelAction(action, sender: sender)
	}

	private func member(_ action: MenuMemberAction, _ sender: Any?) {
		actionCoordinator.performMemberAction(action, sender: sender)
	}

	func performMemberAction(_ action: MenuMemberAction, sender: Any?) {
		member(action, sender)
	}

	private func support(_ action: MenuSupportAction, _ sender: Any?) {
		actionCoordinator.performSupportAction(action, sender: sender)
	}

	private func irc(_ action: MenuIRCAction, _ sender: Any?) {
		actionCoordinator.performIRCAction(action, sender: sender)
	}

	private func window(_ action: MenuWindowAction, _ sender: Any?) {
		actionCoordinator.performWindowAction(action, sender: sender)
	}
}
