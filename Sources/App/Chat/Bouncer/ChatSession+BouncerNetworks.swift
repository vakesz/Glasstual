// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/** The connections a soju account's networks turn into.

 A parent reports what it heard; the chat session owns the list of connections,
 so it is the one to make, update and retire the network connections. */
@MainActor
extension ChatSession {
	/// Seconds between the staggered starts of connections made by one listing.
	private static let bouncerNetworkConnectDelay: UInt = 1

	/// The network connections of `parent`, in the order the list holds them.
	func bouncerChildren(of parent: ServerSession) -> [ServerSession] {
		BouncerHierarchy(sessions: sessions).children(of: parent)
	}

	/** Deletes a connection together with the networks nested under it.

	 The networks go the way a deleted network does: their logs and history stay
	 on disk and come back, read-only, if the bouncer lists them again. Only the
	 keychain items they own are removed — their channels' keys — never the
	 account's secrets, which the account's own deletion clears. */
	func destroySessionWithBouncerNetworks(_ session: ServerSession) {
		for network in bouncerChildren(of: session) {
			KeychainPersistence.shared.persist(Dictionary(
				network.config.ownedKeychainItems.map { ($0, PendingKeychainSecret.cleared) },
				uniquingKeysWith: { _, newest in newest }
			))
			destroySession(network, preservingLocalData: true)
		}
		destroySession(session)
	}

	/// Brings the network connections of `parent` in line with what it heard.
	func applyBouncerChanges(_ changes: BouncerNetworkSet.Changes, from parent: ServerSession) {
		var delay: UInt = 0
		for network in changes.added + changes.changed {
			let isNew = upsertBouncerChild(for: network, of: parent, connectingAfter: delay)
			if isNew {
				delay += Self.bouncerNetworkConnectDelay
			}
		}

		var retired = Set(changes.removed)
		if let listed = changes.completeListing {
			let known = Set(listed)
			for child in bouncerChildren(of: parent) {
				if let binding = child.config.bouncerNetwork, known.contains(binding.networkIdentifier) == false {
					retired.insert(binding.networkIdentifier)
				}
			}
		}
		for identifier in retired {
			retireBouncerChild(networkIdentifier: identifier, of: parent)
		}

		save()
		noteSidebarDidChange()
	}

	/// Lays the parent's connection settings over each of its networks, after
	/// the parent was reconfigured or the list was loaded.
	func propagateBouncerParentSettings(from parent: ServerSession) {
		guard parent.config.bouncerNetwork == nil else { return }
		for child in bouncerChildren(of: parent) {
			let merged = child.config.inheritingConnectionSettings(from: parent.config)
			child.updateConfig(merged, for: .transfer)
		}
	}

	/// Returns whether a connection was made.
	private func upsertBouncerChild(for network: BouncerNetwork, of parent: ServerSession, connectingAfter delay: UInt) -> Bool {
		let identifier = ServerConfig.bouncerNetworkConnectionIdentifier(
			parent: parent.uniqueIdentifier, network: network.id
		)

		if let child = findSession(withId: identifier) {
			var config = child.config.inheritingConnectionSettings(from: parent.config)
			config.connectionName = network.displayName
			config.bouncerNetwork?.isRemoved = false
			child.updateConfig(config, for: .transfer)
			child.bouncer.networkState = network.state
			child.bouncer.networkError = network.error
			return false
		}

		let child = createSession(with: parent.config.derivingBouncerNetwork(network))
		child.bouncer.networkState = network.state
		child.bouncer.networkError = network.error
		let ghostModeIsOn = environment.services.applicationState?.ghostModeIsOn ?? false
		if parent.config.autoConnect, ghostModeIsOn == false {
			child.autoConnect(withDelay: delay, afterWakeUp: false)
		}
		return true
	}

	/// The network is gone from the bouncer. Its conversations and history stay
	/// readable; its connection is closed and cannot be opened again.
	private func retireBouncerChild(networkIdentifier: String, of parent: ServerSession) {
		let identifier = ServerConfig.bouncerNetworkConnectionIdentifier(
			parent: parent.uniqueIdentifier, network: networkIdentifier
		)
		guard let child = findSession(withId: identifier), child.config.bouncerNetwork?.isRemoved == false else { return }

		var config = child.config
		config.bouncerNetwork?.isRemoved = true
		child.updateConfig(config, for: .transfer)
		child.bouncer.networkState = nil
		child.bouncer.networkError = nil
		child.printDebugInformation(toConsole: String(localized: .Bouncer.networkRemovedNotice))
		if child.isConnecting || child.isConnected {
			child.quit()
		}
	}
}
