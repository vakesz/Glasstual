/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
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

// MARK: - Sheets, panels and windows

public extension MenuActionCoordinator {
	@objc func showChannelPropertiesSheet(_: Any?) {
		mainWindow.presentationModel.closePresentedSheet()
		guard let channel = selectedChannel, channel.isChannel else { return }
		present(ChannelPropertiesSheet(channel: channel)) { $0.start() }
	}

	@objc func memberSendInvite(_ sender: Any?) {
		mainWindow.presentationModel.closePresentedSheet()
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
		present(ChannelInviteSheet(nicknames: nicknames, on: client)) { $0.start(withChannels: channels) }
	}

	@objc func showAddressBook(_: Any?) {
		showServerProperties(selection: .addressBook)
	}

	@objc func showOnboardingWindow(_: Any?) {
		mainWindow.presentationModel.closePresentedSheet()
		SharedApplication.sharedApplicationScenes().openOnboarding()
	}

	@objc func showAboutWindow(_: Any?) {
		SharedApplication.sharedApplicationScenes().openAbout()
	}

	@objc func showServerPropertiesSheet(_: Any?) {
		showServerProperties(selection: .default)
	}

	/// A window rather than a sheet: the list exists to jump into the transcript
	/// with, and a sheet had to be dismissed to get there and reopened for the
	/// next highlight.
	@objc func showServerHighlightList(_: Any?) {
		guard let client = selectedClient else { return }
		SharedApplication.sharedApplicationScenes().openServerHighlightList(for: client)
	}

	@objc func showChannelModifyTopicSheet(_: Any?) {
		mainWindow.presentationModel.closePresentedSheet()
		guard let channel = selectedChannel, channel.isChannel else { return }
		present(ChannelModifyTopicSheet(channel: channel)) { $0.start() }
	}

	@objc func showChannelModifyModesSheet(_: Any?) {
		mainWindow.presentationModel.closePresentedSheet()
		guard let channel = selectedChannel, channel.isChannel else { return }
		present(ChannelModifyModesSheet(channel: channel)) { $0.start() }
	}

	@objc func showChannelSpotlightWindow(_: Any?) {
		SharedApplication.sharedApplicationScenes().openChannelSpotlight()
	}

	@objc func showServerChangeNicknameSheet(_: Any?) {
		mainWindow.presentationModel.closePresentedSheet()
		guard let client = selectedClient, client.isLoggedIn else { return }
		present(ServerChangeNicknameSheet(client: client)) { $0.start() }
	}

	@objc func showPreferencesWindow(_: Any?) {
		showPreferences(.default)
	}

	@objc func showHiddenPreferences(_: Any?) {
		showPreferences(.hiddenPreferences)
	}

	func showNotificationPreferences(_: Any?) {
		showPreferences(.notifications)
	}

	func showPreferencesWindow(with selection: PreferencesSceneSelection) {
		showPreferences(selection)
	}

	@objc func showFileTransfersWindow(_: Any?) {
		fileTransferCenter.present()
	}

	internal func showServerProperties(for client: IRCClient, selection: ServerPropertiesDestination) {
		mainWindow.presentationModel.closePresentedSheet()
		present(ServerPropertiesSheet(client: client)) { $0.start(at: selection) }
	}

	/// Named for its argument so that the member-list menu can own the plain
	/// `memberChangeColor:` selector.
	func showNicknameColorSheet(for nickname: String) {
		mainWindow.presentationModel.closePresentedSheet()
		guard selectedClient != nil else { return }
		let sheet = NicknameColorSheet(nickname: nickname)
		sheet.colorDidChange = { [weak self] in
			guard let self else { return }
			mainWindow.reloadTheme()
			/* The transcript is redrawn by the theme reload; the member list's
			 avatars take their pinned colours from a snapshot the list reads
			 when its presentation is invalidated, and nothing else invalidates
			 it here. */
			mainWindow.memberList.invalidatePresentation()
		}
		present(sheet) { $0.start() }
	}

	private func showServerProperties(selection: ServerPropertiesDestination) {
		guard let client = selectedClient else { return }
		showServerProperties(for: client, selection: selection)
	}

	private func showPreferences(_ selection: PreferencesSceneSelection) {
		SharedApplication.sharedApplicationScenes().openSettings(selection)
	}
}
