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

@MainActor
public extension MenuActionCoordinator {
	@objc(channelPropertiesDidAccept:config:)
	func channelPropertiesDidAccept(_ sender: ChannelPropertiesSheet, config: ChannelConfig) {
		guard let client = sender.client else { return }
		let world = NSObject.applicationController().world!
		guard let channel = sender.channel else {
			_ = world.createChannel(with: config, on: client)
			mainWindow.expandClient(client)
			return
		}
		channel.updateConfig(config)
		world.save()
	}

	@objc(channelInviteDidSelect:channelName:)
	func channelInviteDidSelect(_ sender: ChannelInviteSheet, channelName: String) {
		guard let client = sender.client, client.isLoggedIn else { return }
		for nickname in sender.nicknames {
			client.sendInvite(to: nickname, toJoinChannelNamed: channelName)
		}
	}

	@objc(serverPropertiesDidAccept:config:)
	func serverPropertiesDidAccept(_ sender: ServerPropertiesSheet, config: IRCClientConfig) {
		let world = NSObject.applicationController().world!
		guard let client = sender.client else {
			let client = world.createClient(with: config, reload: true)
			mainWindow.expandClient(client)
			world.save()
			return
		}
		let encodingChanged = config.primaryEncoding != client.config.primaryEncoding
		client.updateConfig(config)
		if encodingChanged {
			mainWindow.reloadTheme()
		}
		mainWindow.reloadTreeGroup(client)
		world.save()
	}

	@objc(nicknameColorDidAccept:)
	func nicknameColorDidAccept(_: NicknameColorSheet) {
		mainWindow.reloadTheme()
	}

	@objc(channelTopicDidAccept:topic:)
	func channelTopicDidAccept(_ sender: ChannelModifyTopicSheet, topic: String) {
		guard let client = sender.client, let channel = sender.channel,
		      client.isLoggedIn, channel.isChannel
		else { return }
		client.sendTopic(to: topic, in: channel)
	}

	@objc(channelModesDidAccept:modes:)
	func channelModesDidAccept(_ sender: ChannelModifyModesSheet, modes: ChannelModeContainer) {
		guard let client = sender.client, let channel = sender.channel,
		      client.isLoggedIn, channel.isChannel,
		      let changeString = channel.modeInfo?.changeCommand(for: modes),
		      changeString.isEmpty == false
		else { return }
		client.sendModes(changeString, withParametersString: nil, in: channel)
	}

	@objc(channelSpotlightDidSelect:channel:)
	func channelSpotlightDidSelect(_: ChannelSpotlightController, channel: IRCChannel) {
		guard let treeItem = (channel as AnyObject) as? IRCTreeItem else {
			assertionFailure("IRCChannel must bridge to its legacy tree-item interface")
			return
		}
		mainWindow.select(treeItem)
	}

	@objc(serverNicknameDidAccept:nickname:)
	func serverNicknameDidAccept(_ sender: ServerChangeNicknameSheet, nickname: String) {
		guard let client = sender.client, client.isConnected else { return }
		client.changeNickname(nickname)
	}

	@objc(dialogDidClose:)
	func dialogDidClose(_ sender: Any) {
		SharedApplication.sharedWindowController().removeWindow(fromWindowList: sender)
	}

	@objc(preferencesDialogDidClose:)
	func preferencesDialogDidClose(_ sender: PreferencesController) {
		TextualPreferences.performReloadAction([.highlightKeywords, .preferencesChanged])
		dialogDidClose(sender)
	}
}
