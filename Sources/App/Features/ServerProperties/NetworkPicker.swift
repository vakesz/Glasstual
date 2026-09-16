/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import Foundation
import Observation

/// What the network list can have selected: one of the bundled networks, keyed
/// by its own name, or the custom server the last row offers.
enum NetworkPickerSelection: Hashable {
	case network(String)
	case customServer
}

struct NetworkPickerOption: Identifiable {
	let network: Network?

	var id: NetworkPickerSelection {
		network.map { .network($0.networkName.lowercased()) } ?? .customServer
	}

	var title: String {
		network?.networkName ?? String(localized: .Onboarding.customServer)
	}

	var subtitle: String {
		network?.networkDescription ?? String(localized: .Onboarding.connectToAnyIrcServer)
	}

	var isSecure: Bool {
		network?.prefersSecuredConnection ?? false
	}
}

/** The connection details the network step is filling in.

 Choosing a network replaces the whole draft rather than assigning field by
 field, so there is one description of what a selection means and no order in
 which a half-applied selection can be observed. */
struct NetworkPickerDraft: Equatable {
	var serverAddress = ""
	var serverPort = ConnectionDefaults.serverPortSecure
	var prefersSecuredConnection = true
	var accountName = ""
	var accountPassword = ""
	var usesSASL = true

	init() {}

	init(network: Network?, accountName: String) {
		if let network {
			serverAddress = network.serverAddress
			serverPort = network.serverPort
			prefersSecuredConnection = network.prefersSecuredConnection
			usesSASL = network.saslSupported
		}
		self.accountName = accountName
	}
}

@Observable
final class NetworkPickerModel {
	let networkList: NetworkList
	var query = ""
	var draft = NetworkPickerDraft()
	var selectedChannels: Set<String> = []

	var selection: NetworkPickerSelection? {
		didSet {
			if selection != oldValue {
				applySelection()
			}
		}
	}

	private var defaultNickname = ""
	private var accountNameEdited = false

	init(networkList: NetworkList = NetworkList()) {
		self.networkList = networkList
	}

	var selectedNetwork: Network? {
		guard case let .network(name) = selection else { return nil }
		return networkList.network(named: name)
	}

	var hasSelection: Bool {
		selection == .customServer || selectedNetwork != nil
	}

	var popularOptions: [NetworkPickerOption] {
		guard normalizedQuery.isEmpty else { return [] }
		return networkList.popularNetworks.map { NetworkPickerOption(network: $0) }
	}

	var remainingOptions: [NetworkPickerOption] {
		let candidates = normalizedQuery.isEmpty
			? networkList.networksBelowThePopularOnes
			: networkList.listOfNetworks.filter(matchesQuery)
		return candidates.map { NetworkPickerOption(network: $0) }
	}

	var customOption: NetworkPickerOption {
		NetworkPickerOption(network: nil)
	}

	/// The custom server row always matches, so an empty result is only ever a
	/// search that found no network.
	var hasNoSearchResults: Bool {
		normalizedQuery.isEmpty == false && remainingOptions.isEmpty
	}

	var selectedTitle: String {
		selectedNetwork?.networkName ?? String(localized: .Onboarding.customServer)
	}

	var selectedNetworkRequiresRegistration: Bool {
		selectedNetwork?.registration == .required
	}

	var accountFieldsApply: Bool {
		selectedNetwork?.accountFieldsApply ?? (selection == .customServer)
	}

	var saslIsSupported: Bool {
		selectedNetwork?.saslSupported ?? (selection == .customServer)
	}

	var registrationNote: String? {
		selectedNetwork?.registrationNote
	}

	var websiteURL: URL? {
		guard let website = selectedNetwork?.website else { return nil }
		return URL(string: website)
	}

	var suggestedChannels: [String] {
		selectedNetwork?.suggestedChannels ?? []
	}

	func updateDefaultNickname(_ nickname: String) {
		defaultNickname = nickname
		if accountNameEdited == false {
			draft.accountName = nickname
		}
	}

	func setAccountName(_ name: String) {
		accountNameEdited = true
		draft.accountName = name
	}

	// MARK: - Validation

	var serverAddressProblem: String? {
		guard hasSelection else { return nil }
		let address = draft.serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
		return (address as NSString).isValidInternetAddress
			? nil
			: CommonValidationStrings.invalidServerAddress
	}

	var serverPortProblem: String? {
		guard hasSelection else { return nil }
		return draft.serverPort > 0 ? nil : String(localized: .Onboarding.enterAPortBetween1)
	}

	var accountProblem: String? {
		guard hasSelection, draft.accountPassword.isEmpty == false else { return nil }
		let account = draft.accountName.trimmingCharacters(in: .whitespacesAndNewlines)
		guard account.isEmpty || (account as NSString).isHostmaskUsername else {
			return String(localized: .Onboarding.invalidAccount)
		}
		return draft.accountPassword.rangeOfCharacter(from: .controlCharacters) == nil
			? nil
			: String(localized: .Onboarding.invalidAccount)
	}

	/// Leaving the network step without a selection is a supported choice, so
	/// only a half-filled selection blocks Continue.
	var isValid: Bool {
		serverAddressProblem == nil && serverPortProblem == nil && accountProblem == nil
	}

	func clientConfig() -> ClientConfig? {
		guard hasSelection, isValid else { return nil }

		let normalizedAddress = draft.serverAddress
			.trimmingCharacters(in: .whitespacesAndNewlines)
			.lowercased()
		var config = ClientConfig()
		config.usesSASL = draft.usesSASL && saslIsSupported
		config.connectionName = selectedNetwork?.networkName ?? normalizedAddress
		config.serverList = [
			Server(
				serverAddress: normalizedAddress,
				serverPort: draft.serverPort,
				prefersSecuredConnection: draft.prefersSecuredConnection
			),
		]

		if draft.accountPassword.isEmpty == false {
			config.nicknamePassword = draft.accountPassword
			let name = draft.accountName.trimmingCharacters(in: .whitespacesAndNewlines)
			if name.isEmpty == false {
				config.username = name
			}
		}

		return config
	}

	private var normalizedQuery: String {
		query.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	private func matchesQuery(_ network: Network) -> Bool {
		let query = normalizedQuery
		return network.networkName.localizedCaseInsensitiveContains(query)
			|| network.serverAddress.localizedCaseInsensitiveContains(query)
			|| network.networkDescription.localizedCaseInsensitiveContains(query)
	}

	private func applySelection() {
		accountNameEdited = false
		draft = NetworkPickerDraft(network: selectedNetwork, accountName: defaultNickname)
		selectedChannels = Set(suggestedChannels)
	}
}

extension NetworkList {
	/// The catalog with the popular networks taken out, so a list that leads
	/// with them does not name any of them twice.
	var networksBelowThePopularOnes: [Network] {
		let popularNames = Set(popularNetworks.map { $0.networkName.lowercased() })

		return listOfNetworks.filter { popularNames.contains($0.networkName.lowercased()) == false }
	}
}
