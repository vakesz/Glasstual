// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Observation
import SwiftUI

/** The connection details the network step is filling in.

 Choosing a network replaces the whole draft rather than assigning field by
 field, so there is one description of what a selection means and no order in
 which a half-applied selection can be observed. */
struct OnboardingNetworkDraft: Equatable {
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

/** The first connection onboarding offers to make.

 The shared list says which network is chosen; this is everything the step adds
 to that answer -- the address and port to connect to, the account to log in as,
 and which of the network's suggested channels to open. */
@Observable
final class OnboardingNetworkPickerModel {
	/// Which of the bundled networks is chosen, as the shared list keeps it.
	let networks: NetworkPickerListModel

	var draft = OnboardingNetworkDraft()
	var selectedChannels: Set<String> = []

	private var defaultNickname = ""
	private var accountNameEdited = false

	init(networkList: NetworkList = NetworkList()) {
		networks = NetworkPickerListModel(networkList: networkList)
		networks.selectionDidChange = { [weak self] in
			self?.applySelection()
		}
	}

	var selectedNetwork: Network? {
		networks.selectedNetwork
	}

	var hasSelection: Bool {
		networks.hasSelection
	}

	var selectedNetworkRequiresRegistration: Bool {
		selectedNetwork?.registration == .required
	}

	/// Whether the chosen row logs in with an account at all. A custom server
	/// might; a network that runs no services does not.
	var accountFieldsApply: Bool {
		selectedNetwork?.accountFieldsApply ?? (networks.selection == .customServer)
	}

	var saslIsSupported: Bool {
		selectedNetwork?.saslSupported ?? (networks.selection == .customServer)
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

	/// The suggested channels the person left ticked, in the network's order.
	var channelsToJoin: [String] {
		suggestedChannels.filter { selectedChannels.contains($0) }
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
		return address.isValidInternetAddress
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
		guard account.isEmpty || account.isHostmaskUsername else {
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

	/// The connection the step describes, or `nil` when it describes none.
	func serverConfig() -> ServerConfig? {
		guard hasSelection, isValid else { return nil }

		let normalizedAddress = draft.serverAddress
			.trimmingCharacters(in: .whitespacesAndNewlines)
			.lowercased()
		var config = ServerConfig()
		config.usesSASL = draft.usesSASL && saslIsSupported
		config.connectionName = selectedNetwork?.networkName ?? normalizedAddress
		config.serverList = [
			ServerEndpoint(
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

	private func applySelection() {
		accountNameEdited = false
		draft = OnboardingNetworkDraft(network: selectedNetwork, accountName: defaultNickname)
		selectedChannels = Set(suggestedChannels)
	}
}

/// The network step: the shared list of networks, the details of the chosen one,
/// and what to do with the connection once onboarding closes.
struct OnboardingNetworkView: View {
	@Bindable var settings: OnboardingSettings
	@Bindable var picker: OnboardingNetworkPickerModel
	let confirm: () -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			HStack(spacing: 0) {
				NetworkPickerListView(model: picker.networks, confirm: confirm)
					.frame(width: 250)

				Divider()

				ScrollView {
					if picker.hasSelection {
						OnboardingNetworkDetailView(picker: picker)
							.padding(.horizontal, 14)
					} else {
						ContentUnavailableView(
							String(localized: .Onboarding.chooseANetworkOrEnter),
							systemImage: "network"
						)
						.frame(maxWidth: .infinity, minHeight: 260)
					}
				}
				.frame(maxWidth: .infinity)
			}
			.frame(minHeight: 300)

			VStack(alignment: .leading, spacing: 6) {
				Text(.Onboarding.suggestedChannels)
				if picker.suggestedChannels.isEmpty {
					Text(.Onboarding.chooseANetworkToSeeSuggested)
						.font(.callout)
						.foregroundStyle(.secondary)
				} else {
					ForEach(picker.suggestedChannels, id: \.self) { channel in
						Toggle(channel, isOn: $picker.selectedChannels.containing(channel))
					}
				}
			}

			Toggle(.Onboarding.connectWhenFinished, isOn: $settings.network.connectWhenFinished)
		}
		.padding(.bottom, 10)
	}
}

/// The chosen network's details, and the account to log in to it with.
private struct OnboardingNetworkDetailView: View {
	@Bindable var picker: OnboardingNetworkPickerModel

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			header
			if let network = picker.selectedNetwork {
				Text(verbatim: network.networkDescription)
					.font(.callout)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}

			Form {
				ValidatedFormRow(
					label: String(localized: .Onboarding.serverAddress),
					problem: picker.serverAddressProblem
				) {
					TextField(.Onboarding.ircExampleOrg, text: $picker.draft.serverAddress)
						.accessibilityIdentifier("network-address")
				}

				ValidatedFormRow(
					label: String(localized: .Onboarding.networkPickerPort),
					problem: picker.serverPortProblem
				) {
					TextField(
						.Onboarding.networkPickerPort,
						value: $picker.draft.serverPort,
						format: .number.grouping(.never)
					)
					.labelsHidden()
					.frame(width: 70)
					.monospacedDigit()
					.accessibilityIdentifier("network-port")
				}

				Toggle(.Onboarding.useSslTls, isOn: $picker.draft.prefersSecuredConnection)
			}
			.formStyle(.columns)

			if picker.accountFieldsApply {
				accountFields
			}
		}
		.padding(.vertical, UISpacing.regular)
	}

	private var header: some View {
		HStack {
			Text(verbatim: picker.networks.selectedTitle).font(.headline)
			if picker.selectedNetworkRequiresRegistration {
				Text(.Onboarding.registrationRequired)
					.font(.caption.weight(.medium))
					.padding(.horizontal, 6)
					.padding(.vertical, 2)
					.background(.quaternary, in: Capsule())
			}
			Spacer()
			if let websiteURL = picker.websiteURL {
				Link(websiteURL.host() ?? websiteURL.absoluteString, destination: websiteURL)
					.font(.callout)
			}
		}
	}

	private var accountFields: some View {
		GroupBox(.Onboarding.networkPickerAccount) {
			VStack(alignment: .leading, spacing: UISpacing.regular) {
				Form {
					LabeledContent(.Onboarding.accountName) {
						TextField(
							.Onboarding.accountName,
							text: Binding(get: { picker.draft.accountName }, set: picker.setAccountName)
						)
						.labelsHidden()
					}
					ValidatedFormRow(
						label: String(localized: .Onboarding.networkPickerPassword),
						problem: picker.accountProblem
					) {
						SecureField(.Onboarding.networkPickerPassword, text: $picker.draft.accountPassword)
							.labelsHidden()
					}
				}
				.formStyle(.columns)

				Toggle(.Onboarding.signInWithSasl, isOn: $picker.draft.usesSASL)
					.disabled(picker.saslIsSupported == false)
				Text(.Onboarding.accountIdentityHelp)
					.font(.caption)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)

				if let registrationNote = picker.registrationNote {
					Text(verbatim: registrationNote)
						.font(.caption)
						.foregroundStyle(.secondary)
						.textSelection(.enabled)
				}
			}
			.padding(.vertical, UISpacing.tight)
		}
	}
}

private extension Binding where Value == Set<String> {
	/// Presents one member of the set as the `Bool` a `Toggle` binds to.
	func containing(_ member: String) -> Binding<Bool> {
		Binding<Bool>(
			get: { wrappedValue.contains(member) },
			set: { isSelected in
				if isSelected {
					wrappedValue.insert(member)
				} else {
					wrappedValue.remove(member)
				}
			}
		)
	}
}
