/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
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
 *  * Neither the name of Textual and/or Codeux Software, nor the names of
 *    its contributors may be used to endorse or promote products derived
 *    from this software without specific prior written permission.
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
import os

private enum WorldTiming {
	static let autoConnectDelay: UInt = 1
	static let reconnectAfterWakeupDelay: UInt = 8
	static let savePeriodicallyThreshold: CFAbsoluteTime = 300
}

private extension Notification.Name {
	static let ircWorldClientListWasModified = Notification.Name("IRCWorldClientListWasModifiedNotification")
	static let ircWorldDateHasChanged = Notification.Name("IRCWorldDateHasChangedNotification")
}

private extension NSObject {
	func invokeWorldLifecycleSelector(_ selector: Selector) {
		guard responds(to: selector) else {
			return
		}

		typealias Implementation = @convention(c) (AnyObject, Selector) -> Void
		let implementation = unsafeBitCast(method(for: selector), to: Implementation.self)
		implementation(self, selector)
	}
}

private func legacyTreeItem(for channel: IRCChannel) -> IRCTreeItem {
	(channel as AnyObject) as! IRCTreeItem
}

@MainActor
@objc(IRCWorld)
public final class World: NSObject {
	private let clientsLock = NSRecursiveLock()
	private var clients: [IRCClient] = []

	private nonisolated let trafficLock = NSLock()
	private nonisolated(unsafe) var messagesSentStorage: UInt = 0
	private nonisolated(unsafe) var messagesReceivedStorage: UInt = 0
	private nonisolated(unsafe) var bandwidthInStorage: UInt64 = 0
	private nonisolated(unsafe) var bandwidthOutStorage: UInt64 = 0

	private var preferencesDidChangeTimerIsActive = false
	private var savePeriodicallyLastSave = CFAbsoluteTimeGetCurrent()
	private var lastDateHasChangedDate: Date?
	private nonisolated(unsafe) var midnightTimer: Timer?

	@objc public var isImportingConfiguration = false

	@objc public var clientList: [IRCClient] {
		get {
			clientsLock.withLock { clients }
		}
		set {
			clientsLock.withLock {
				clients = newValue
				postClientListWasModifiedNotification()
			}
		}
	}

	@objc public var clientCount: UInt {
		clientsLock.withLock { UInt(clients.count) }
	}

	@objc public nonisolated var messagesSent: UInt {
		trafficLock.withLock { messagesSentStorage }
	}

	@objc public nonisolated var messagesReceived: UInt {
		trafficLock.withLock { messagesReceivedStorage }
	}

	@objc public nonisolated var bandwidthIn: UInt64 {
		trafficLock.withLock { bandwidthInStorage }
	}

	@objc public nonisolated var bandwidthOut: UInt64 {
		trafficLock.withLock { bandwidthOutStorage }
	}

	deinit {
		NSObject.cancelPreviousPerformRequests(withTarget: self)
		midnightTimer?.invalidate()
	}

	// MARK: - Configuration

	@objc public func setupConfiguration() {
		isImportingConfiguration = true

		let serverList = masterController.mainWindow.serverList!
		serverList.beginUpdates()

		for dictionary in TPCPreferences.clientList() ?? [] {
			let stringDictionary = dictionary.reduce(into: [String: Any]()) { result, entry in
				guard let key = entry.key as? String else {
					return
				}
				result[key] = entry.value
			}
			let config = IRCClientConfig(dictionary: stringDictionary)
			_ = createClient(with: config, reload: true)
		}

		serverList.endUpdates()
		isImportingConfiguration = false
		setupOtherServices()
	}

	private func setupOtherServices() {
		setupMidnightTimer()

		let notifications = NotificationCenter.default
		notifications.addObserver(
			self,
			selector: #selector(dateChanged(_:)),
			name: NSNotification.Name.NSSystemClockDidChange,
			object: nil
		)
		notifications.addObserver(
			self,
			selector: #selector(userDefaultsDidChange(_:)),
			name: .TPCPreferencesUserDefaultsDidChange,
			object: nil
		)
		notifications.addObserver(
			self,
			selector: #selector(mainWindowAppearanceChanged(_:)),
			name: .TVCMainWindowAppearanceChanged,
			object: nil
		)
	}

	private var clientConfigurations: [[String: Any]] {
		clientList.map { $0.configurationDictionary() }
	}

	@objc public func save() {
		TPCPreferences.setClientList(clientConfigurations)
	}

	@objc public func savePeriodically() {
		let now = CFAbsoluteTimeGetCurrent()
		guard savePeriodicallyLastSave + WorldTiming.savePeriodicallyThreshold < now else {
			return
		}

		savePeriodicallyLastSave = now
		save()
	}

