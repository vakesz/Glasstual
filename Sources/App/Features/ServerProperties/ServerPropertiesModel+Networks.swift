// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

extension ServerPropertiesModel {
	// MARK: - Templates

	var isChoosingTemplate: Bool {
		templatePicker != nil
	}

	/// Continue is offered once a row is chosen; the custom server row counts.
	var canApplyTemplate: Bool {
		templatePicker?.hasSelection ?? false
	}

	/** Fills the connection in from the chosen row and moves on to the form.

	 The custom server row moves on with the fields as they are. A network sets
	 the connection's name and primary endpoint, turns SASL on where the network
	 offers it, and puts its suggested channels on the channel list, where the
	 Conversation List pane can take any of them off again. */
	func applySelectedTemplate() {
		guard let picker = templatePicker, picker.hasSelection else { return }

		if let network = picker.selectedNetwork {
			var config = config
			config.connectionName = network.networkName
			config.serverList = [
				ServerEndpoint(
					serverAddress: network.serverAddress,
					serverPort: network.serverPort,
					prefersSecuredConnection: network.prefersSecuredConnection
				),
			]
			config.usesSASL = network.saslSupported
			config.conversationList = network.suggestedChannels.map { ConversationConfig.seed(withName: $0) }
			replace(with: config)
		}

		templatePicker = nil
		selection = .general
	}

	// MARK: - Bundled networks

	/** What the Server Address field offers to complete to.

	 An empty field leads with the popular networks and then lists the rest, the
	 way the onboarding picker does; typing narrows the whole catalog by name and
	 by address. The onboarding picker's matcher also reads the network's blurb,
	 which belongs to a browsing list rather than to an address field, so this
	 keeps its own. */
	var serverAddressSuggestions: [Network] {
		let query = serverAddress.trimmed

		guard query.isEmpty == false else {
			return networkList.popularNetworks + networkList.networksBelowThePopularOnes
		}

		return networkList.listOfNetworks.filter {
			$0.networkName.localizedCaseInsensitiveContains(query)
				|| $0.serverAddress.localizedCaseInsensitiveContains(query)
		}
	}

	/** The address to connect to, which is not always the address on screen.

	 The field shows a network by name — "Libera.Chat" rather than
	 `irc.libera.chat` — so what is stored is the catalog's address for the
	 network the text names, and otherwise the host as typed. Three network names
	 hold a space, which is also why the name is resolved before the text is cut
	 down to its first token. */
	var resolvedPrimaryServerAddress: String {
		if let network = networkList.network(named: serverAddress.trimmed) {
			return network.serverAddress
		}

		return serverAddress.firstToken.lowercased()
	}

	/** Fills the port and TLS fields in from the network the address now names.

	 Called for each edit of the field. A value that names a network — by its
	 name or by its address — is replaced with the network's name and brings the
	 network's port and TLS state with it; a value that names none puts back
	 whatever the last network overwrote, once. */
	func serverAddressTextDidChange() {
		guard isApplyingNetwork == false else { return }

		let text = serverAddress.trimmed

		guard text != lastResolvedAddressText else { return }

		lastResolvedAddressText = text

		guard let network = networkList.network(named: text) ?? networkList.network(withServerAddress: text)
		else {
			restorePreviousValuesForPrimaryServer()
			return
		}

		isApplyingNetwork = true
		defer { isApplyingNetwork = false }

		if valuesReplacedByNetwork == nil {
			valuesReplacedByNetwork = PrimaryServerValues(port: serverPort, secured: primaryServerIsSecured)
		}

		serverAddress = network.networkName
		lastResolvedAddressText = network.networkName
		applyPrimaryServerValues(
			PrimaryServerValues(port: String(network.serverPort), secured: network.prefersSecuredConnection)
		)
	}

	/// The network name a stored address is listed under, or the address itself
	/// when the catalog does not list it.
	static func displayedServerAddress(_ serverAddress: String, in networkList: NetworkList) -> String {
		networkList.network(withServerAddress: serverAddress)?.networkName ?? serverAddress
	}

	func restorePreviousValuesForPrimaryServer() {
		guard let previous = valuesReplacedByNetwork else { return }

		valuesReplacedByNetwork = nil
		applyPrimaryServerValues(previous)
	}

	/** Writes a port and a TLS state together.

	 `setPrimaryServerSecured(_:)` moves the port between 6667 and 6697 as the
	 endpoint sheet does, which is right for a toggle the person flipped and
	 wrong here: both values are being replaced at once, so neither may nudge
	 the other. */
	func applyPrimaryServerValues(_ values: PrimaryServerValues) {
		var server = primaryServer ?? ServerEndpoint()
		server.serverPort = UInt16(values.port) ?? server.serverPort
		server.prefersSecuredConnection = values.secured
		storePrimaryServer(server)
		serverPort = values.port
	}

	/// Forgets what the field last resolved, for a sheet whose fields have just
	/// been replaced wholesale: nothing a network overwrote is still on screen.
	func forgetNetworkResolution() {
		valuesReplacedByNetwork = nil
		lastResolvedAddressText = serverAddress.trimmed
	}
}
