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
	@objc func showChannelPropertiesSheet(_ sender: Any?) {
		dialog(.showChannelProperties, sender)
	}

	@objc func memberSendInvite(_ sender: Any?) {
		dialog(.sendInvite, sender)
	}

	@objc func showAddressBook(_ sender: Any?) {
		dialog(.showAddressBook, sender)
	}

	@objc func showIgnoreList(_ sender: Any?) {
		dialog(.showAddressBook, sender)
	}

	@objc func showOnboardingWindow(_ sender: Any?) {
		dialog(.showOnboarding, sender)
	}

	@objc func showAboutWindow(_ sender: Any?) {
		dialog(.showAbout, sender)
	}

	@objc func showServerPropertiesSheet(_ sender: Any?) {
		dialog(.showServerProperties, sender)
	}

	@objc func showServerHighlightList(_ sender: Any?) {
		dialog(.showServerHighlightList, sender)
	}

	@objc func showChannelModifyTopicSheet(_ sender: Any?) {
		dialog(.showChannelTopic, sender)
	}

	@objc func showChannelModifyModesSheet(_ sender: Any?) {
		dialog(.showChannelModes, sender)
	}

	@objc func showChannelSpotlightWindow(_ sender: Any?) {
		dialog(.showChannelSpotlight, sender)
	}

	@objc func showServerChangeNicknameSheet(_ sender: Any?) {
		dialog(.showChangeNickname, sender)
	}

	@objc func showPreferencesWindow(_ sender: Any?) {
		dialog(.showPreferences, sender)
	}

	func showNotificationPreferences(_ sender: Any?) {
		dialog(.showNotificationPreferences, sender)
	}

	func showStylePreferences(_ sender: Any?) {
		dialog(.showStylePreferences, sender)
	}

	@objc func showHiddenPreferences(_ sender: Any?) {
		dialog(.showHiddenPreferences, sender)
	}

	internal func showServerPropertiesSheet(
		for client: IRCClient,
		selection: ServerPropertiesDestination,
		context: Any?
	) {
		actionCoordinator.showServerProperties(for: client, selection: selection, context: context)
	}

	/** Named for its argument so that the member-list menu can own the plain
	 memberChangeColor: selector. */
	func showNicknameColorSheet(forNickname nickname: String) {
		actionCoordinator.showNicknameColorSheet(for: nickname)
	}

	func showPreferencesWindow(with selection: PreferencesSceneSelection) {
		let action: MenuDialogAction = switch selection {
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

	func channelPropertiesSheetWillClose(_: ChannelPropertiesSheet) {}

	func channelInviteSheet(_ sender: ChannelInviteSheet, onSelectChannel channelName: String) {
		actionCoordinator.channelInviteDidSelect(sender, channelName: channelName)
	}

	func channelInviteSheetWillClose(_: ChannelInviteSheet) {}

	func serverPropertiesSheet(_ sender: ServerPropertiesSheet, onOk config: IRCClientConfig) {
		actionCoordinator.serverPropertiesDidAccept(sender, config: config)
	}

	func serverPropertiesSheetWillClose(_: ServerPropertiesSheet) {}

	func serverHighlightListSheetWillClose(_: ServerHighlightListSheet) {}

	func nicknameColorSheetOnOk(_ sender: NicknameColorSheet) {
		actionCoordinator.nicknameColorDidAccept(sender)
	}

	func nicknameColorSheetWillClose(_: NicknameColorSheet) {}

	func channelModifyTopicSheet(_ sender: ChannelModifyTopicSheet, onOk topic: String) {
		actionCoordinator.channelTopicDidAccept(sender, topic: topic)
	}

	func channelModifyTopicSheetWillClose(_: ChannelModifyTopicSheet) {}

	func channelModifyModesSheet(_ sender: ChannelModifyModesSheet, onOk modes: ChannelModeContainer) {
		actionCoordinator.channelModesDidAccept(sender, modes: modes)
	}

	func channelModifyModesSheetWillClose(_: ChannelModifyModesSheet) {}

	func serverChangeNicknameSheet(_ sender: ServerChangeNicknameSheet, didInputNickname nickname: String) {
		actionCoordinator.serverNicknameDidAccept(sender, nickname: nickname)
	}

	func serverChangeNicknameSheetWillClose(_: ServerChangeNicknameSheet) {}

	private func dialog(_ action: MenuDialogAction, _ sender: Any?) {
		actionCoordinator.performDialogAction(action, sender: sender)
	}
}

extension MenuController: ChannelInviteSheetDelegate, ChannelModifyTopicSheetDelegate,
	ChannelModifyModesSheetDelegate, ChannelPropertiesSheetDelegate,
	NicknameColorSheetDelegate, ServerChangeNicknameSheetDelegate,
	ServerHighlightListSheetDelegate, ServerPropertiesSheetDelegate
{}
