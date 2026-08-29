/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
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

import CocoaExtensions
import Foundation
import GlasstualPluginKit
import os

public typealias IRCWorld = World
public nonisolated let IRCWorldClientListDefaultsKey = "World Controller Client Configurations" // nonisolated: let

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

private func nativeChannel(from item: IRCTreeItem?) -> IRCChannel? {
	(item as AnyObject?) as? IRCChannel
}

@MainActor
@objc(IRCWorld)
public final class World: NSObject {
	private var clients: [IRCClient] = []

	@objc public private(set) var messagesSent: UInt = 0
	@objc public private(set) var messagesReceived: UInt = 0
	@objc public private(set) var bandwidthIn: UInt64 = 0
	@objc public private(set) var bandwidthOut: UInt64 = 0

	/// Pending debounce of the preference-change broadcast, if any.
	private var preferencesDidChangeTask: Task<Void, Never>?
	private var savePeriodicallyLastSave = CFAbsoluteTimeGetCurrent()
	private var lastDateHasChangedDate: Date?
	/// Waits for the next local midnight so views can redraw their date rules.
	private var midnightTask: Task<Void, Never>?
	private let notifications = NotificationSubscriptions()
	private var observers = WorldObserverList()

	/** The environment handed to every client the world makes. The preference
	 half is refreshed from the defaults store whenever it reports a write. */
	var environment: ClientEnvironment

	@objc public var isImportingConfiguration = false

	/** The application's world shares the services box with
	 `ClientEnvironment.shared`, so the window and menus only have to be
	 installed once for both. */
	@objc override public init() {
		environment = ClientEnvironment(
			preferences: .current(),
			services: ClientEnvironment.shared.services
		)
		super.init()
		environment.services.world = self
		ClientEnvironment.shared.preferences = environment.preferences
	}

	init(environment: ClientEnvironment) {
		self.environment = environment
		super.init()
		self.environment.services.world = self
	}

	@objc public var clientList: [IRCClient] {
		get {
			clients
		}
		set {
			clients = newValue
			postClientListWasModifiedNotification()
		}
	}

	@objc public var clientCount: UInt {
		UInt(clients.count)
	}

	// MARK: - Observers

	func addObserver(_ observer: any WorldObserver) {
		observers.add(observer)
	}

	func removeObserver(_ observer: any WorldObserver) {
		observers.remove(observer)
	}

	private func notifyObservers(_ event: (any WorldObserver) -> Void) {
		observers.forEach(event)
	}

	/// Republishes the navigation list after a client changed shape on its own.
	func noteNavigationListDidChange() {
		notifyObservers { $0.worldNavigationListDidChange(self) }
	}

	// MARK: - Configuration

	@objc public func setupConfiguration() {
		isImportingConfiguration = true

		notifyObservers { $0.worldWillBeginBulkUpdate(self) }

		for dictionary in TextualPreferences.clientList() ?? [] {
			guard let config = PropertyListModel.decode(ClientConfig.self, from: dictionary) else {
				continue
			}

			_ = createClient(with: config, reload: true)
		}

		notifyObservers { $0.worldDidEndBulkUpdate(self) }

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

		midnightTask?.cancel()
		midnightTask = nil
		preferencesDidChangeTask?.cancel()
		preferencesDidChangeTask = nil

		for client in clientList {
			client.prepareForApplicationTermination()
		}
	}

	@objc private func userDefaultsDidChange(_: Notification) {
		/* Every branch the connection code takes on a preference reads the
		 snapshot, so it is refreshed before anything else reacts to the write. */
		refreshEnvironmentPreferences()

		guard SharedApplication.sharedThemeController().settings.postsPreferenceChangeNotifications else {
			return
		}
		/* Preferences change in bursts as a pane is edited; tell the views once. */
		guard preferencesDidChangeTask == nil else {
			return
		}

		preferencesDidChangeTask = Task { [weak self] in
			try? await Task.sleep(for: .seconds(1))

			guard Task.isCancelled == false, let self else { return }

			preferencesDidChangeTask = nil
			evaluateFunction(onAllViews: "Glasstual.preferencesDidChange", arguments: nil, onQueue: true)
		}
	}

	/// Re-reads the defaults store and republishes the snapshot to every client.
	func refreshEnvironmentPreferences() {
		let preferences = ClientPreferences.current()
		guard applyPreferences(preferences) else {
			return
		}

		ClientEnvironment.shared.preferences = preferences
	}

	/// Republishes `preferences` to this world and every client it made.
	/// Returns whether anything changed.
	@discardableResult
	func applyPreferences(_ preferences: ClientPreferences) -> Bool {
		guard preferences != environment.preferences else {
			return false
		}

		environment.preferences = preferences

		for client in clientList {
			client.environment.preferences = preferences
		}

		return true
	}

	@objc private func mainWindowAppearanceChanged(_: Notification) {
		guard SharedApplication.sharedThemeController().settings.postsAppearanceChangeNotifications else {
			return
		}

		environment.output?.notifyAllViewsAppearanceDidChange()
	}

	// MARK: - Lifecycle

	private func postClientListWasModifiedNotification() {
		NotificationCenter.default.post(name: .ircWorldClientListWasModified, object: self)
	}

