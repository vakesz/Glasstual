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
import GlasstualPluginKit
import os

public typealias IRCWorld = World
public let IRCWorldClientListDefaultsKey = "World Controller Client Configurations"

extension World {
	func destroy(_ client: IRCClient) {
		destroyClient(client)
	}

	func destroy(_ channel: IRCChannel, reload: Bool = true) {
		destroyChannel(channel, reload: reload)
	}
}

private enum WorldTiming {
	static let autoConnectDelay: UInt = 1
	static let reconnectAfterWakeupDelay: UInt = 8
	static let savePeriodicallyThreshold: CFAbsoluteTime = 300
}

extension Notification.Name {
	static let ircWorldClientListWasModified = Notification.Name("IRCWorldClientListWasModifiedNotification")
	static let ircWorldDateHasChanged = Notification.Name("IRCWorldDateHasChangedNotification")
	static let ircWorldWillDestroyClient = Notification.Name("IRCWorldWillDestroyClientNotification")
	static let ircWorldWillDestroyChannel = Notification.Name("IRCWorldWillDestroyChannelNotification")
}

private func legacyTreeItem(for channel: IRCChannel) -> IRCTreeItem {
	channel
}

private func nativeChannel(from item: IRCTreeItem?) -> IRCChannel? {
	(item as AnyObject?) as? IRCChannel
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
	private var midnightTimer: Timer?
	private let notifications = NotificationSubscriptions()

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

	// MARK: - Configuration

	@objc public func setupConfiguration() {
		isImportingConfiguration = true

		let serverList = applicationController.mainWindow.serverList!
		serverList.beginUpdates()

		for dictionary in TextualPreferences.clientList() ?? [] {
			let config = IRCClientConfig(dictionary: dictionary)
			_ = createClient(with: config, reload: true)
		}

		serverList.endUpdates()
		isImportingConfiguration = false
		setupOtherServices()
	}

	private func setupOtherServices() {
		setupMidnightTimer()

		notifications.observe(.NSSystemClockDidChange) { [weak self] notification in
			self?.dateChanged(notification)
		}
		notifications
			.observe(.textualUserDefaultsDidChange) { [weak self] notification in
				self?.userDefaultsDidChange(notification)
			}
		notifications.observe(.TVCMainWindowAppearanceChanged) { [weak self] notification in
			self?.mainWindowAppearanceChanged(notification)
		}
	}

	private var clientConfigurations: [[String: Any]] {
		clientList.map { $0.configurationDictionary() }
	}

	@objc public func save() {
		TextualPreferences.setClientList(clientConfigurations)
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
		notifications.cancelAll()

		/* Timer.invalidate() must run on the thread that scheduled the timer. deinit is
		 nonisolated and can run anywhere, and a pending timer retains its target, so
		 deinit could never have reached this anyway. */
		midnightTimer?.invalidate()
		midnightTimer = nil

		for client in clientList {
			client.prepareForApplicationTermination()
		}
	}

	@objc private func userDefaultsDidChange(_: Notification) {
		guard SharedApplication.sharedThemeController().settings.postsPreferenceChangeNotifications else {
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
		guard SharedApplication.sharedThemeController().settings.postsAppearanceChangeNotifications else {
			return
		}

		informAllViewsMainWindowAppearanceChanged()
	}

	private func informAllViewsMainWindowAppearanceChanged() {
		let appearance = applicationController.mainWindow.userInterfaceObjects
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
		guard applicationController.ghostModeIsOn == false || afterWakeUp else {
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
		guard TextualPreferences.disconnectOnSleep() else {
			return
		}

		for client in clientList where client.isConnected {
			client.disconnectType = .computerSleep
			client.quit()
		}
	}

	@objc public func prepareForScreenSleep() {
		guard TextualPreferences.setAwayOnScreenSleep() else {
			return
		}

		for client in clientList {
			client.toggleAwayStatus(true)
		}
	}

	@objc public func wakeFromScreenSleep() {
		guard TextualPreferences.setAwayOnScreenSleep() else {
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
		applicationController.menuController?.preferencesChanged()

		for client in clientList {
			client.preferencesChanged()
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
	public func findChannel(withId channelId: String, onClientWithId clientId: String) -> IRCChannel? {
		guard let client = findClient(withId: clientId) else { return nil }
		return client.channelList.first { $0.uniqueIdentifier == channelId }
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
		guard applicationController.applicationIsTerminating == false else {
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
				applicationController.mainWindow.serverList?.addItem(toList: UInt(index), inParent: nil)
			}

			if clients.count == 1 {
				applicationController.mainWindow.select(client)
			}
		}

		_ = applicationController.mainWindow.reloadLoadingScreen()
		applicationController.menuController?.populateNavigationChannelList()
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
		let channel = swiftChannel
		swiftChannel.viewController = createViewController(client: client, channel: channel)

		if add {
			client.add(channel)
		}

		if reload, let index = client.channelList.firstIndex(where: { $0 === channel }) {
			applicationController.mainWindow.serverList?.addItem(toList: UInt(index), inParent: client)
		}

		if adjust {
			applicationController.mainWindow.adjustSelection()
			applicationController.menuController?.populateNavigationChannelList()
		}

		return channel
	}

	@objc(createPrivateMessage:onClient:)
	public func createPrivateMessage(_ nickname: String, on client: IRCClient) -> IRCChannel {
		createPrivateMessage(nickname, on: client, as: .privateMessage)
	}

	public func createPrivateMessage(
		_ nickname: String,
		on client: IRCClient,
		as type: ChannelType
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

	@objc(createPrivateMessage:onClient:asType:)
	public func createPrivateMessageFromObjectiveC(
		_ nickname: String,
		on client: IRCClient,
		asType rawValue: UInt
	) -> IRCChannel {
		guard let type = ChannelType(rawValue: rawValue) else {
			preconditionFailure("Unknown channel type raw value: \(rawValue)")
		}
		return createPrivateMessage(nickname, on: client, as: type)
	}

	private func createViewController(client: IRCClient, channel: IRCChannel?) -> LogController {
		if let channel {
			return LogController(channel: channel, in: applicationController.mainWindow)
		}

		return LogController(client: client, in: applicationController.mainWindow)
	}

	private func selectOtherBeforeDestroy(_ target: IRCTreeItem) {
		if target.isClient {
			applicationController.mainWindow.deselectGroup(target)
		} else {
			applicationController.mainWindow.deselect(target)
		}
	}

	@objc(destroyClient:)
	public func destroyClient(_ client: IRCClient) {
		if client.isConnecting || client.isConnected {
			client.addDisconnectCallback { [weak self, weak client] in
				guard let client else {
					return
				}
				self?.destroyClient(client)
			}
			client.quit()
			return
		}

		NotificationCenter.default.post(
			name: .ircWorldWillDestroyClient,
			object: client
		)
		selectOtherBeforeDestroy(client)
		client.prepareForPermanentDestruction()
		applicationController.mainWindow.serverList?.removeItem(fromList: client)

		clientsLock.withLock {
			clients.removeAll { $0 === client }
		}

		postClientListWasModifiedNotification()
		_ = applicationController.mainWindow.reloadLoadingScreen()
		applicationController.menuController?.populateNavigationChannelList()
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
			name: .ircWorldWillDestroyChannel,
			object: channel
		)

		guard let client = channel.associatedClient else {
			return
		}

		if partChannel {
			client.part(channel)
		}

		if reload {
			selectOtherBeforeDestroy(legacyTreeItem(for: channel))
		}

		channel.prepareForPermanentDestruction()
		if client.lastSelectedChannel === channel {
			client.lastSelectedChannel = nil
		}

		if reload {
			applicationController.mainWindow.serverList?.removeItem(fromList: channel)
			client.remove(channel)
			applicationController.mainWindow.adjustSelection()
			applicationController.menuController?.populateNavigationChannelList()
		}
	}
}
