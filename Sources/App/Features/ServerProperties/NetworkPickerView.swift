/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import SwiftUI

struct NetworkPickerView: View {
	@Bindable var model: NetworkPickerModel
	let confirm: () -> Void

	var body: some View {
		HStack(spacing: 0) {
			NetworkPickerListView(model: model, confirm: confirm)
				.frame(width: 250)

			Divider()

			ScrollView {
				if model.hasSelection {
					NetworkPickerDetailView(model: model)
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
	}
}

/** The searchable list of bundled networks, with the custom server row last.

 The onboarding step and the connection sheet's template step both show it:
 one goes on to ask for an account, the other opens the full connection form.
 Double-clicking a row selects it and confirms in one go. */
struct NetworkPickerListView: View {
	@Bindable var model: NetworkPickerModel
	let confirm: () -> Void

	/// `searchable` needs a navigation container to place its field in, and the
	/// list is the only part of the step that is searched.
	var body: some View {
		NavigationStack {
			List(selection: $model.selection) {
				if model.popularOptions.isEmpty == false {
					Section(.Onboarding.networkPickerPopular) {
						ForEach(model.popularOptions) { option in
							networkRow(option).tag(option.id)
						}
					}
				}

				/* The unavailable view stands in for the networks the search did
				 not match, rather than overlaying the whole list: the custom
				 server is always an answer, and an overlay covered the row that
				 offers it. */
				if model.hasNoSearchResults {
					ContentUnavailableView.search(text: model.query)
						.listRowSeparator(.hidden)
						.selectionDisabled()
				} else {
					Section(.Onboarding.allNetworks) {
						ForEach(model.remainingOptions) { option in
							networkRow(option).tag(option.id)
						}
					}
				}

				Section {
					networkRow(model.customOption).tag(model.customOption.id)
				}
			}
			.listStyle(.inset)
			.accessibilityLabel(.Onboarding.networkPickerNetworks)
			.searchable(text: $model.query, prompt: Text(.Onboarding.searchNetworks))
		}
	}

	private func networkRow(_ option: NetworkPickerOption) -> some View {
		HStack(spacing: 8) {
			VStack(alignment: .leading, spacing: 1) {
				Text(verbatim: option.title).lineLimit(1)
				Text(verbatim: option.subtitle)
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(1)
			}
			Spacer(minLength: 0)
			if option.isSecure {
				Image(systemName: "lock.fill")
					.foregroundStyle(.secondary)
					.accessibilityLabel(.Onboarding.secureConnection)
			}
		}
		.contentShape(Rectangle())
		.onTapGesture(count: 2) {
			model.selection = option.id
			confirm()
		}
	}
}

private struct NetworkPickerDetailView: View {
	@Bindable var model: NetworkPickerModel

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			header
			if let network = model.selectedNetwork {
				Text(verbatim: network.networkDescription)
					.font(.callout)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}

			Form {
				OnboardingValidatedRow(
					label: String(localized: .Onboarding.serverAddress),
					problem: model.serverAddressProblem
				) {
					TextField(.Onboarding.ircExampleOrg, text: $model.draft.serverAddress)
						.accessibilityIdentifier("network-address")
				}

				OnboardingValidatedRow(
					label: String(localized: .Onboarding.networkPickerPort),
					problem: model.serverPortProblem
				) {
					TextField(
						.Onboarding.networkPickerPort,
						value: $model.draft.serverPort,
						format: .number.grouping(.never)
					)
					.labelsHidden()
					.frame(width: 70)
					.monospacedDigit()
					.accessibilityIdentifier("network-port")
				}

				Toggle(.Onboarding.useSslTls, isOn: $model.draft.prefersSecuredConnection)
			}
			.formStyle(.columns)

			if model.accountFieldsApply {
				accountFields
			}
		}
		.padding(.vertical, 8)
	}

	private var header: some View {
		HStack {
			Text(verbatim: model.selectedTitle).font(.headline)
			if model.selectedNetworkRequiresRegistration {
				Text(.Onboarding.registrationRequired)
					.font(.caption.weight(.medium))
					.padding(.horizontal, 6)
					.padding(.vertical, 2)
					.background(.quaternary, in: Capsule())
			}
			Spacer()
			if let websiteURL = model.websiteURL {
				Link(websiteURL.host() ?? websiteURL.absoluteString, destination: websiteURL)
					.font(.callout)
			}
		}
	}

	private var accountFields: some View {
		GroupBox(.Onboarding.networkPickerAccount) {
			VStack(alignment: .leading, spacing: 8) {
				Form {
					LabeledContent(.Onboarding.accountName) {
						TextField(
							.Onboarding.accountName,
							text: Binding(get: { model.draft.accountName }, set: model.setAccountName)
						)
						.labelsHidden()
					}
					OnboardingValidatedRow(
						label: String(localized: .Onboarding.networkPickerPassword),
						problem: model.accountProblem
					) {
						SecureField(.Onboarding.networkPickerPassword, text: $model.draft.accountPassword)
							.labelsHidden()
					}
				}
				.formStyle(.columns)

				Toggle(.Onboarding.signInWithSasl, isOn: $model.draft.usesSASL)
					.disabled(model.saslIsSupported == false)
				Text(.Onboarding.accountIdentityHelp)
					.font(.caption)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)

				if let registrationNote = model.registrationNote {
					Text(verbatim: registrationNote)
						.font(.caption)
						.foregroundStyle(.secondary)
						.textSelection(.enabled)
				}
			}
			.padding(.vertical, 4)
		}
	}
}