	@objc public func prepareForApplicationTermination() {
		NotificationCenter.default.removeObserver(self)

		for client in clientList {
			client.invokeWorldLifecycleSelector(NSSelectorFromString("prepareForApplicationTermination"))
		}
	}

	@objc private func userDefaultsDidChange(_: Notification) {
		guard TXSharedApplication.sharedThemeController().settings.js_postPreferencesDidChangesNotifications else {
			return
		}
		guard preferencesDidChangeTimerIsActive == false else {
			return
		}

		preferencesDidChangeTimerIsActive = true
		perform(
			#selector(informAllViewsUserDefaultsDidChange),
			with: nil,
			afterDelay: 1,
			inModes: [.common]
		)
	}

	@objc private func informAllViewsUserDefaultsDidChange() {
		preferencesDidChangeTimerIsActive = false
		evaluateFunction(onAllViews: "Glasstual.preferencesDidChange", arguments: nil, onQueue: true)
	}

	@objc private func mainWindowAppearanceChanged(_: Notification) {
		guard TXSharedApplication.sharedThemeController().settings.js_postAppearanceChangesNotification else {
			return
		}

		informAllViewsMainWindowAppearanceChanged()
	}

	private func informAllViewsMainWindowAppearanceChanged() {
		let appearance = masterController.mainWindow.userInterfaceObjects
		evaluateFunction(
			onAllViews: "Glasstual.appearanceDidChange",
			arguments: [appearance.shortAppearanceDescription],
			onQueue: true
		)
	}

	// MARK: - Lifecycle

	private func postClientListWasModifiedNotification() {
		NotificationCenter.default.post(name: .ircWorldClientListWasModified, object: self)
	}

	@objc public func autoConnect(afterWakeup afterWakeUp: Bool) {
		guard masterController.ghostModeIsOn == false || afterWakeUp else {
			return
		}

		var delay = afterWakeUp ? WorldTiming.reconnectAfterWakeupDelay : 0

		for client in clientList {
			let isAutoConnecting = afterWakeUp == false && client.config.autoConnect
			let isWakingFromSleep = afterWakeUp
				&& client.config.autoSleepModeDisconnect
				&& client.disconnectType == .computerSleep

			guard isWakingFromSleep || isAutoConnecting else {
				continue
			}

			client.autoConnect(withDelay: delay, afterWakeUp: afterWakeUp)
			delay += WorldTiming.autoConnectDelay
		}
	}

	@objc public func prepareForSleep() {
		guard TPCPreferences.disconnectOnSleep() else {
			return
		}

		for client in clientList where client.isConnected {
			client.disconnectType = .computerSleep
			client.quit()
		}
	}

	@objc public func prepareForScreenSleep() {
		guard TPCPreferences.setAwayOnScreenSleep() else {
			return
		}

		for client in clientList {
			client.toggleAwayStatus(true)
		}
	}

	@objc public func wakeFromScreenSleep() {
		guard TPCPreferences.setAwayOnScreenSleep() else {
			return
		}

		for client in clientList {
			client.toggleAwayStatus(false)
		}
	}

	@objc public func noteReachabilityChanged(_ reachable: Bool) {
		for client in clientList {
			client.noteReachabilityChanged(reachable)
		}
	}

	@objc public func preferencesChanged() {
		masterController.menuController?.invokeWorldLifecycleSelector(NSSelectorFromString("preferencesChanged"))

		for client in clientList {
			client.invokeWorldLifecycleSelector(NSSelectorFromString("preferencesChanged"))
		}
	}

	private func setupMidnightTimer() {
		setupMidnightTimer(firingNotification: false)
	}

	private func setupMidnightTimer(firingNotification fireNotification: Bool) {
		let calendar = Calendar.current
		let now = Date()
		let currentDayComponents = calendar.dateComponents([.year, .month, .day], from: now)
		guard let lastMidnight = calendar.date(from: currentDayComponents),
		      let nextMidnight = calendar.date(byAdding: .day, value: 1, to: lastMidnight)
		else {
			return
		}

		midnightTimer?.invalidate()
		let timer = Timer(
			fireAt: nextMidnight,
			interval: 0,
			target: self,
			selector: #selector(dateChanged(_:)),
			userInfo: nil,
			repeats: false
		)
		timer.tolerance = 0
		RunLoop.main.add(timer, forMode: .default)
		midnightTimer = timer

		if let lastDateHasChangedDate, calendar.isDate(lastDateHasChangedDate, inSameDayAs: lastMidnight) {
			return
		}

		lastDateHasChangedDate = lastMidnight
		guard fireNotification else {
			return
		}

		NotificationCenter.default.post(name: .ircWorldDateHasChanged, object: nil)
		evaluateFunction(
			onAllViews: "Glasstual.dateChanged",
			arguments: [
				currentDayComponents.year ?? 0,
				currentDayComponents.month ?? 0,
				currentDayComponents.day ?? 0,
			],
			onQueue: false
		)
	}

