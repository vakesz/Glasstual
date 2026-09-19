// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import os

/// What tearing a conversation down does beyond removing it. Named options rather
/// than positional booleans, so a call site says which of them it means.
struct ConversationDestruction: OptionSet, Sendable {
	let rawValue: Int

	/// Move the selection off the conversation and redraw the navigation list. The
	/// session drops the conversation either way; this names the redraw.
	static let reloadsSidebar = Self(rawValue: 1 << 0)
	/// Send `PART` for a channel that is still joined.
	static let partsChannel = Self(rawValue: 1 << 1)
	/// Keep the conversation's logs, keychain item and input history.
	static let preservesLocalData = Self(rawValue: 1 << 2)

	/// What the user asking to close a conversation means.
	static let `default`: Self = [.reloadsSidebar, .partsChannel]
}

private enum ChatSessionTiming {
	static let autoConnectDelay: UInt = 1
	static let reconnectAfterWakeupDelay: UInt = 8
	static let savePeriodicallyThreshold: CFAbsoluteTime = 300
}

extension Notification.Name {
	static let chatSessionListWasModified = Notification.Name("Glasstual.chatSessionListWasModified")
	static let chatSessionWillDestroySession = Notification.Name("Glasstual.chatSessionWillDestroySession")
}

/** The application's one chat session: every server session it has open, and
 their lifecycle.

 It makes and destroys server sessions and their conversations, persists the
 configuration list, republishes the settings snapshot, keeps the process awake
 while a connection is logged in, counts what the connections send and receive,
 and answers sleep, wake, reachability and termination. What is drawn from all
 that is the window layer's business: it hears about the shape of the list
 through ``ChatSessionPresenting``. */
@MainActor
final class ChatSession {
	private var storedSessions: [ServerSession] = []

	/// What every connection has sent and received this session.
	private var traffic = ConnectionTraffic()
	/// The idle-sleep assertion held while a connection is logged in.
	private let sleepPrevention = SleepPrevention()

	/// When the session list was last written by the periodic save.
	private var savePeriodicallyLastSave = CFAbsoluteTimeGetCurrent()
	private let notifications = NotificationSubscriptions()
	private var observers = ChatSessionPresenterList()

	/** The environment handed to every session this chat session makes. The setting
	 half is refreshed from the defaults store whenever it reports a write. */
	var environment: ChatEnvironment

	var isImportingConfiguration = false

	/** The application's chat session takes `ChatServices.shared`, so the window
	 and menus only have to be installed once for both it and the protocol-layer
	 entry points that have no session to ask. A chat session built with a
	 services box of its own — a test fixture's — is invisible to them. */
	init(environment: ChatEnvironment = .application) {
		self.environment = environment
		self.environment.services.chatSession = self
	}

	var sessions: [ServerSession] {
		get {
			storedSessions
		}
		set {
			storedSessions = newValue
			postSessionListWasModifiedNotification()
		}
	}

	var sessionCount: UInt {
		UInt(sessions.count)
	}

	// MARK: - Observers

	func addObserver(_ observer: any ChatSessionPresenting) {
		observers.add(observer)
	}

	func removeObserver(_ observer: any ChatSessionPresenting) {
		observers.remove(observer)
	}

	/// Delivers `event` to the observers registered when it was raised. One an
	/// event handler registers hears the events after it.
	private func notifyObservers(_ event: (any ChatSessionPresenting) -> Void) {
		observers.liveObservers.forEach(event)
		observers.pruneReleased()
	}

	/// Republishes the navigation list after a session changed shape on its own.
	func noteSidebarDidChange() {
		notifyObservers { $0.chatSessionSidebarDidChange(self) }
	}

	// MARK: - Configuration

	func setupConfiguration() {
		isImportingConfiguration = true

		notifyObservers { $0.chatSessionWillBeginBulkUpdate(self) }

		for dictionary in SettingsKeys.Sessions.serverSessions.propertyListValue?.array?.compactMap(\.dictionary) ?? [] {
			guard let config = PropertyListModel.decode(ServerConfig.self, from: dictionary) else {
				continue
			}

			_ = createSession(with: config)
		}

		notifyObservers { $0.chatSessionDidEndBulkUpdate(self) }

		isImportingConfiguration = false
		setupOtherServices()
	}

