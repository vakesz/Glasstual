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
	@IBAction func showChannelPropertiesSheet(_ sender: Any?) {
		dialog(.showChannelProperties, sender)
	}

	@IBAction func memberSendInvite(_ sender: Any?) {
		dialog(.sendInvite, sender)
	}

	@IBAction func showAddressBook(_ sender: Any?) {
		dialog(.showAddressBook, sender)
	}

	@IBAction func showIgnoreList(_ sender: Any?) {
		dialog(.showAddressBook, sender)
	}

	@IBAction func showOnboardingWindow(_ sender: Any?) {
		dialog(.showOnboarding, sender)
	}

	@IBAction func showAboutWindow(_ sender: Any?) {
		dialog(.showAbout, sender)
	}

	@IBAction func showServerPropertiesSheet(_ sender: Any?) {
		dialog(.showServerProperties, sender)
	}

	@IBAction func showServerHighlightList(_ sender: Any?) {
		dialog(.showServerHighlightList, sender)
	}

	@IBAction func showChannelModifyTopicSheet(_ sender: Any?) {
		dialog(.showChannelTopic, sender)
	}

	@IBAction func showChannelModifyModesSheet(_ sender: Any?) {
		dialog(.showChannelModes, sender)
	}

	@IBAction func showChannelSpotlightWindow(_ sender: Any?) {
		dialog(.showChannelSpotlight, sender)
	}

	@IBAction func showServerChangeNicknameSheet(_ sender: Any?) {
		dialog(.showChangeNickname, sender)
	}

	@IBAction func showPreferencesWindow(_ sender: Any?) {
		dialog(.showPreferences, sender)
	}

	@IBAction func showNotificationPreferences(_ sender: Any?) {
		dialog(.showNotificationPreferences, sender)
	}

	@IBAction func showStylePreferences(_ sender: Any?) {
		dialog(.showStylePreferences, sender)
	}

	@IBAction func showHiddenPreferences(_ sender: Any?) {
		dialog(.showHiddenPreferences, sender)
	}

	func showServerPropertiesSheet(for client: IRCClient, selection: UInt, context: Any?) {
		actionCoordinator.showServerProperties(for: client, selection: selection, context: context)
	}

	/** Named for its argument so that the member-list menu can own the plain
	 memberChangeColor: selector. */
	func showNicknameColorSheet(forNickname nickname: String) {
		actionCoordinator.showNicknameColorSheet(for: nickname)
	}

	func showPreferencesWindow(with selection: PreferencesControllerSelection) {
		let action: TXMenuDialogAction = switch selection {
		case .default: .showPreferences
		case .notifications: .showNotificationPreferences
		case .style: .showStylePreferences
		case .hiddenPreferences: .showHiddenPreferences
		}
		dialog(action, nil)
	}

	func channelPropertiesSheet(_ sender: ChannelPropertiesSheet, onOk config: ChannelConfig) {
		actionCoordinator.channelPropertiesDidAccept(sender, config: config)
	}

	func channelPropertiesSheetWillClose(_ sender: ChannelPropertiesSheet) {
		dialogDidClose(sender)
	}

	func channelInviteSheet(_ sender: ChannelInviteSheet, onSelectChannel channelName: String) {
		actionCoordinator.channelInviteDidSelect(sender, channelName: channelName)
	}

	func channelInviteSheetWillClose(_ sender: ChannelInviteSheet) {
		dialogDidClose(sender)
	}

	func onboardingWindowControllerWillClose(_ sender: OnboardingWindowController) {
		dialogDidClose(sender)
	}

	func aboutDialogWillClose(_ sender: AboutDialog) {
		dialogDidClose(sender)
	}

	func serverPropertiesSheet(_ sender: ServerPropertiesSheet, onOk config: IRCClientConfig) {
		actionCoordinator.serverPropertiesDidAccept(sender, config: config)
	}

	func serverPropertiesSheetWillClose(_ sender: ServerPropertiesSheet) {
		dialogDidClose(sender)
	}

	func serverHighlightListSheetWillClose(_ sender: ServerHighlightListSheet) {
		dialogDidClose(sender)
	}

	func nicknameColorSheetOnOk(_ sender: NicknameColorSheet) {
		actionCoordinator.nicknameColorDidAccept(sender)
	}

	func nicknameColorSheetWillClose(_ sender: NicknameColorSheet) {
		dialogDidClose(sender)
	}

	func channelModifyTopicSheet(_ sender: ChannelModifyTopicSheet, onOk topic: String) {
		actionCoordinator.channelTopicDidAccept(sender, topic: topic)
	}

	func channelModifyTopicSheetWillClose(_ sender: ChannelModifyTopicSheet) {
		dialogDidClose(sender)
	}

	func channelModifyModesSheet(_ sender: ChannelModifyModesSheet, onOk modes: ChannelModeContainer) {
		actionCoordinator.channelModesDidAccept(sender, modes: modes)
	}

	func channelModifyModesSheetWillClose(_ sender: ChannelModifyModesSheet) {
		dialogDidClose(sender)
	}

	func channelSpotlightController(_ sender: ChannelSpotlightController, selectChannel channel: IRCChannel) {
		actionCoordinator.channelSpotlightDidSelect(sender, channel: channel)
	}

	func channelSpotlightControllerWillClose(_ sender: ChannelSpotlightController) {
		dialogDidClose(sender)
	}

	func serverChangeNicknameSheet(_ sender: ServerChangeNicknameSheet, didInputNickname nickname: String) {
		actionCoordinator.serverNicknameDidAccept(sender, nickname: nickname)
	}

	func serverChangeNicknameSheetWillClose(_ sender: ServerChangeNicknameSheet) {
		dialogDidClose(sender)
	}

	func preferencesDialogWillClose(_ sender: PreferencesController) {
		actionCoordinator.preferencesDialogDidClose(sender)
	}

	private func dialog(_ action: TXMenuDialogAction, _ sender: Any?) {
		actionCoordinator.performDialogAction(action, sender: sender)
	}

	private func dialogDidClose(_ sender: Any) {
		actionCoordinator.dialogDidClose(sender)
	}
}

extension TXMenuController: AboutDialogDelegate, ChannelInviteSheetDelegate, ChannelModifyTopicSheetDelegate,
	ChannelModifyModesSheetDelegate, ChannelPropertiesSheetDelegate, ChannelSpotlightControllerDelegate,
	NicknameColorSheetDelegate, OnboardingWindowControllerDelegate, ServerChangeNicknameSheetDelegate,
	ServerHighlightListSheetDelegate, ServerPropertiesSheetDelegate
{}

@MainActor
@objc(TXMenuControllerMainWindowProxy)
public final class TXMenuControllerMainWindowProxy: NSObject {
	@IBAction public func showOnboardingWindow(_ sender: Any?) {
		AppController.shared.menuController?.showOnboardingWindow(sender)
	}
}
