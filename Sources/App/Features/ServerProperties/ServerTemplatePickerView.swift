/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import SwiftUI

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
				OnboardingStrings.NetworkPicker.customServerTitle,
				systemImage: "server.rack",
				description: Text(verbatim: ServerPropertiesStrings.Template.customServerHelp)
			)
		} else {
			ContentUnavailableView(
				ServerPropertiesStrings.Template.title,
				systemImage: "network",
				description: Text(verbatim: ServerPropertiesStrings.Template.help)
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
				LabeledContent(ServerPropertiesStrings.General.serverAddress, value: network.serverAddress)
				LabeledContent(ServerPropertiesStrings.General.serverPort, value: String(network.serverPort))
				LabeledContent(
					ServerPropertiesStrings.General.connectSecurely,
					value: network.prefersSecuredConnection ? PromptStrings.Action.yes : PromptStrings.Action.no
				)
				LabeledContent(
					ServerPropertiesStrings.Identity.signInWithSASL,
					value: network.saslSupported ? PromptStrings.Action.yes : PromptStrings.Action.no
				)
				if let websiteURL {
					LabeledContent(ServerPropertiesStrings.Template.website) {
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
					Text(verbatim: ServerPropertiesStrings.Template.noSuggestedChannels)
						.foregroundStyle(.secondary)
				} else {
					ForEach(network.suggestedChannels, id: \.self) { channel in
						Label(channel, systemImage: "number")
					}
				}
			} header: {
				Text(verbatim: ServerPropertiesStrings.Template.suggestedChannels)
			} footer: {
				if network.suggestedChannels.isEmpty == false {
					Text(verbatim: ServerPropertiesStrings.Template.suggestedChannelsHelp)
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
					Text(verbatim: ServerPropertiesStrings.Template.registrationRequired)
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