	private func setupOtherServices() {
		notifications
			.observe(.userDefaultsDidChange) { [weak self] notification in
				self?.userDefaultsDidChange(notification)
			}
		notifications.observe(.mainWindowAppearanceChanged) { [weak self] notification in
			self?.mainWindowAppearanceChanged(notification)
		}
	}

	private var serverConfigs: [[String: PropertyListValue]] {
		sessions.map { $0.configurationDictionary() }
	}

	func save() {
		SettingsKeys.Sessions.serverSessions.propertyListValue = .array(serverConfigs.map(PropertyListValue.dictionary))
	}

	func savePeriodically() {
		let now = CFAbsoluteTimeGetCurrent()
		guard savePeriodicallyLastSave + ChatSessionTiming.savePeriodicallyThreshold < now else {
			return
		}

		savePeriodicallyLastSave = now
		save()
	}

	func prepareForApplicationTermination() {
		notifications.cancelAll()

		sleepPrevention.refresh(shouldHold: false)

		for session in sessions {
			session.prepareForApplicationTermination()
		}
	}

	private func userDefaultsDidChange(_: Notification) {
		/* Every branch the connection code takes on a setting reads the
		 snapshot, so it is refreshed before anything else reacts to the write. */
		refreshEnvironmentSettings()
		refreshSleepPrevention()
	}

	// MARK: - Sleep

	/// Called when a session's registration state changes, which is the only
	/// thing the setting reads besides itself.
	func noteLoginStateChanged() {
		refreshSleepPrevention()
	}

	private func refreshSleepPrevention() {
		sleepPrevention.refresh(
			shouldHold: SettingsKeys.Connection.preventSleepWhileConnected.value
				&& sessions.contains(where: \.isLoggedIn)
		)
	}

	/// Re-reads the defaults store and republishes the snapshot to every session.
	func refreshEnvironmentSettings() {
		applySettings(.current())
	}

	/// Republishes `settings` to this chat session and every session it made.
	/// Returns whether anything changed.
	@discardableResult
	func applySettings(_ settings: ChatSettings) -> Bool {
		guard settings != environment.settings else {
			return false
		}

		environment.settings = settings

		for session in sessions {
			session.environment.settings = settings
		}

		return true
	}

	private func mainWindowAppearanceChanged(_: Notification) {
		environment.output?.notifyAllViewsAppearanceDidChange()
	}

	// MARK: - Lifecycle

	private func postSessionListWasModifiedNotification() {
		NotificationCenter.default.post(name: .chatSessionListWasModified, object: self)
	}

	func autoConnect(afterWakeup afterWakeUp: Bool) {
		let ghostModeIsOn = environment.services.applicationState?.ghostModeIsOn ?? false
		guard ghostModeIsOn == false || afterWakeUp else {
			return
		}

		var delay = afterWakeUp ? ChatSessionTiming.reconnectAfterWakeupDelay : 0

		for session in sessions {
			let isAutoConnecting = afterWakeUp == false && session.config.autoConnect
			let isWakingFromSleep = afterWakeUp
				&& session.config.autoSleepModeDisconnect
				&& session.disconnectType == .computerSleep

			guard isWakingFromSleep || isAutoConnecting else {
				continue
			}

			session.autoConnect(withDelay: delay, afterWakeUp: afterWakeUp)
			delay += ChatSessionTiming.autoConnectDelay
		}
	}

	func prepareForSleep() {
		guard environment.settings.disconnectOnSleep else {
			return
		}

		for session in sessions where session.isConnected {
			session.disconnectType = .computerSleep
			session.quit()
		}
	}

	func prepareForScreenSleep() {
		guard environment.settings.awayOnScreenSleep else {
			return
		}

		for session in sessions {
			session.setAwayForScreenSleep()
		}
	}

	func wakeFromScreenSleep() {
		for session in sessions {
			session.clearAwayAfterScreenSleep()
		}
	}

	func noteReachabilityChanged(_ reachable: Bool) {
		for session in sessions {
			session.noteReachabilityChanged(reachable)
		}
	}

