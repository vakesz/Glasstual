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
import CocoaExtensions

private enum MenuServerSuppressionKey: String {
	case deleteChannel = "delete_channel"
}

enum MenuServerActionPolicy {
	static func canConnect(isConnecting: Bool, isConnected: Bool, isQuitting: Bool) -> Bool {
		isConnecting == false && isConnected == false && isQuitting == false
	}

	static func canDisconnect(isConnecting: Bool, isConnected: Bool, isQuitting: Bool) -> Bool {
		(isConnecting || isConnected) && isQuitting == false
	}
}

@MainActor
public extension MenuActionCoordinator {
	func performServerChannelAction(_ action: MenuServerChannelAction, sender: Any?) {
		switch action {
		case .connect: connect(bypassingProxy: false)
		case .connectBypassingProxy: connect(bypassingProxy: true)
		case .disconnect: disconnect()
		case .cancelReconnection: selectedClient?.cancelReconnect()
		case .showChannelList: showServerChannelList()
		case .addServer: addServer()
		case .duplicateServer: duplicateServer()
		case .deleteServer: deleteServer()
		case .joinChannel: joinSelectedChannel()
		case .leaveChannel: leaveSelectedChannel()
		case .addChannel: addChannel()
		case .deleteChannel: deleteChannel()
		case .copyUniqueIdentifier: copyUniqueIdentifier()
		case .joinClickedChannel: joinClickedChannel(sender)
		case .empty: break
		@unknown default: break
		}
	}

	private func connect(bypassingProxy: Bool) {
		guard let client = selectedClient,
		      MenuServerActionPolicy.canConnect(
		      	isConnecting: client.isConnecting,
		      	isConnected: client.isConnected,
		      	isQuitting: client.isQuitting
		      )
		else { return }
		if bypassingProxy {
			client.connect(.normal, bypassProxy: true)
		} else {
			client.connect()
		}
		mainWindow.expandClient(client)
	}

	private func disconnect() {
		guard let client = selectedClient,
		      MenuServerActionPolicy.canDisconnect(
		      	isConnecting: client.isConnecting,
		      	isConnected: client.isConnected,
		      	isQuitting: client.isQuitting
		      )
		else { return }
		client.quit()
	}

	private func showServerChannelList() {
		guard let client = selectedClient, client.isLoggedIn else { return }
		client.openServerChannelList()
	}

	private func addServer() {
		mainWindow.presentationModel.closePresentedSheet()
		present(ServerPropertiesSheet(client: nil)) { $0.start() }
	}

	private func duplicateServer() {
		guard let client = selectedClient, let world else { return }

		var config = client.config.uniqueCopy()
		config.connectionName += "_"
		let newClient = world.createClient(with: config, reload: true)
		if newClient.config.sidebarItemExpanded {
			mainWindow.expandClient(newClient)
		}
		world.save()
	}

	private func deleteServer() {
		guard let client = selectedClient,
		      let world,
		      client.isConnecting == false,
		      client.isConnected == false
		else { return }
		let completion: AlertCompletion = { outcome in
			guard outcome.response == .default,
			      client.isConnecting == false,
			      client.isConnected == false
			else { return }
			world.destroy(client)
			world.save()
		}
		Alerts.alert(
			withMessage: PromptStrings.Deletion.warning(for: .server),
			title: PromptStrings.Deletion.confirmationTitle,
			defaultButton: PromptStrings.Action.yes,
			alternateButton: PromptStrings.Action.no,
			completionBlock: completion
		)
	}

	private func joinSelectedChannel() {
		guard let client = selectedClient, let channel = selectedChannel,
		      client.isLoggedIn, channel.isChannel, channel.isActive == false
		else { return }
		client.join(channel)
		selectInMainWindow(channel)
	}

	private func leaveSelectedChannel() {
		guard let client = selectedClient, let channel = selectedChannel else { return }
		if channel.isChannel {
			guard client.isLoggedIn, channel.isActive else { return }
			client.part(channel)
		} else {
			world?.destroy(channel)
		}
	}

	private func addChannel() {
		mainWindow.presentationModel.closePresentedSheet()
		guard let client = selectedClient else { return }
		present(ChannelPropertiesSheet(client: client)) { $0.start() }
	}

	private func deleteChannel() {
		guard let channel = selectedChannel, let world else { return }
		if channel.isChannel == false {
			world.destroy(channel)
			world.save()
			return
		}
		let completion: AlertCompletion = { outcome in
			guard outcome.response == .default else { return }
			world.destroy(channel)
			world.save()
		}
		Alerts.alert(
			withMessage: PromptStrings.Deletion.warning(for: .channel),
			title: PromptStrings.Deletion.confirmationTitle,
			defaultButton: PromptStrings.Action.yes,
			alternateButton: PromptStrings.Action.no,
			suppressionKey: MenuServerSuppressionKey.deleteChannel.rawValue,
			suppressionText: nil,
			completionBlock: completion
		)
	}

	private func copyUniqueIdentifier() {
		guard let identifier = selectedChannel?.uniqueIdentifier else { return }
		NSPasteboard.general.setString(identifier, forType: .string)
	}

	private func joinClickedChannel(_ sender: Any?) {
		guard let client = selectedClient, client.isLoggedIn else { return }
		let channelName: String? = if let menuItem = sender as? NSMenuItem {
			menuItem.textualUserInfo
		} else {
			sender as? String
		}
		guard let channelName, client.stringIsChannelName(channelName),
		      let channel = client.findChannelOrCreate(channelName)
		else { return }
		client.join(channel)
		selectInMainWindow(channel)
	}

	private func selectInMainWindow(_ channel: IRCChannel) {
		mainWindow.select(channel)
	}
}
