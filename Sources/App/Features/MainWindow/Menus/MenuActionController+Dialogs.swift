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

extension MenuActionController {
	/* Each command checks it can act before it takes down the sheet already on
	 screen. The other order dismissed an unrelated sheet, and the edits in it,
	 for a command that then did nothing.

	 A sheet reports what the person accepted through a closure it was built
	 with, so the command and its answer are written together. */

	@objc func showChannelPropertiesSheet(_: Any?) {
		guard let channel = selectedChannel, channel.isChannel else { return }
		presentChannelProperties(for: channel, on: channel.associatedClient)
	}

	@objc func memberSendInvite(_ sender: Any?) {
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
		mainWindow.presentationModel.dismissPresentedSheet()
		let sheet = ChannelInviteSheet(nicknames: nicknames, on: client) { [weak client] channelName in
			guard let client, client.isLoggedIn else { return }
			for nickname in nicknames {
				client.sendInvite(to: nickname, toJoinChannelNamed: channelName)
			}
		}
		sheet.window = mainWindow
		sheet.start(withChannels: channels)
	}

	@objc func showAddressBook(_: Any?) {
		presentServerPropertiesForSelectedClient(at: .addressBook)
	}

	@objc func showOnboardingWindow(_: Any?) {
		mainWindow.presentationModel.dismissPresentedSheet()
		AppServices.scenes.openOnboarding()
	}

	@objc func showAboutWindow(_: Any?) {
		AppServices.scenes.openAbout()
	}

	@objc func showServerPropertiesSheet(_: Any?) {
		presentServerPropertiesForSelectedClient(at: .default)
	}

	/// A window rather than a sheet: the list exists to jump into the transcript
	/// with, and a sheet had to be dismissed to get there and reopened for the
	/// next highlight.
	@objc func showServerHighlightList(_: Any?) {
		guard let client = selectedClient else { return }
		AppServices.scenes.openServerHighlightList(for: client)
	}

	@objc func showChannelModifyTopicSheet(_: Any?) {
		guard let channel = selectedChannel, channel.isChannel else { return }
		mainWindow.presentationModel.dismissPresentedSheet()
		let sheet = ChannelTopicSheet(channel: channel) { [weak channel] topic in
			guard let channel, let client = channel.associatedClient,
			      client.isLoggedIn, channel.isChannel
			else { return }
			client.sendTopic(to: topic, in: channel)
		}
		sheet.window = mainWindow
		sheet.start()
	}

	@objc func showChannelModifyModesSheet(_: Any?) {
		guard let channel = selectedChannel, channel.isChannel else { return }
		mainWindow.presentationModel.dismissPresentedSheet()
		let sheet = ChannelModesSheet(channel: channel) { [weak channel] modes in
			guard let channel, let client = channel.associatedClient,
			      client.isLoggedIn, channel.isChannel,
			      let changes = channel.modeInfo?.changeGroups(for: modes),
			      changes.isEmpty == false
			else { return }
			client.sendModes(changes, inChannelNamed: channel.name)
		}
		sheet.window = mainWindow
		sheet.start()
	}

	@objc func showChannelSpotlightWindow(_: Any?) {
		AppServices.scenes.openChannelSpotlight()
	}

	@objc func showServerChangeNicknameSheet(_: Any?) {
		guard let client = selectedClient, client.isLoggedIn else { return }
		mainWindow.presentationModel.dismissPresentedSheet()
		let sheet = ServerNicknameChangeSheet(client: client) { [weak client] nickname in
			guard let client, client.isConnected else { return }
			client.changeNickname(nickname)
		}
		sheet.window = mainWindow
		sheet.start()
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

	@objc func showFileTransfersWindow(_: Any?) {
		fileTransferCenter.present()
	}

	/** Opens the connection sheet, on an existing connection or on a new one.

	 A new connection is created once the sheet is accepted; an existing one is
	 updated in place, and the transcript is redrawn only where the encoding
	 changed, because that is what decides how the lines already on screen are
	 decoded. */
	func presentServerProperties(
		for client: Client?,
		at destination: ServerPropertiesDestination = .default
	) {
		mainWindow.presentationModel.dismissPresentedSheet()
		let sheet = ServerPropertiesSheet(client: client) { [weak self, weak client] config in
			guard let self, let clientDirectory else { return }
			guard let client else {
				let created = clientDirectory.createClient(with: config)
				mainWindow.expandClient(created)
				clientDirectory.save()
				return
			}
			let encodingChanged = config.primaryEncoding != client.config.primaryEncoding
			client.updateConfig(config)
			if encodingChanged {
				mainWindow.reloadTheme()
			}
			mainWindow.reloadChatItemGroup(client)
			clientDirectory.save()
		}
		sheet.window = mainWindow
		sheet.start(at: destination)
	}

	/// Opens the channel sheet, on an existing channel or on a new one for
	/// `client`.
	func presentChannelProperties(for channel: Channel?, on client: Client?) {
		mainWindow.presentationModel.dismissPresentedSheet()
		let save: (ChannelConfig) -> Void = { [weak self, weak client, weak channel] config in
			guard let self, let clientDirectory, let client else { return }
			guard let channel else {
				_ = clientDirectory.createChannel(with: config, on: client)
				mainWindow.expandClient(client)
				return
			}
			channel.updateConfig(config)
			clientDirectory.save()
		}
		let sheet = channel.map { ChannelPropertiesSheet(channel: $0, onSave: save) }
			?? ChannelPropertiesSheet(config: nil, onClient: client, onSave: save)
		sheet.window = mainWindow
		sheet.start()
	}

	/// Named for its argument so that the member-list menu can own the plain
	/// `memberChangeColor:` selector.
	func showNicknameColorSheet(for nickname: String) {
		guard selectedClient != nil else { return }
		mainWindow.presentationModel.dismissPresentedSheet()
		let sheet = NicknameColorSheet(nickname: nickname) { [weak self] in
			guard let self else { return }
			mainWindow.reloadTheme()
			/* The transcript is redrawn by the theme reload; the member list's
			 avatars take their pinned colours from a snapshot the list reads
			 when its presentation is invalidated, and nothing else invalidates
			 it here. */
			mainWindow.memberList.invalidatePresentation()
		}
		sheet.window = mainWindow
		sheet.start()
	}

	private func presentServerPropertiesForSelectedClient(at destination: ServerPropertiesDestination) {
		guard let client = selectedClient else { return }
		presentServerProperties(for: client, at: destination)
	}

	private func showPreferences(_ selection: SettingsSceneSelection) {
		AppServices.scenes.openSettings(selection)
	}
}