	/** Answers a setting change: the environment every session reads from is
	 refreshed, and each session is handed what the change obliges it to redo.

	 The action is carried rather than looked up because the connections hold
	 state -- member orderings, unread counts, open transcript files -- that the
	 window draws, and it has to be current before anything is told to redraw. */
	func settingsChanged(_ action: SettingsReloadAction) {
		if action.contains(.settingsChanged) {
			refreshEnvironmentSettings()
			notifyObservers { $0.chatSessionSettingsDidChange(self) }
		}

		for session in sessions {
			session.settingsChanged(action)
		}
	}

	// MARK: - Traffic counters

	var messagesSent: UInt {
		traffic.messagesSent
	}

	var messagesReceived: UInt {
		traffic.messagesReceived
	}

	var bandwidthIn: UInt64 {
		traffic.bandwidthIn
	}

	var bandwidthOut: UInt64 {
		traffic.bandwidthOut
	}

	func noteMessageSent(length: UInt) {
		traffic.noteSent(length: length)
	}

	func noteMessageReceived(length: UInt) {
		traffic.noteReceived(length: length)
	}

	// MARK: - Sidebar items

	func findItem(withId itemId: String?) -> ChatItem? {
		guard let itemId else {
			return nil
		}

		for session in sessions {
			if session.uniqueIdentifier == itemId {
				return session
			}

			if let conversation = session.conversationList.first(where: { $0.uniqueIdentifier == itemId }) {
				return conversation
			}
		}

		return nil
	}

	func findSession(withId sessionId: String) -> ServerSession? {
		findItem(withId: sessionId) as? ServerSession
	}

	func findConversation(withId conversationId: String, onSessionWithId sessionId: String) -> Conversation? {
		guard let session = findSession(withId: sessionId) else { return nil }
		return session.conversationList.first { $0.uniqueIdentifier == conversationId }
	}

	// MARK: - Factory

	func createSession(with config: ServerConfig) -> ServerSession {
		let session = ServerSession(config: config, environment: environment)
		session.conversationList = session.config.conversationList.map {
			createConversation(with: $0, on: session, add: false, adjust: false, reload: false)
		}

		storedSessions.append(session)
		let addedIndex = storedSessions.firstIndex { $0 === session }
		let isOnlySession = sessions.count == 1

		if let addedIndex {
			notifyObservers { $0.chatSession(self, didAddSession: session, at: addedIndex) }
		}

		if isOnlySession {
			notifyObservers { $0.chatSession(self, requestsSelectionOf: session) }
		}

		notifyObservers {
			$0.chatSessionListDidChange(self)
			$0.chatSessionSidebarDidChange(self)
		}
		postSessionListWasModifiedNotification()

		return session
	}

	func createConversation(
		with config: ConversationConfig,
		on session: ServerSession,
		add: Bool = true,
		adjust: Bool = true,
		reload: Bool = true
	) -> Conversation {
		let conversation = Conversation(config: config)
		conversation.associatedSession = session
		session.resolveSecretKey(for: config)

		if add {
			session.add(conversation)
		}

		if reload, let index = session.conversationList.firstIndex(where: { $0 === conversation }) {
			notifyObservers { $0.chatSession(self, didAddConversation: conversation, on: session, at: index) }
		}

		if adjust {
			notifyObservers {
				$0.chatSessionRequestsSelectionAdjustment(self)
				$0.chatSessionSidebarDidChange(self)
			}
		}

		return conversation
	}

	func createDirectConversation(
		_ nickname: String,
		on session: ServerSession,
		as type: ConversationKind = .direct
	) -> Conversation {
		precondition(type == .direct || type == .console || type == .directChat)

		let config = ConversationConfig(name: nickname, type: type)

		let conversation = createConversation(with: config, on: session, add: true, adjust: true, reload: true)
		if session.isLoggedIn, conversation.isDirect {
			conversation.activate()
			session.trackDirectPeer(nickname)
		}

		return conversation
	}

	// MARK: - Ordering

