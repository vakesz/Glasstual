// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import os

enum ServerConfigPolicy {
	static func shouldStoreConversation(
		isConsole: Bool,
		isDirectChat: Bool,
		isChannel: Bool,
		rememberDirectConversations: Bool,
		isFavorite: Bool = false
	) -> Bool {
		guard isConsole == false, isDirectChat == false else { return false }
		return isChannel || rememberDirectConversations || isFavorite
	}

	static func storedConversationConfigurations(
		from conversations: [Conversation],
		rememberDirectConversations: Bool
	) -> [ConversationConfig] {
		conversations.compactMap { conversation in
			guard shouldStoreConversation(
				isConsole: conversation.isConsole,
				isDirectChat: conversation.isDirectChat,
				isChannel: conversation.isChannel,
				rememberDirectConversations: rememberDirectConversations,
				isFavorite: conversation.config.isFavorite
			) else { return nil }
			return conversation.config
		}
	}
}

private let serverConfigLogger = Logger(
	subsystem: LogSubsystem.current,
	category: "ServerConfigLifecycle"
)

private let sessionTerminationLogger = Logger(
	subsystem: LogSubsystem.current,
	category: "Termination"
)

/** Why a session's configuration is being replaced.

 The three reasons differ in what survives the replacement, which used to be
 spelled out at each call site as a pair of booleans whose combinations did not
 all mean anything. */
enum ConfigUpdate: Sendable {
	/// The user edited the configuration in Server Properties. What the edit
	/// dropped is dropped, keychain items for removed endpoints included.
	case edit
	/// A settings import or a transfer from another Mac laid a configuration
	/// over the live one. It says what the settings are, not what the whole
	/// machine is, so local data and live conversations it does not mention
	/// are kept.
	case transfer
	/// A snapshot was restored. It is a statement about the whole machine, so
	/// a live conversation the snapshot does not list goes away with it —
	/// while its logs and secrets, which the snapshot never carried, stay.
	case restore

	/// Whether keychain items and logs outlive the endpoints and conversations
	/// the new configuration leaves out.
	var preservesLocalData: Bool {
		self != .edit
	}

	/// Whether a live conversation the new configuration does not list
	/// survives it.
	var preservesUnmatchedConversations: Bool {
		self != .restore
	}
}

@MainActor
extension ServerSession {
	func updateConfig(_ newConfig: ServerConfig, for reason: ConfigUpdate = .edit) {
		let preservingLocalData = reason.preservesLocalData
		let preservingUnmatchedConversations = reason.preservesUnmatchedConversations

		// A restore also removes live conversations its configuration left out.
		guard isTerminating == false, config != newConfig || !preservingUnmatchedConversations else { return }
		guard config.uniqueIdentifier == newConfig.uniqueIdentifier else {
			serverConfigLogger.error("Tried to load configuration for incorrect session")
			return
		}

		let currentConfig = config
		config = newConfig
		reconcileConversations(with: newConfig.conversationList, preservingLocalData: preservingLocalData,
		                       preservingUnmatchedConversations: preservingUnmatchedConversations)
		reconcileServers(
			from: currentConfig.serverList,
			to: newConfig.serverList,
			preservingLocalData: preservingLocalData
		)
		reloadSidebarItems()

		chatSession?.noteSidebarDidChange()
		writePasswordsToKeychain()
		output?.updateTitle(for: self)
		clearAddressBookCache()
		populateISONTrackedUsersList()
		NotificationCenter.default.post(name: .serverSessionConfigWasUpdated, object: self)
	}

	func reloadSidebarItems() {
		output?.reloadSidebarItems(for: self)
	}

	func writePasswordsToKeychain() {
		let edits = config.pendingKeychainEdits
		KeychainPersistence.shared.persist(edits) { [weak self] committed in
			guard let self else { return }
			let acknowledged = committed.filter { config.pendingKeychainEdits[$0.key] == $0.value }
			sessionCredentials.apply(acknowledged)
			config.acknowledgeKeychainEdits(acknowledged)
		}
	}

	func updateStoredConfiguration() {
		guard configurationIsStale else { return }

		config.lastMessageServerTime = lastMessageServerTime
		config.sidebarItemExpanded = sidebarItemIsExpanded
	}

	func updateStoredConversationList() {
		rebuildConversationIndex()
		config.conversationList = ServerConfigPolicy.storedConversationConfigurations(
			from: conversationList,
			rememberDirectConversations: environment.settings.remembersDirectConversations
		)
		NotificationCenter.default.post(name: .serverSessionConversationListWasModified, object: self)
	}

	func configurationDictionary() -> [String: PropertyListValue] {
		updateStoredConfiguration()
		return config.dictionaryValue
	}

	func prepareForApplicationTermination() {
		guard isTerminating == false else { return }
		isTerminating = true
		let sessionIdentifier = uniqueIdentifier
		sessionTerminationLogger.debug("Preparing session: <\(sessionIdentifier, privacy: .public)>")
		sessionTerminationLogger.debug("[\(sessionIdentifier, privacy: .public)] Closing dialogs")
		closeDialogs()

		guard isConnecting || isConnected else {
			prepareForApplicationTerminationPostflight()
			return
		}

		sessionTerminationLogger.debug("[\(sessionIdentifier, privacy: .public)] Performing disconnect")
		addDisconnectCallback { [weak self] in
			self?.prepareForApplicationTerminationPostflight()
		}
		socket?.beginCloseDeadline()
		quit()
	}