	@objc public func autoConnect(afterWakeup afterWakeUp: Bool) {
		let ghostModeIsOn = environment.services.applicationState?.ghostModeIsOn ?? false
		guard ghostModeIsOn == false || afterWakeUp else {
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
		guard environment.preferences.disconnectOnSleep else {
			return
		}

		for client in clientList where client.isConnected {
			client.disconnectType = .computerSleep
			client.quit()
		}
	}

	@objc public func prepareForScreenSleep() {
		guard environment.preferences.awayOnScreenSleep else {
			return
		}

		for client in clientList {
			client.toggleAwayStatus(true)
		}
	}

	@objc public func wakeFromScreenSleep() {
		guard environment.preferences.awayOnScreenSleep else {
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
		refreshEnvironmentPreferences()
		notifyObservers { $0.worldPreferencesDidChange(self) }

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

		midnightTask?.cancel()
		let secondsUntilMidnight = max(0, nextMidnight.timeIntervalSinceNow)
		midnightTask = Task { [weak self] in
			try? await Task.sleep(for: .seconds(secondsUntilMidnight))

			guard Task.isCancelled == false, let self else { return }

			midnightTask = nil
			dateChanged(nil)
		}

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
	public func noteMessageSent(length: UInt) {
		messagesSent &+= 1
		bandwidthOut &+= UInt64(length)
	}

	@objc(noteMessageReceivedWithLength:)
	public func noteMessageReceived(length: UInt) {
		messagesReceived &+= 1
		bandwidthIn &+= UInt64(length)
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
				items.append(channel)
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
				return channel
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
		let isTerminating = environment.services.applicationState?.applicationIsTerminating ?? false
		guard isTerminating == false else {
			return
		}

		environment.output?.evaluateFunctionOnAllViews(function, arguments: arguments, onQueue: onQueue)
	}

	// MARK: - Factory

	public func createClient(with config: IRCClientConfig) -> IRCClient {
		createClient(with: config, reload: true)
	}

	public func createClient(with config: IRCClientConfig, reload _: Bool) -> IRCClient {
		let client = IRCClient(config: config, environment: environment)
		client.channelList = client.config.channelList.map {
			createChannel(with: $0, on: client, add: false, adjust: false, reload: false)
		}

		clients.append(client)
		let addedIndex = clients.firstIndex { $0 === client }
		let isOnlyClient = clients.count == 1

		if let addedIndex {
			notifyObservers { $0.world(self, didAddClient: client, at: addedIndex) }
		}

		if isOnlyClient {
			notifyObservers { $0.world(self, requestsSelectionOf: client) }
		}

		notifyObservers {
			$0.worldClientListDidChange(self)
			$0.worldNavigationListDidChange(self)
		}
		postClientListWasModifiedNotification()

		return client
	}

	public func createChannel(with config: ChannelConfig, on client: IRCClient) -> IRCChannel {
		createChannel(with: config, on: client, add: true, adjust: true, reload: true)
	}

	public func createChannel(
		with config: ChannelConfig,
		on client: IRCClient,
		add: Bool,
		adjust: Bool,
		reload: Bool
	) -> IRCChannel {
		let channel = Channel(config: config)
		channel.associatedClient = client

		if add {
			client.add(channel)
		}

		if reload, let index = client.channelList.firstIndex(where: { $0 === channel }) {
			notifyObservers { $0.world(self, didAddChannel: channel, on: client, at: index) }
		}

		if adjust {
			notifyObservers {
				$0.worldRequestsSelectionAdjustment(self)
				$0.worldNavigationListDidChange(self)
			}
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

		let config = ChannelConfig(channelName: nickname, type: type)

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

	// MARK: - Ordering

	/// Moves a client within the list and tells observers to follow.
	func moveClient(from oldIndex: Int, to newIndex: Int) {
		guard clients.indices.contains(oldIndex) else { return }

		let client = clients.remove(at: oldIndex)
		clients.insert(client, at: min(newIndex, clients.count))

		postClientListWasModifiedNotification()
		notifyObservers {
			$0.world(self, didMoveClientFrom: oldIndex, to: newIndex)
			$0.worldNavigationListDidChange(self)
		}
	}

	/// Moves a channel within its client and tells observers to follow.
	func moveChannel(on client: IRCClient, from oldIndex: Int, to newIndex: Int) {
		var channels = client.channelList
		guard channels.indices.contains(oldIndex) else { return }

		let channel = channels.remove(at: oldIndex)
		channels.insert(channel, at: min(newIndex, channels.count))
		client.channelList = channels

		notifyObservers {
			$0.world(self, didMoveChannelOn: client, from: oldIndex, to: newIndex)
			$0.worldNavigationListDidChange(self)
		}
	}

	/// Replaces a client's channels wholesale — a sort, not a drag.
	func setChannelList(_ channels: [IRCChannel], on client: IRCClient) {
		guard channels != client.channelList else { return }

		client.channelList = channels
		environment.output?.reloadServerListItems(for: client)
		notifyObservers { $0.worldNavigationListDidChange(self) }
	}

	// MARK: - Destruction

	private func selectOtherBeforeDestroy(_ target: IRCTreeItem) {
		if target.isClient {
			notifyObservers { $0.world(self, requestsGroupDeselectionOf: target) }
		} else {
			notifyObservers { $0.world(self, requestsDeselectionOf: target) }
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
		notifyObservers { $0.world(self, didRemoveClient: client) }

		clients.removeAll { $0 === client }

		postClientListWasModifiedNotification()
		notifyObservers {
			$0.worldClientListDidChange(self)
			$0.worldNavigationListDidChange(self)
		}
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
			selectOtherBeforeDestroy(channel)
		}

		channel.prepareForPermanentDestruction()
		if client.lastSelectedChannel === channel {
			client.lastSelectedChannel = nil
		}

		if reload {
			notifyObservers { $0.world(self, didRemoveChannel: channel, on: client) }
			client.remove(channel)
			notifyObservers {
				$0.worldRequestsSelectionAdjustment(self)
				$0.worldNavigationListDidChange(self)
			}
		}
	}
}
