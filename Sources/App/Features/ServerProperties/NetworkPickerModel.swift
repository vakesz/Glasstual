/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
import Observation

struct NetworkPickerOption: Identifiable {
	let network: Network?
	let isCustom: Bool

	var id: String {
		if let network {
			return network.networkName.lowercased()
		}
		return "__custom_server__"
	}

	var title: String {
		network?.networkName ?? OnboardingStrings.NetworkPicker.customServerTitle
	}

	var subtitle: String {
		network?.networkDescription ?? OnboardingStrings.NetworkPicker.customServerDescription
	}

	var isSecure: Bool {
		network?.prefersSecuredConnection ?? false
	}
}

@Observable
final class NetworkPickerModel {
	let networkList: NetworkList
	var query = ""
	var selectionID: String? {
		didSet { applySelection() }
	}

	var serverAddress = ""
	var serverPort = "6697"
	var prefersSecuredConnection = true
	var accountName = ""
	var accountPassword = ""
	var usesSASL = true
	var selectedChannels: Set<String> = []

	private(set) var selectedNetwork: Network?
	private(set) var customServerSelected = false
	private var defaultNickname = ""
	private var accountNameEdited = false

	init(networkList: NetworkList = NetworkList()) {
		self.networkList = networkList
	}

	var hasSelection: Bool {
		selectedNetwork != nil || customServerSelected
	}

	var popularOptions: [NetworkPickerOption] {
		guard normalizedQuery.isEmpty else { return [] }
		return networkList.popularNetworks.map { NetworkPickerOption(network: $0, isCustom: false) }
	}

	var remainingOptions: [NetworkPickerOption] {
		let popularNames = Set(networkList.popularNetworks.map { $0.networkName.lowercased() })
		let candidates = normalizedQuery.isEmpty
			? networkList.listOfNetworks.filter { popularNames.contains($0.networkName.lowercased()) == false }
			: networkList.listOfNetworks.filter(matchesQuery)
		return candidates.map { NetworkPickerOption(network: $0, isCustom: false) }
	}

	var customOption: NetworkPickerOption {
		NetworkPickerOption(network: nil, isCustom: true)
	}

	var selectedTitle: String {
		selectedNetwork?.networkName ?? OnboardingStrings.NetworkPicker.customServerTitle
	}

	var selectedNetworkRequiresRegistration: Bool {
		selectedNetwork?.registration == .required
	}

	var accountFieldsApply: Bool {
		selectedNetwork?.accountFieldsApply ?? customServerSelected
	}

	var saslIsSupported: Bool {
		selectedNetwork?.saslSupported ?? customServerSelected
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
			accountName = nickname
		}
	}

	func setAccountName(_ name: String) {
		accountNameEdited = true
		accountName = name
	}

	func validate() throws {
		guard hasSelection else {
			throw OnboardingStepError(OnboardingStrings.NetworkPicker.missingServer)
		}
		guard ServerPropertiesValidation
			.isInternetAddress(serverAddress.trimmingCharacters(in: .whitespacesAndNewlines))
		else {
			throw OnboardingStepError(CommonValidationStrings.invalidServerAddress)
		}
		guard ServerPropertiesValidation.isInternetPort(serverPort) else {
			throw OnboardingStepError(OnboardingStrings.NetworkPicker.invalidPort)
		}
	}

	func clientConfig() -> ClientConfig? {
		guard (try? validate()) != nil, let port = UInt16(serverPort) else { return nil }

		let normalizedAddress = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
		var config = ClientConfig()
		config.connectionName = selectedNetwork?.networkName ?? normalizedAddress
		config.serverList = [
			Server(
				serverAddress: normalizedAddress,
				serverPort: port,
				prefersSecuredConnection: prefersSecuredConnection
			),
		]

		if accountPassword.isEmpty == false {
			config.nicknamePassword = accountPassword
			let name = accountName.trimmingCharacters(in: .whitespacesAndNewlines)
			if usesSASL, name.isEmpty == false {
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
		guard let selectionID else {
			selectedNetwork = nil
			customServerSelected = false
			selectedChannels = []
			return
		}

		accountNameEdited = false
		accountName = defaultNickname
		accountPassword = ""

		if selectionID == customOption.id {
			selectedNetwork = nil
			customServerSelected = true
			serverAddress = ""
			serverPort = "6697"
			prefersSecuredConnection = true
			usesSASL = true
			selectedChannels = []
			return
		}

		guard let network = networkList.network(named: selectionID) else {
			self.selectionID = nil
			return
		}

		selectedNetwork = network
		customServerSelected = false
		serverAddress = network.serverAddress
		serverPort = String(network.serverPort)
		prefersSecuredConnection = network.prefersSecuredConnection
		usesSASL = network.saslSupported
		selectedChannels = Set(network.suggestedChannels)
	}
}
