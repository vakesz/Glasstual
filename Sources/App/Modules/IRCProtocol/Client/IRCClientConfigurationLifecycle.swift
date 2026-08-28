/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
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
import os

enum IRCClientConfigurationPolicy {
	static func shouldStoreChannel(
		isUtility: Bool,
		isDirectChat: Bool,
		isChannel: Bool,
		rememberQueries: Bool
	) -> Bool {
		guard isUtility == false, isDirectChat == false else { return false }
		return isChannel || rememberQueries
	}

	static func storedChannelConfigurations(
		from channels: [IRCChannel],
		rememberQueries: Bool
	) -> [ChannelConfig] {
		channels.compactMap { channel in
			guard shouldStoreChannel(
				isUtility: channel.isUtility,
				isDirectChat: channel.isDirectChat,
				isChannel: channel.isChannel,
				rememberQueries: rememberQueries
			) else { return nil }
			return channel.config
		}
	}
}

enum IRCClientLifecyclePolicy {
	static func requiresDisconnect(isConnecting: Bool, isConnected: Bool) -> Bool {
		isConnecting || isConnected
	}
}

private let clientConfigurationLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "IRCClientConfiguration"
)

private let clientTerminationLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "Termination"
)

@MainActor
public extension IRCClient {
	@objc(updateConfig:)
	func updateConfig(_ newConfig: ClientConfig) {
		updateConfig(newConfig, updateSelection: true)
	}

	@objc(updateConfig:updateSelection:)
	func updateConfig(_ newConfig: ClientConfig, updateSelection: Bool) {
		guard isTerminating == false, config.isEqual(newConfig) == false else { return }
		guard config.uniqueIdentifier == newConfig.uniqueIdentifier else {
			clientConfigurationLogger.error("Tried to load configuration for incorrect client")
			return
		}

		let currentConfig = config
		config = newConfig
		reconcileChannels(with: newConfig.channelList)
		reconcileServers(from: currentConfig.serverList, to: newConfig.serverList)

		if updateSelection {
			reloadServerListItems()
		}

		let controller: ApplicationController = AppController.shared
		controller.menuController?.populateNavigationChannelList()
		writePasswordsToKeychain()
		destroyServerPasswordKeychainItemAfterMigration()
		controller.mainWindow?.updateTitle(for: self)
		clearAddressBookCache()
		populateISONTrackedUsersList()
		NotificationCenter.default.post(name: .init("IRCClientConfigurationWasUpdatedNotification"), object: self)
	}

	@objc(reloadServerListItems)
	func reloadServerListItems() {
		guard let mainWindow = AppController.shared.mainWindow,
		      let serverList = mainWindow.serverList
		else { return }

		mainWindow.ignoreOutlineViewSelectionChanges = true
		serverList.beginUpdates()
		serverList.reloadItem(self, reloadChildren: true)
		serverList.endUpdates()
		mainWindow.adjustSelection()
		mainWindow.ignoreOutlineViewSelectionChanges = false
	}

	@objc(writePasswordsToKeychain)
	func writePasswordsToKeychain() {
		config.writeNicknamePasswordToKeychain()
		config.writeProxyPasswordToKeychain()
	}

	@objc(destroyServerPasswordKeychainItemAfterMigration)
	func destroyServerPasswordKeychainItemAfterMigration() {
		config.destroyServerPasswordKeychainItemAfterMigration()
	}

	@objc(updateStoredConfiguration)
	func updateStoredConfiguration() {
		guard configurationIsStale,
		      let mutableConfig = config.mutableCopy() as? MutableClientConfig
		else { return }

		mutableConfig.lastMessageServerTime = lastMessageServerTime
		mutableConfig.sidebarItemExpanded = sidebarItemIsExpanded
		config = mutableConfig
	}

	@objc(updateStoredChannelList)
	func updateStoredChannelList() {
		guard let mutableConfig = config.mutableCopy() as? MutableClientConfig else { return }

		mutableConfig.channelList = IRCClientConfigurationPolicy.storedChannelConfigurations(
			from: channelList,
			rememberQueries: TextualPreferences.rememberServerListQueryStates()
		)
		config = mutableConfig
		NotificationCenter.default.post(name: .init("IRCClientChannelListWasModifiedNotification"), object: self)
	}

	@objc(configurationDictionary)
	func configurationDictionary() -> [String: Any] {
		updateStoredConfiguration()
		return config.dictionaryValue
	}

	@objc(prepareForApplicationTermination)
	func prepareForApplicationTermination() {
		isTerminating = true
		let clientIdentifier = uniqueIdentifier
		clientTerminationLogger.info("Preparing client: <\(clientIdentifier, privacy: .public)>")
		clientTerminationLogger.info("[\(clientIdentifier, privacy: .public)] Closing dialogs")
		closeDialogs()

		guard IRCClientLifecyclePolicy.requiresDisconnect(
			isConnecting: isConnecting,
			isConnected: isConnected
		) else {
			prepareForApplicationTerminationPostflight()
			return
		}

		clientTerminationLogger.info("[\(clientIdentifier, privacy: .public)] Performing disconnect")
		addDisconnectCallback { [weak self] in
			self?.prepareForApplicationTerminationPostflight()
		}
		quit()
	}

