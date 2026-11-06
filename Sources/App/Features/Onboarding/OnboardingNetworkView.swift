// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Observation
import SwiftUI

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
					TextField(.Onboarding.serverAddress, text: $picker.draft.serverAddress,
					          prompt: Text(.Onboarding.ircExampleOrg))
						.accessibilityIdentifier("network-address")
				}

				ValidatedFormRow(
					label: String(localized: .Onboarding.networkPickerPort),
					problem: picker.serverPortProblem
				) {
					TextField(
						.Onboarding.networkPickerPort,
						text: $picker.draft.serverPortText
					)
					.labelsHidden()
					.frame(width: 70)
					.monospacedDigit()
					.accessibilityIdentifier("network-port")
				}

				Toggle(.Onboarding.useSslTls, isOn: Binding(
					get: { picker.draft.prefersSecuredConnection },
					set: picker.setPrefersSecuredConnection
				))
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
					.accessibilityElement(children: .contain)
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
