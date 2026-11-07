// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** The networks a bouncer account is known to have, and what changed when it
 last said something about them.

 A listing replaces the set; a notification adds, changes or removes one
 network. Both are reduced to the same ``Changes`` so the session reacts to a
 difference rather than to the shape of what arrived. The set is bounded: a
 bouncer that names more networks than ``BouncerNetworkAttributes/maximumNetworks``
 has the surplus ignored. */
nonisolated struct BouncerNetworkSet: Equatable, Sendable {
	enum Update: Equatable, Sendable {
		/// The complete listing, as the answer to `LISTNETWORKS`.
		case snapshot([BouncerNetwork])
		/// One network was added or its attributes changed.
		case upsert(BouncerNetwork)
		/// A notification: only the attributes that changed, merged into the
		/// network. For a network not known yet it is an addition, described by
		/// whatever the notification carries.
		case update(String, [String: String])
		/// One network was deleted.
		case remove(String)
	}

	struct Changes: Equatable, Sendable {
		var added: [BouncerNetwork] = []
		var changed: [BouncerNetwork] = []
		var removed: [String] = []
		/// The identifiers of the whole listing, when the update was one. A
		/// network this account knew before that is missing from it is gone,
		/// even if this set never held it.
		var completeListing: [String]?

		var isEmpty: Bool {
			added.isEmpty && changed.isEmpty && removed.isEmpty
		}
	}

	private(set) var networks: [BouncerNetwork] = []

	func network(withIdentifier identifier: String) -> BouncerNetwork? {
		networks.first { $0.id == identifier }
	}

	mutating func apply(_ update: Update) -> Changes {
		switch update {
		case let .snapshot(listing):
			applySnapshot(listing)
		case let .upsert(network):
			applyUpsert(network)
		case let .update(identifier, attributes):
			applyUpdate(identifier, attributes)
		case let .remove(identifier):
			applyRemoval(identifier)
		}
	}

	private mutating func applySnapshot(_ listing: [BouncerNetwork]) -> Changes {
		var next: [BouncerNetwork] = []
		for network in listing {
			if let index = next.firstIndex(where: { $0.id == network.id }) {
				next[index] = network
			} else if next.count < BouncerNetworkAttributes.maximumNetworks {
				next.append(network)
			}
		}

		var changes = Changes()
		for network in next {
			if let known = self.network(withIdentifier: network.id) {
				if known != network {
					changes.changed.append(network)
				}
			} else {
				changes.added.append(network)
			}
		}
		changes.removed = networks.map(\.id).filter { identifier in
			next.contains { $0.id == identifier } == false
		}
		networks = next
		changes.completeListing = next.map(\.id)
		return changes
	}

	private mutating func applyUpsert(_ network: BouncerNetwork) -> Changes {
		if let index = networks.firstIndex(where: { $0.id == network.id }) {
			guard networks[index] != network else { return Changes() }
			networks[index] = network
			return Changes(changed: [network])
		}

		guard networks.count < BouncerNetworkAttributes.maximumNetworks else { return Changes() }
		networks.append(network)
		return Changes(added: [network])
	}

	private mutating func applyUpdate(_ identifier: String, _ attributes: [String: String]) -> Changes {
		var network = network(withIdentifier: identifier) ?? BouncerNetwork(id: identifier)
		network.apply(attributes)
		return applyUpsert(network)
	}

	private mutating func applyRemoval(_ identifier: String) -> Changes {
		guard let index = networks.firstIndex(where: { $0.id == identifier }) else { return Changes() }
		networks.remove(at: index)
		return Changes(removed: [identifier])
	}
}