	/// Moves a session within the list and tells observers to follow.
	func moveSession(from oldIndex: Int, to newIndex: Int) {
		guard storedSessions.indices.contains(oldIndex) else { return }

		let session = storedSessions.remove(at: oldIndex)
		/* Observers are told where the session landed, not where it was asked to
		 go: one that indexed its own rows by the requested position would read
		 past the end. */
		let insertedIndex = min(newIndex, storedSessions.count)
		storedSessions.insert(session, at: insertedIndex)

		postSessionListWasModifiedNotification()
		notifyObservers {
			$0.chatSession(self, didMoveSessionFrom: oldIndex, to: insertedIndex)
			$0.chatSessionSidebarDidChange(self)
		}
	}

	/// Moves a conversation within its session and tells observers to follow.
	func moveConversation(on session: ServerSession, from oldIndex: Int, to newIndex: Int) {
		var conversations = session.conversationList
		guard conversations.indices.contains(oldIndex) else { return }

		let moved = conversations.remove(at: oldIndex)
		let insertedIndex = min(newIndex, conversations.count)
		conversations.insert(moved, at: insertedIndex)
		session.conversationList = conversations

		notifyObservers {
			$0.chatSession(self, didMoveConversationOn: session, from: oldIndex, to: insertedIndex)
			$0.chatSessionSidebarDidChange(self)
		}
	}

	/// Replaces a session's conversations wholesale — a sort, not a drag.
	func setConversationList(_ conversations: [Conversation], on session: ServerSession) {
		guard conversations != session.conversationList else { return }

		session.conversationList = conversations
		environment.output?.reloadSidebarItems(for: session)
		notifyObservers { $0.chatSessionSidebarDidChange(self) }
	}

	// MARK: - Destruction

	private func selectOtherBeforeDestroy(_ target: ChatItem) {
		if target.isSession {
			notifyObservers { $0.chatSession(self, requestsGroupDeselectionOf: target) }
		} else {
			notifyObservers { $0.chatSession(self, requestsDeselectionOf: target) }
		}
	}

	func destroySession(_ session: ServerSession, preservingLocalData: Bool = false) {
		if session.isConnecting || session.isConnected {
			session.addDisconnectCallback { [weak self, weak session] in
				guard let session else {
					return
				}
				self?.destroySession(session, preservingLocalData: preservingLocalData)
			}
			session.quit()
			return
		}

		NotificationCenter.default.post(
			name: .chatSessionWillDestroySession,
			object: session
		)
		selectOtherBeforeDestroy(session)
		session.prepareForRemoval(preservingLocalData: preservingLocalData)
		notifyObservers { $0.chatSession(self, didRemoveSession: session) }

		storedSessions.removeAll { $0 === session }

		postSessionListWasModifiedNotification()
		notifyObservers {
			$0.chatSessionListDidChange(self)
			$0.chatSessionSidebarDidChange(self)
		}
	}

	func destroyConversation(_ conversation: Conversation, options: ConversationDestruction = .default) {
		let reload = options.contains(.reloadsSidebar)
		let partsChannel = options.contains(.partsChannel)
		let preservingLocalData = options.contains(.preservesLocalData)

		/* The session drops what it holds for this conversation before anything
		 tears it down. It used to hear that through the notification below, which
		 is delivered a turn later — after the conversation had gone. */
		conversation.associatedSession?.willDestroyConversation(conversation)

		guard let session = conversation.associatedSession else {
			return
		}

		if partsChannel {
			session.part(conversation)
		}

		if reload {
			selectOtherBeforeDestroy(conversation)
		}

		conversation.prepareForRemoval(preservingLocalData: preservingLocalData)
		if session.lastSelectedConversation === conversation {
			session.lastSelectedConversation = nil
		}

		/* `reload` names a redraw. The session drops the conversation either way: one
		 that still listed a destroyed conversation would write it back out with its
		 configuration, and nothing could reach it again. */
		session.remove(conversation)

		// Removal also releases the window's controller, even during a batched redraw.
		notifyObservers { $0.chatSession(self, didRemoveConversation: conversation, on: session) }
		if reload {
			notifyObservers {
				$0.chatSessionRequestsSelectionAdjustment(self)
				$0.chatSessionSidebarDidChange(self)
			}
		}
	}
}