	@objc private func dateChanged(_: Any?) {
		setupMidnightTimer(firingNotification: true)
	}

	// MARK: - Traffic counters

	@objc(noteMessageSentWithLength:)
	public nonisolated func noteMessageSent(length: UInt) {
		trafficLock.withLock {
			messagesSentStorage &+= 1
			bandwidthOutStorage &+= UInt64(length)
		}
	}

	@objc(noteMessageReceivedWithLength:)
	public nonisolated func noteMessageReceived(length: UInt) {
		trafficLock.withLock {
			messagesReceivedStorage &+= 1
			bandwidthInStorage &+= UInt64(length)
		}
	}

	// MARK: - Tree items

	@objc(findItemsWithIds:)
	public func findItems(withIds itemIds: [String]) -> [IRCTreeItem] {
		let identifiers = Set(itemIds)
		var items: [IRCTreeItem] = []

		for client in clientList {
			if identifiers.contains(client.uniqueIdentifier) {
				items.append(client)
			}

			for channel in client.channelList where identifiers.contains(channel.uniqueIdentifier) {
				items.append(legacyTreeItem(for: channel))
			}
		}

		return items
	}

	@objc(findItemWithId:)
	public func findItem(withId itemId: String?) -> IRCTreeItem? {
		guard let itemId else {
			return nil
		}

		for client in clientList {
			if client.uniqueIdentifier == itemId {
				return client
			}

			if let channel = client.channelList.first(where: { $0.uniqueIdentifier == itemId }) {
				return legacyTreeItem(for: channel)
			}
		}

		return nil
	}

	@objc(findClientWithId:)
	public func findClient(withId clientId: String) -> IRCClient? {
		findItem(withId: clientId) as? IRCClient
	}

	@objc(findChannelWithId:onClientWithId:)
	public func findChannel(withId channelId: String, onClientWithId _: String) -> IRCChannel? {
		findItem(withId: channelId) as? IRCChannel
	}

	@objc(findItemWithPasteboardString:)
	public func findItem(withPasteboardString string: String) -> IRCTreeItem? {
		findItem(withId: string)
	}

	@objc(pasteboardStringForItem:)
	public func pasteboardString(for item: IRCTreeItem) -> String {
		item.uniqueIdentifier
	}

	@objc(findClientWithServerAddress:)
	public func findClient(withServerAddress serverAddress: String) -> IRCClient? {
		clientList.first { client in
			client.config.serverList.contains { server in
				server.serverAddress.caseInsensitiveCompare(serverAddress) == .orderedSame
			}
		}
	}

	// MARK: - JavaScript

	@objc(evaluateFunctionOnAllViews:arguments:)
	public func evaluateFunction(onAllViews function: String, arguments: [Any]?) {
		evaluateFunction(onAllViews: function, arguments: arguments, onQueue: true)
	}

	@objc(evaluateFunctionOnAllViews:arguments:onQueue:)
	public func evaluateFunction(onAllViews function: String, arguments: [Any]?, onQueue: Bool) {
		guard masterController.applicationIsTerminating == false else {
			return
		}

		for client in clientList {
			client.viewController.evaluateFunction(function, withArguments: arguments, onQueue: onQueue)

			for channel in client.channelList {
				channel.viewController.evaluateFunction(function, withArguments: arguments, onQueue: onQueue)
			}
		}
	}

	// MARK: - Factory

	@objc(createClientWithConfig:)
	public func createClient(with config: IRCClientConfig) -> IRCClient {
		createClient(with: config, reload: true)
	}

	@objc(createClientWithConfig:reload:)
	public func createClient(with config: IRCClientConfig, reload: Bool) -> IRCClient {
		let client = IRCClient(config: config)
		client.setValue(createViewController(client: client, channel: nil), forKey: "viewController")
		client.channelList = client.config.channelList.map {
			createChannel(with: $0, on: client, add: false, adjust: false, reload: false)
		}

		clientsLock.withLock {
			clients.append(client)

			if reload, let index = clients.firstIndex(where: { $0 === client }) {
				masterController.mainWindow.serverList?.addItem(toList: UInt(index), inParent: nil)
			}

			if clients.count == 1 {
				masterController.mainWindow.select(client)
			}
		}

		_ = masterController.mainWindow.reloadLoadingScreen()
		masterController.menuController?.populateNavigationChannelList()
		postClientListWasModifiedNotification()

		return client
	}

