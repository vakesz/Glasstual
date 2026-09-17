// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions

private enum MenuServerSuppressionKey: String {
	case deleteChannel = "delete_channel"
}

// MARK: - Server and channel commands

extension MenuActionController {
	@objc func connect(_: Any?) {
		connect(bypassingProxy: false)
	}

	@objc func connectBypassingProxy(_: Any?) {
		connect(bypassingProxy: true)
	}

	@objc func disconnect(_: Any?) {
		guard isRunning, let client = selectedClient,
		      MenuServerActionPolicy(client: client).canDisconnect
		else { return }
		client.quit()
	}

	@objc func cancelReconnection(_: Any?) {
		guard isRunning, let client = selectedClient,
		      MenuServerActionPolicy(client: client).canCancelReconnect
		else { return }
		client.cancelReconnect()
	}

	@objc func showServerChannelList(_: Any?) {
		guard isRunning, let client = selectedClient, client.isLoggedIn else { return }
		AppServices.scenes.openServerChannelList(for: client)
	}

	@objc func addServer(_: Any?) {
		guard isRunning else { return }
		presentServerProperties(for: nil)
	}

	@objc func duplicateServer(_: Any?) {
		guard isRunning, let client = selectedClient, let clientDirectory else { return }

		let snapshot = client.config
		let identifier = UUID()
		serverDuplicationTasks[identifier] = Task { [weak self, weak client, weak clientDirectory] in
			var config = await KeychainSecretLoader.duplicate(snapshot)
			guard let self else { return }
			defer { serverDuplicationTasks[identifier] = nil }
			guard !Task.isCancelled, isRunning, let client, !client.isTerminating, let clientDirectory else { return }
			config.connectionName = MenuServerNamePolicy.duplicateName(of: config.connectionName)
			let newClient = clientDirectory.createClient(with: config)
			if newClient.config.sidebarItemExpanded {
				mainWindow.expandClient(newClient)
			}
			clientDirectory.save()
		}
	}

	@objc func deleteServer(_: Any?) {
		guard isRunning, let client = selectedClient,
		      let clientDirectory,
		      client.isConnecting == false,
		      client.isConnected == false
		else { return }
		let completion: AlertCompletion = { outcome in
			guard outcome.response == .default,
			      client.isConnecting == false,
			      client.isConnected == false
			else { return }
			clientDirectory.destroyClient(client)
			clientDirectory.save()
		}
		/* Delete/Cancel, not Yes/No: the default button says what it does, which
		 is what makes a destructive confirmation readable at a glance. The
		 Return key still belongs to Cancel — see `AlertRequest`. */
		Alerts.alert(
			withMessage: PromptStrings.Deletion.warning(for: .server),
			title: PromptStrings.Deletion.confirmationTitle(named: client.name),
			defaultButton: PromptStrings.Action.delete,
			alternateButton: PromptStrings.Action.cancel,
			destructiveButton: .default,
			completionBlock: completion
		)
	}

	@objc func joinChannel(_: Any?) {
		guard isRunning, let client = selectedClient, let channel = selectedChannel,
		      client.canJoin(channel)
		else { return }
		client.join(channel)
		mainWindow.select(channel)
	}

	@objc func leaveChannel(_: Any?) {
		guard isRunning, let client = selectedClient, let channel = selectedChannel,
		      channel.associatedClient === client
		else { return }
		if channel.isChannel {
			guard client.canJoinChannels, channel.isActive else { return }
			client.part(channel)
		} else {
			clientDirectory?.destroyChannel(channel)
		}
	}

	@objc func addChannel(_: Any?) {
		guard isRunning, let client = selectedClient else { return }
		presentChannelProperties(for: nil, on: client)
	}

	@objc func deleteChannel(_: Any?) {
		guard isRunning, let channel = selectedChannel, let clientDirectory else { return }
		if channel.isChannel == false {
			clientDirectory.destroyChannel(channel)
			clientDirectory.save()
			return
		}
		let completion: AlertCompletion = { outcome in
			guard outcome.response == .default else { return }
			clientDirectory.destroyChannel(channel)
			clientDirectory.save()
		}
		Alerts.alert(
			withMessage: PromptStrings.Deletion.warning(for: .channel),
			title: PromptStrings.Deletion.confirmationTitle(named: channel.name),
			defaultButton: PromptStrings.Action.delete,
			alternateButton: PromptStrings.Action.cancel,
			destructiveButton: .default,
			suppressionKey: MenuServerSuppressionKey.deleteChannel.rawValue,
			suppressionText: nil,
			completionBlock: completion
		)
	}

	@objc func copyUniqueIdentifier(_: Any?) {
		guard let identifier = selectedChannel?.uniqueIdentifier else { return }
		NSPasteboard.general.setString(identifier, forType: .string)
	}

	@objc func joinChannelClicked(_ sender: Any?) {
		guard isRunning, let client = selectedClient, client.canJoinChannels else { return }
		let channelName: String? = if let menuItem = sender as? NSMenuItem {
			menuItem.userInfoString
		} else {
			sender as? String
		}
		guard let channelName, client.stringIsChannelName(channelName),
		      let channel = client.findChannelOrCreate(channelName)
		else { return }
		client.join(channel)
		mainWindow.select(channel)
	}

	/// Nothing may act on the connection tree once the application has begun
	/// shutting down.
	private var isRunning: Bool {
		AppServices.delegate.applicationIsTerminating == false
	}

	private func connect(bypassingProxy: Bool) {
		guard isRunning, let client = selectedClient else { return }
		let policy = MenuServerActionPolicy(client: client)
		guard bypassingProxy ? policy.canConnectWithoutProxy : policy.canConnect else { return }
		if bypassingProxy {
			client.connect(.normal, bypassProxy: true)
		} else {
			client.connect()
		}
		mainWindow.expandClient(client)
	}
}
