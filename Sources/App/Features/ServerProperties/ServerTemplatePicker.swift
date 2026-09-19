// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

/** The first screen of the sheet for a new connection: the bundled networks
 to start from, with the custom server row for a host the catalog does not
 list.

 The list is the shared one onboarding also shows. What sits beside it is a
 preview of what Continue fills the form in with, rather than the account fields
 the onboarding step asks for: the form has those, and every other field, on the
 next screen. */
struct ServerTemplatePickerView: View {
	let model: ServerPropertiesModel
	@Bindable var picker: NetworkPickerListModel
	/// Weak for the same reason `ServerPropertiesView`'s is: the sheet holds
	/// this view.
	weak var commands: (any ServerPropertiesCommands)?

	var body: some View {
		VStack(spacing: 0) {
			HStack(spacing: 0) {
				NetworkPickerListView(model: picker) { commands?.applyTemplate() }
					.frame(width: 280)

				Divider()

				detail
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			}

			SheetActions(
				confirmTitle: Text(PromptStrings.Action.continueAction),
				confirmIsDisabled: model.canApplyTemplate == false,
				confirm: { commands?.applyTemplate() },
				cancel: { commands?.cancel() }
			)
		}
	}

	@ViewBuilder
	private var detail: some View {
		if let network = picker.selectedNetwork {
			ServerTemplateDetailView(network: network)
		} else if picker.selection == .customServer {
			ContentUnavailableView(
				String(localized: .NetworkPicker.customServer),
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
		VStack(alignment: .leading, spacing: UISpacing.tight) {
			HStack(spacing: UISpacing.regular) {
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