	@objc(createChannelWithConfig:onClient:)
	public func createChannel(with config: ChannelConfig, on client: IRCClient) -> IRCChannel {
		createChannel(with: config, on: client, add: true, adjust: true, reload: true)
	}

	@objc(createChannelWithConfig:onClient:add:adjust:reload:)
	public func createChannel(
		with config: ChannelConfig,
		on client: IRCClient,
		add: Bool,
		adjust: Bool,
		reload: Bool
	) -> IRCChannel {
		let swiftChannel = Channel(config: config)
		swiftChannel.associatedClient = client
		let channel = (swiftChannel as AnyObject) as! IRCChannel
		swiftChannel.viewController = createViewController(client: client, channel: channel)

		if add {
			client.add(channel)
		}

		if reload, let index = client.channelList.firstIndex(where: { $0 === channel }) {
			masterController.mainWindow.serverList?.addItem(toList: UInt(index), inParent: client)
		}

		if adjust {
			masterController.mainWindow.adjustSelection()
			masterController.menuController?.populateNavigationChannelList()
		}

		return channel
	}

	@objc(createPrivateMessage:onClient:)
	public func createPrivateMessage(_ nickname: String, on client: IRCClient) -> IRCChannel {
		createPrivateMessage(nickname, on: client, as: .privateMessage)
	}

	@objc(createPrivateMessage:onClient:asType:)
	public func createPrivateMessage(
		_ nickname: String,
		on client: IRCClient,
		as type: IRCChannelType
	) -> IRCChannel {
		precondition(type == .privateMessage || type == .utility || type == .directChat)

		let config = MutableChannelConfig()
		config.channelName = nickname
		config.type = type

		let channel = createChannel(with: config, on: client, add: true, adjust: true, reload: true)
		if client.isLoggedIn, channel.isPrivateMessage {
			channel.activate()
		}

		return channel
	}

	private func createViewController(client: IRCClient, channel: IRCChannel?) -> LogController {
		if let channel {
			return LogController(channel: channel, in: masterController.mainWindow)
		}

		return LogController(client: client, in: masterController.mainWindow)
	}

	private func selectOtherBeforeDestroy(_ target: IRCTreeItem) {
		if target.isClient {
			masterController.mainWindow.deselectGroup(target)
		} else {
			masterController.mainWindow.deselect(target)
		}
	}

	@objc(destroyClient:)
	public func destroyClient(_ client: IRCClient) {
		if client.isConnecting || client.isConnected {
			client.disconnectCallback = { [weak self, weak client] in
				guard let client else {
					return
				}
				self?.destroyClient(client)
			}
			client.quit()
			return
		}

		NotificationCenter.default.post(
			name: Notification.Name("IRCWorldWillDestroyClientNotification"),
			object: client
		)
		selectOtherBeforeDestroy(client)
		client.invokeWorldLifecycleSelector(NSSelectorFromString("prepareForPermanentDestruction"))
		masterController.mainWindow.serverList?.removeItem(fromList: client)

		clientsLock.withLock {
			clients.removeAll { $0 === client }
		}

		postClientListWasModifiedNotification()
		_ = masterController.mainWindow.reloadLoadingScreen()
		masterController.menuController?.populateNavigationChannelList()
	}

	@objc(destroyChannel:)
	public func destroyChannel(_ channel: IRCChannel) {
		destroyChannel(channel, reload: true, part: true)
	}

	@objc(destroyChannel:reload:)
	public func destroyChannel(_ channel: IRCChannel, reload: Bool) {
		destroyChannel(channel, reload: reload, part: true)
	}

	@objc(destroyChannel:reload:part:)
	public func destroyChannel(_ channel: IRCChannel, reload: Bool, part partChannel: Bool) {
		NotificationCenter.default.post(
			name: Notification.Name("IRCWorldWillDestroyChannelNotification"),
			object: channel
		)

		let client = channel.associatedClient!
		if partChannel {
			client.part(channel)
		}

		if reload {
			selectOtherBeforeDestroy(legacyTreeItem(for: channel))
		}

		channel.invokeWorldLifecycleSelector(NSSelectorFromString("prepareForPermanentDestruction"))
		if client.lastSelectedChannel === channel {
			client.setValue(nil, forKey: "lastSelectedChannel")
		}

		if reload {
			masterController.mainWindow.serverList?.removeItem(fromList: channel)
			client.remove(channel)
			masterController.mainWindow.adjustSelection()
			masterController.menuController?.populateNavigationChannelList()
		}
	}
}