	@objc(prepareForApplicationTerminationPostflight)
	func prepareForApplicationTerminationPostflight() {
		let clientIdentifier = uniqueIdentifier
		clientTerminationLogger.info("[\(clientIdentifier, privacy: .public)] Closing log file")
		closeLogFile()
		clientTerminationLogger.info(
			"[\(clientIdentifier, privacy: .public)] Removing unspoken messages from speech synthesizer"
		)
		clearEventsToSpeak()
		clientTerminationLogger.info("[\(clientIdentifier, privacy: .public)] Emptying Address Book cache")
		clearAddressBookCache()
		clientTerminationLogger.info("[\(clientIdentifier, privacy: .public)] Removing all tracked users")
		clearTrackedUsers()
		let channels = channelList
		clientTerminationLogger.info(
			"[\(clientIdentifier, privacy: .public)] Preparing channels: \(channels.count, privacy: .public)"
		)
		channels.forEach { $0.prepareForApplicationTermination() }
		let viewIdentifier = viewController.uniqueIdentifier
		clientTerminationLogger.info(
			"[\(clientIdentifier, privacy: .public)] Preparing view controller: <\(viewIdentifier, privacy: .public)>"
		)
		((viewController as AnyObject) as? LogController)?.prepareForApplicationTermination()
		clientTerminationLogger.info("[\(clientIdentifier, privacy: .public)] Decrementing client count")
		AppController.shared.terminatingClientCount -= 1
	}

	@objc(prepareForPermanentDestruction)
	func prepareForPermanentDestruction() {
		isTerminating = true
		stopAllTimers()
		closeDialogs()
		closeLogFile()
		clearEventsToSpeak()
		clearAddressBookCache()
		clearTrackedUsers()
		config.destroyNicknamePasswordKeychainItem()
		config.destroyProxyPasswordKeychainItem()
		destroyServerPasswordsKeychainItems()
		channelList.forEach { $0.prepareForPermanentDestruction() }
		AppController.shared.mainWindow.inputHistoryManager().destroy(self)
		((viewController as AnyObject) as? LogController)?.prepareForPermanentDestruction()
	}

	@objc(closeDialogs)
	func closeDialogs() {
		let channelListDialogKey = "TDCServerChannelListDialog -> \(uniqueIdentifier)"
		let channelListDialog = SharedApplication.sharedWindowController()
			.window(fromWindowList: channelListDialogKey) as? ServerChannelListDialog
		channelListDialog?.close()
		let descriptions = [
			"TDCChannelInviteSheet",
			"TDCServerChangeNicknameSheet",
			"TDCServerHighlightListSheet",
			"TDCServerPropertiesSheet",
		]
		let windows = SharedApplication.sharedWindowController().windows(fromWindowList: descriptions)
		for window in windows {
			guard let sheet = window as? SheetBase,
			      let clientSheet = window as? TDCClientPrototype,
			      clientSheet.clientId == uniqueIdentifier
			else { continue }
			sheet.close()
		}
	}

	@objc(preferencesChanged)
	func preferencesChanged() {
		channelList.forEach { $0.preferencesChanged() }
		if monitorAwayStatus == false {
			resetAwayStatusForUsers()
		}
	}

	@objc(willDestroyChannel:)
	func willDestroyChannel(_ notification: Notification) {
		guard let channel = notification.object as? IRCChannel, channel.associatedClient === self else { return }
		clearZNCPlayback(for: channel)
		if hiddenCommandResponsesQuery === channel {
			hiddenCommandResponsesQuery = nil
		}
		if rawDataLogQuery === channel {
			rawDataLogQuery = nil
		}
	}

	@objc(enumerateServers:)
	func enumerateServers(_ body: (Server, UInt, UnsafeMutablePointer<ObjCBool>) -> Void) {
		(config.serverList as NSArray).enumerateObjects { object, index, stop in
			guard let server = object as? Server else { return }
			body(server, UInt(index), stop)
		}
	}

	@objc(writeServerPasswordsToKeychain)
	func writeServerPasswordsToKeychain() {
		config.serverList.forEach { $0.writeServerPasswordToKeychain() }
	}

	@objc(destroyServerPasswordsKeychainItems)
	func destroyServerPasswordsKeychainItems() {
		config.serverList.forEach { $0.destroyServerPasswordKeychainItem() }
	}

	private func reconcileChannels(with configurations: [ChannelConfig]) {
		var remainingChannels = channelList
		var updatedChannels: [IRCChannel] = []
		var insertedNames = Set<String>()
		guard let world = AppController.shared.world else { return }

		for channelConfig in configurations where insertedNames.insert(channelConfig.channelName).inserted {
			if let channel = findChannel(channelConfig.channelName, in: remainingChannels) {
				channel.updateConfig(
					channelConfig,
					fireChangedNotification: false,
					updateStoredChannelList: false
				)
				remainingChannels.removeAll { $0 === channel }
				updatedChannels.append(channel)
			} else {
				updatedChannels.append(
					world.createChannel(with: channelConfig, on: self, add: false, adjust: false, reload: false)
				)
			}
		}

		for channel in remainingChannels {
			if channel.isChannel {
				world.destroy(channel, reload: false)
			} else {
				updatedChannels.append(channel)
			}
		}
		channelList = updatedChannels
	}

	private func reconcileServers(from oldServers: [Server], to newServers: [Server]) {
		let newIdentifiers = Set(newServers.map(\.uniqueIdentifier))
		for oldServer in oldServers where newIdentifiers.contains(oldServer.uniqueIdentifier) == false {
			if oldServer.uniqueIdentifier == server?.uniqueIdentifier {
				server?.destroyKeychainItemsDuringDealloc = true
			} else {
				oldServer.destroyServerPasswordKeychainItem()
			}
		}

		if newServers.isEmpty {
			lastServerSelected = UInt(NSNotFound)
		} else {
			newServers.forEach { $0.writeServerPasswordToKeychain() }
		}
	}
}
