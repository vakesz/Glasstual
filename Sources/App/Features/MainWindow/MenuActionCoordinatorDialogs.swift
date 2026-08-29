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

enum MenuDialogSelection {
	static let serverDefault: UInt = 0
	static let serverAddressBook: UInt = 1
	static let serverNewIgnoreEntry: UInt = 200
}

@MainActor
public extension MenuActionCoordinator {
	func performDialogAction(_ action: TXMenuDialogAction, sender: Any?) {
		switch action {
		case .showChannelProperties: showChannelProperties()
		case .sendInvite: showChannelInvite(sender)
		case .showAddressBook: showServerProperties(selection: MenuDialogSelection.serverAddressBook, context: nil)
		case .showOnboarding: showOnboarding()
		case .showAbout: showAbout()
		case .showServerProperties: showServerProperties(selection: MenuDialogSelection.serverDefault, context: nil)
		case .showServerHighlightList: showServerHighlightList()
		case .showChannelTopic: showChannelTopic()
		case .showChannelModes: showChannelModes()
		case .showChannelSpotlight: showChannelSpotlight()
		case .showChangeNickname: showChangeNickname()
		case .showPreferences: showPreferences(.default)
		case .showNotificationPreferences: showPreferences(.notifications)
		case .showStylePreferences: showPreferences(.style)
		case .showHiddenPreferences: showPreferences(.hiddenPreferences)
		@unknown default: break
		}
	}

	func showServerProperties(for client: IRCClient, selection: UInt, context: Any?) {
		presentServerProperties(for: client, selection: selection, context: context)
	}

	func showNicknameColorSheet(for nickname: String) {
		windowController.popMainWindowSheetIfExists()
		guard selectedClient != nil else { return }
		let sheet = NicknameColorSheet(nickname: nickname)
		present(sheet) { $0.start() }
	}

	private func showChannelProperties() {
		windowController.popMainWindowSheetIfExists()
		guard let channel = selectedChannel, channel.isChannel else { return }
		let sheet = ChannelPropertiesSheet(channel: channel)
		present(sheet) { $0.start() }
	}

	private func showChannelInvite(_ sender: Any?) {
		windowController.popMainWindowSheetIfExists()
		guard let client = selectedClient, let selectedChannel,
		      client.isLoggedIn, selectedChannel.isChannel, selectedChannel.isActive
		else { return }
		let nicknames = selectedNicknames(for: sender as Any)
		guard nicknames.isEmpty == false else { return }
		deselectMembers(for: sender as Any)
		let channels = client.channelList.compactMap { channel in
			channel !== selectedChannel && channel.isChannel ? channel.name : nil
		}
		guard channels.isEmpty == false else { return }
		let sheet = ChannelInviteSheet(nicknames: nicknames, on: client)
		present(sheet) { $0.start(withChannels: channels) }
	}

	private func showOnboarding() {
		guard windowController.maybeBringWindowForward("TDCOnboardingWindowController") == false else { return }
		windowController.popMainWindowSheetIfExists()
		let controller = OnboardingWindowController()
		present(controller) { $0.show() }
	}

	private func showAbout() {
		guard windowController.maybeBringWindowForward("TDCAboutDialog") == false else { return }
		let dialog = AboutDialog()
		present(dialog) { $0.show() }
	}

	private func showServerProperties(selection: UInt, context: Any?) {
		guard let client = selectedClient else { return }
		presentServerProperties(for: client, selection: selection, context: context)
	}

	private func presentServerProperties(for client: IRCClient, selection: UInt, context: Any?) {
		windowController.popMainWindowSheetIfExists()
		let sheet = ServerPropertiesSheet(client: client)
		present(sheet) { $0.start(withSelection: selection, context: context) }
	}

	private func showServerHighlightList() {
		windowController.popMainWindowSheetIfExists()
		guard let client = selectedClient else { return }
		let sheet = ServerHighlightListSheet(client: client)
		present(sheet) { $0.start() }
	}

	private func showChannelTopic() {
		windowController.popMainWindowSheetIfExists()
		guard let channel = selectedChannel, channel.isChannel else { return }
		let sheet = ChannelModifyTopicSheet(channel: channel)
		present(sheet) { $0.start() }
	}

	private func showChannelModes() {
		windowController.popMainWindowSheetIfExists()
		guard let channel = selectedChannel, channel.isChannel else { return }
		let sheet = ChannelModifyModesSheet(channel: channel)
		present(sheet) { $0.start() }
	}

	private func showChannelSpotlight() {
		guard windowController.maybeBringWindowForward("TDCChannelSpotlightController") == false else { return }
		let dialog = ChannelSpotlightController()
		present(dialog) { $0.show() }
	}

	private func showChangeNickname() {
		windowController.popMainWindowSheetIfExists()
		guard let client = selectedClient, client.isLoggedIn else { return }
		let sheet = ServerChangeNicknameSheet(client: client)
		present(sheet) { $0.start() }
	}

	private func showPreferences(_ selection: PreferencesControllerSelection) {
		if let controller = windowController
			.window(fromWindowList: "TDCPreferencesController") as? PreferencesController
		{
			controller.show(selection)
			return
		}
		let controller = PreferencesController()
		present(controller) { $0.show(selection) }
	}
}
