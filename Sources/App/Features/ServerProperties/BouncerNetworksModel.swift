// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import Observation

/** The live side of the Bouncer Networks pane.

 The rest of the connection sheet edits a configuration that is saved when the
 sheet closes. A bouncer's networks live on the bouncer: adding, changing or
 deleting one is a command sent to it now, and what the pane lists is what the
 bouncer last reported. The model follows the session for that, and answers
 only for the connection it was made for. */
@MainActor
@Observable
final class BouncerNetworksModel {
	private(set) var networks: [BouncerNetwork] = []
	private(set) var failure: BouncerFailure?
	/// Whether the connection is signed in to a bouncer that lists networks.
	private(set) var canManage = false
	/// The account connection a network connection belongs to, by name.
	private(set) var parentName: String?
	/// Whether that account connection has left the sidebar.
	private(set) var parentIsHidden = false

	@ObservationIgnored private weak var session: ServerSession?
	@ObservationIgnored private let notifications = NotificationSubscriptions()

	init(session: ServerSession) {
		self.session = session
		refresh()
		notifications.observe(ServerSessionBouncerNetworksDidChange.self, of: session) { [weak self] _ in
			self?.refresh()
		}
		notifications.observe(SessionCapabilitiesDidChange.self, of: session) { [weak self] _ in
			self?.refresh()
		}
	}

	func refresh() {
		guard let session else { return }
		networks = session.bouncer.networks.networks
		failure = session.bouncer.lastFailure
		canManage = session.canManageBouncerNetworks
		let parent = session.config.bouncerNetwork.flatMap {
			session.chatSession?.findSession(withId: $0.parentIdentifier)
		}
		parentName = parent?.label
		parentIsHidden = parent?.config.bouncerHidesParent == true
	}

	func reload() {
		session?.requestBouncerNetworks()
	}

	func add(_ edit: BouncerNetworkEdit) {
		session?.addBouncerNetwork(edit)
	}

	func change(_ network: BouncerNetwork, with edit: BouncerNetworkEdit) {
		session?.changeBouncerNetwork(network.id, with: edit)
	}

	func remove(_ network: BouncerNetwork) {
		session?.deleteBouncerNetwork(network.id)
	}

	/// Puts the account connection back in the sidebar, from one of its networks.
	func showParentConnection() {
		guard let binding = session?.config.bouncerNetwork,
		      let parent = session?.chatSession?.findSession(withId: binding.parentIdentifier)
		else { return }
		var config = parent.config
		config.bouncerHidesParent = false
		parent.updateConfig(config)
		refresh()
	}
}
