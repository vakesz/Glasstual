// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import os

private let bouncerLogger = Logger(subsystem: LogSubsystem.current, category: "BouncerNetworks")

/** soju's `soju.im/bouncer-networks`.

 One bouncer account owns several upstream networks. The connection the user
 configured, the parent, asks for them and reports each to the chat session,
 which keeps a connection of its own for every one. Those connections send
 `BOUNCER BIND` before registration ends so the bouncer attaches them to their
 network instead of offering them the account's listing. */
@MainActor
extension ServerSession {
	// MARK: - State

	/// Whether this connection is bound to one network of a bouncer account.
	var isBouncerNetwork: Bool {
		config.bouncerNetwork != nil
	}

	/// Whether this connection may list and manage the account's networks: it
	/// is not itself a network, and the user leaves discovery on.
	var bouncerDiscoveryIsEnabled: Bool {
		config.bouncerNetwork == nil && config.bouncerDiscoversNetworks
	}

	/// Whether the bouncer has accepted the capability and a command could be sent.
	var canManageBouncerNetworks: Bool {
		bouncerDiscoveryIsEnabled && isLoggedIn && isCapabilityEnabled(.bouncerNetworks)
	}

	// MARK: - Outbound

	/** Attaches a network connection to its network.

	 Called just before `CAP END`: the bouncer decides which network a
	 connection serves while it is registering, so a bind sent afterwards would
	 come too late. */
	func sendBouncerBindIfNeeded() {
		guard let binding = config.bouncerNetwork, binding.isRemoved == false else { return }
		send(.bouncer, arguments: ["BIND", binding.networkIdentifier])
	}

	func requestBouncerNetworks() {
		guard canManageBouncerNetworks else { return }
		send(.bouncer, arguments: ["LISTNETWORKS"])
	}

	func addBouncerNetwork(_ edit: BouncerNetworkEdit) {
		guard canManageBouncerNetworks else { return }
		bouncer.lastFailure = nil
		send(.bouncer, arguments: ["ADDNETWORK", edit.attributeText])
	}

	func changeBouncerNetwork(_ identifier: String, with edit: BouncerNetworkEdit) {
		guard canManageBouncerNetworks, BouncerNetworkAttributes.isValidNetworkIdentifier(identifier) else { return }
		bouncer.lastFailure = nil
		send(.bouncer, arguments: ["CHANGENETWORK", identifier, edit.attributeText])
	}

	func deleteBouncerNetwork(_ identifier: String) {
		guard canManageBouncerNetworks, BouncerNetworkAttributes.isValidNetworkIdentifier(identifier) else { return }
		bouncer.lastFailure = nil
		send(.bouncer, arguments: ["DELNETWORK", identifier])
	}

	// MARK: - Inbound

	/** A `BOUNCER` line outside a listing batch: a notification, or the
	 acknowledgement of a management command. */
	func receiveBouncer(_ message: Message) {
		guard bouncerDiscoveryIsEnabled, let subcommand = message.params.first?.uppercased() else { return }

		switch subcommand {
		case "NETWORK":
			guard isCapabilityEnabled(.bouncerNetworks), message.params.count >= 3 else { return }
			receiveBouncerNetworkLine(identifier: message.params[1], attributes: message.params[2])
		case "ADDNETWORK", "CHANGENETWORK", "DELNETWORK":
			/* Without notifications the account's listing has to be asked for
			 again to show what the command did. */
			if isCapabilityEnabled(.bouncerNetworksNotify) == false {
				requestBouncerNetworks()
			}
		default:
			break
		}
	}

	private func receiveBouncerNetworkLine(identifier: String, attributes: String) {
		guard BouncerNetworkAttributes.isValidNetworkIdentifier(identifier) else {
			bouncerLogger.error("Ignored a BOUNCER NETWORK line with an invalid identifier")
			return
		}

		if attributes == "*" {
			applyBouncerUpdate(.remove(identifier))
		} else if let changed = BouncerNetworkAttributes.parse(attributes) {
			applyBouncerUpdate(.update(identifier, changed))
		} else {
			bouncerLogger.error("Ignored a BOUNCER NETWORK line with invalid attributes")
		}
	}

	/// The answer to `LISTNETWORKS`: every network in the batch, as the whole listing.
	func receiveBouncerNetworkBatch(_ batch: MessageBatch) {
		guard bouncerDiscoveryIsEnabled, isCapabilityEnabled(.bouncerNetworks) else { return }

		var listing: [BouncerNetwork] = []
		for message in batch.queuedMessages where message.remoteCommand == .bouncer {
			guard message.params.count >= 3, message.params[0].uppercased() == "NETWORK",
			      message.params[2] != "*",
			      let network = BouncerNetwork(id: message.params[1], attributeText: message.params[2])
			else { continue }
			listing.append(network)
		}
		applyBouncerUpdate(.snapshot(listing))
	}

	private func applyBouncerUpdate(_ update: BouncerNetworkSet.Update) {
		let changes = bouncer.networks.apply(update)
		guard changes.isEmpty == false || changes.completeListing != nil else { return }

		chatSession?.applyBouncerChanges(changes, from: self)
		ServerSessionBouncerNetworksDidChange(subject: self).post()
	}

	/// Remembers a failed management command so the pane that sent it can say so.
	func receiveBouncerFailure(_ message: Message) {
		guard message.params.count >= 3 else { return }
		bouncer.lastFailure = BouncerFailure(code: message.params[1], description: message.params.last ?? "")
		ServerSessionBouncerNetworksDidChange(subject: self).post()
	}
}