	func prepareForApplicationTerminationPostflight() {
		guard terminationPostflightFinished == false else { return }
		terminationPostflightFinished = true
		let sessionIdentifier = uniqueIdentifier
		sessionTerminationLogger.debug("[\(sessionIdentifier, privacy: .public)] Closing log file")
		closeLogFile()
		sessionTerminationLogger.debug("[\(sessionIdentifier, privacy: .public)] Emptying Address Book cache")
		clearAddressBookCache()
		sessionTerminationLogger.debug("[\(sessionIdentifier, privacy: .public)] Removing all tracked users")
		clearTrackedUsers()
		let conversations = conversationList
		sessionTerminationLogger.debug(
			"[\(sessionIdentifier, privacy: .public)] Preparing conversations: \(conversations.count, privacy: .public)"
		)
		conversations.forEach { $0.prepareForApplicationTermination() }
		let viewIdentifier = presentation?.presentationIdentifier ?? ""
		sessionTerminationLogger.debug(
			"[\(sessionIdentifier, privacy: .public)] Preparing view controller: <\(viewIdentifier, privacy: .public)>"
		)
		presentation?.tearDown(.applicationTermination)
		sessionTerminationLogger.debug("[\(sessionIdentifier, privacy: .public)] Decrementing session count")
		environment.services.applicationState?.noteSessionDidFinishTerminating()
	}

	func prepareForRemoval(preservingLocalData: Bool) {
		// Cancels the session's scheduled work and stops its timers.
		isTerminating = true
		socket?.close()
		closeDialogs()
		closeLogFile()
		clearAddressBookCache()
		clearTrackedUsers()
		if !preservingLocalData {
			KeychainPersistence.shared.persist(Dictionary(
				config.keychainItems.map { ($0, PendingKeychainSecret.cleared) },
				uniquingKeysWith: { _, newest in newest }
			))
			output?.destroyInputHistory(for: self)
		}
		conversationList.forEach { $0.prepareForRemoval(preservingLocalData: preservingLocalData) }
		presentation?.tearDown(preservingLocalData ? .preservingRemoval : .permanentRemoval)
	}

	func closeDialogs() {
		channelListPresentation?.closeChannelList(for: self)
		output?.closeSheets(for: self)
	}

	func settingsChanged(_ action: SettingsReloadAction) {
		conversationList.forEach { $0.settingsChanged(action) }

		if action.contains(.settingsChanged), monitorAwayStatus == false {
			resetAwayStatusForUsers()
		}

		/* The cache exists so the highlight sheet can be opened after the fact.
		 With the sheet turned off there is nothing to open it for. */
		if action.contains(.highlightLogging), environment.settings.logHighlights == false {
			clearCachedHighlights()
		}

		if action.contains(.logTranscripts) {
			reopenLogFileIfNeeded()
		}

		if action.contains(.scrollbackVisibleLimit) {
			transcriptController?.changeScrollbackLimit()
		}
	}

	/// Called by `ChatSession` before the conversation is torn down, so what the
	/// session holds for it is dropped while the conversation is still whole.
	func willDestroyConversation(_ conversation: Conversation) {
		guard conversation.associatedSession === self else { return }
		if conversation.isDirect {
			stopTrackingDirectPeer(conversation.name)
		}
		clearZNCPlayback(for: conversation)
		if hiddenCommandResponsesConsole === conversation {
			hiddenCommandResponsesConsole = nil
		}
		if rawDataLogConsole === conversation {
			rawDataLogConsole = nil
		}
	}

	private func reconcileConversations(with configurations: [ConversationConfig], preservingLocalData: Bool,
	                                    preservingUnmatchedConversations: Bool)
	{
		var remaining = conversationList
		var updated: [Conversation] = []
		var insertedNames = Set<String>()
		guard let chatSession else { return }

		for stored in configurations where insertedNames.insert(stored.name).inserted {
			if let conversation = findConversation(stored.name, in: remaining),
			   conversation.uniqueIdentifier == stored.uniqueIdentifier,
			   conversation.name == stored.name,
			   conversation.type == stored.type
			{
				conversation.updateConfig(
					stored,
					fireChangedNotification: false,
					updateStoredConversationList: false
				)
				remaining.removeAll { $0 === conversation }
				updated.append(conversation)
			} else {
				updated.append(
					chatSession.createConversation(with: stored, on: self, add: false, adjust: false, reload: false)
				)
			}
		}

		for conversation in remaining {
			let replacedByName = findConversation(conversation.name, in: updated) != nil
			if !preservingUnmatchedConversations || conversation.isChannel || replacedByName {
				chatSession.destroyConversation(
					conversation,
					options: preservingLocalData ? [.partsChannel, .preservesLocalData] : [.partsChannel]
				)
			} else {
				updated.append(conversation)
			}
		}
		conversationList = updated
	}

	private func reconcileServers(from oldServers: [ServerEndpoint], to newServers: [ServerEndpoint], preservingLocalData: Bool) {
		/* Explicit edits delete removed endpoints' passwords after any active
		 connection ends. Transfers retain them so restoring a backup recovers
		 the same local credentials. */
		let newIdentifiers = Set(newServers.map(\.uniqueIdentifier))
		for oldServer in oldServers where !preservingLocalData && !newIdentifiers.contains(oldServer.uniqueIdentifier) {
			if oldServer.uniqueIdentifier == server?.uniqueIdentifier {
				retiredServerKeychainItems.insert(oldServer.keychainItem)
			} else {
				KeychainPersistence.shared.persist([oldServer.keychainItem: .cleared])
			}
		}

		if newServers.isEmpty {
			lastServerSelected = nil
		} else {
			writePasswordsToKeychain()
		}
	}
}