/** The first screen of the sheet for a new connection: the bundled networks
 to start from, with the custom server row for a host the catalog does not
 list.

 The list is the onboarding picker's. What sits beside it is a preview of
 what Continue fills the form in with, rather than the account fields the
 onboarding step asks for: the form has those, and every other field, on the
 next screen. */
struct ServerTemplatePickerView: View {
	let model: ServerPropertiesModel
	@Bindable var picker: NetworkPickerModel
	let actions: ServerPropertiesActions

	var body: some View {
		VStack(spacing: 0) {
			HStack(spacing: 0) {
				NetworkPickerListView(model: picker, confirm: actions.applyTemplate)
					.frame(width: 280)

				Divider()

				detail
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			}

			Divider()
			HStack {
				Spacer()
				Button(PromptStrings.Action.cancel, action: actions.cancel)
					.keyboardShortcut(.cancelAction)
				Button(PromptStrings.Action.continueAction, action: actions.applyTemplate)
					.keyboardShortcut(.defaultAction)
					.disabled(model.canApplyTemplate == false)
			}
			.padding(12)
		}
	}

	@ViewBuilder
	private var detail: some View {
		if let network = picker.selectedNetwork {
			ServerTemplateDetailView(network: network)
		} else if picker.selection == .customServer {
			ContentUnavailableView(
				String(localized: .Onboarding.customServer),
				systemImage: "server.rack",
				description: Text(.ServerProperties.templateCustomServerHelp)
			)
		} else {
			ContentUnavailableView(
				String(localized: .ServerProperties.chooseNetworkTitle),
				systemImage: "network",
				description: Text(.ServerProperties.templatePickerHelp)
			)
		}
	}
}

/// What choosing a network puts into the form, shown before it is chosen.
private struct ServerTemplateDetailView: View {
	let network: Network

	var body: some View {
		Form {
			Section {
				LabeledContent(.ServerProperties.serverAddress, value: network.serverAddress)
				LabeledContent(.ServerProperties.serverPort, value: String(network.serverPort))
				LabeledContent(
					.ServerProperties.connectSecurely,
					value: network.prefersSecuredConnection ? PromptStrings.Action.yes : PromptStrings.Action.no
				)
				LabeledContent(
					.ServerProperties.signInWithSasl,
					value: network.saslSupported ? PromptStrings.Action.yes : PromptStrings.Action.no
				)
				if let websiteURL {
					LabeledContent(.ServerProperties.templateWebsite) {
						Link(websiteURL.host() ?? websiteURL.absoluteString, destination: websiteURL)
					}
				}
			} header: {
				header
			} footer: {
				if let registrationNote = network.registrationNote {
					Text(verbatim: registrationNote)
						.textSelection(.enabled)
				}
			}

			Section {
				if network.suggestedChannels.isEmpty {
					Text(.ServerProperties.templateNoSuggestedChannels)
						.foregroundStyle(.secondary)
				} else {
					ForEach(network.suggestedChannels, id: \.self) { channel in
						Label(channel, systemImage: "number")
					}
				}
			} header: {
				Text(.ServerProperties.templateSuggestedChannels)
			} footer: {
				if network.suggestedChannels.isEmpty == false {
					Text(.ServerProperties.templateSuggestedChannelsHelp)
				}
			}
		}
		.formStyle(.grouped)
	}

	private var header: some View {
		VStack(alignment: .leading, spacing: 4) {
			HStack(spacing: 8) {
				Text(verbatim: network.networkName)
					.font(.title2.weight(.semibold))
				if network.registration == .required {
					Text(.ServerProperties.templateRegistrationRequired)
						.font(.caption.weight(.medium))
						.padding(.horizontal, 6)
						.padding(.vertical, 2)
						.background(.quaternary, in: Capsule())
				}
			}
			if network.networkDescription.isEmpty == false {
				Text(verbatim: network.networkDescription)
					.font(.callout)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}
		}
		.textCase(nil)
		.padding(.bottom, 6)
	}

	private var websiteURL: URL? {
		network.website.flatMap { URL(string: $0) }
	}
}
