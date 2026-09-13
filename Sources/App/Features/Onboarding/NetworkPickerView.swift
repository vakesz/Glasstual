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
						OnboardingStrings.NetworkPicker.missingServer,
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
					Section(OnboardingStrings.NetworkPicker.popularGroup) {
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
					Section(OnboardingStrings.NetworkPicker.allNetworksGroup) {
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
			.accessibilityLabel(Text(verbatim: OnboardingStrings.NetworkPicker.accessibilityLabel))
			.searchable(
				text: $model.query,
				prompt: Text(verbatim: OnboardingStrings.NetworkPicker.searchPlaceholder)
			)
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
					.accessibilityLabel(
						Text(verbatim: OnboardingStrings.NetworkPicker.secureConnectionAccessibilityLabel)
					)
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

			Form {
				OnboardingValidatedRow(
					label: OnboardingStrings.NetworkPicker.serverAddressLabel,
					problem: model.serverAddressProblem
				) {
					TextField(
						OnboardingStrings.NetworkPicker.serverAddressPlaceholder,
						text: $model.draft.serverAddress
					)
					.accessibilityIdentifier("network-address")
				}

				OnboardingValidatedRow(
					label: OnboardingStrings.NetworkPicker.portLabel,
					problem: model.serverPortProblem
				) {
					TextField(
						OnboardingStrings.NetworkPicker.portLabel,
						value: $model.draft.serverPort,
						format: .number.grouping(.never)
					)
					.labelsHidden()
					.frame(width: 70)
					.monospacedDigit()
					.accessibilityIdentifier("network-port")
				}

				Toggle(
					OnboardingStrings.NetworkPicker.useTLSCheckbox,
					isOn: $model.draft.prefersSecuredConnection
				)
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
				Text(verbatim: OnboardingStrings.NetworkPicker.registrationRequired)
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
		GroupBox(OnboardingStrings.NetworkPicker.accountGroup) {
			VStack(alignment: .leading, spacing: 8) {
				Form {
					LabeledContent(OnboardingStrings.NetworkPicker.accountNameLabel) {
						TextField(
							OnboardingStrings.NetworkPicker.accountNameLabel,
							text: Binding(get: { model.draft.accountName }, set: model.setAccountName)
						)
						.labelsHidden()
					}
					OnboardingValidatedRow(
						label: OnboardingStrings.NetworkPicker.passwordLabel,
						problem: model.accountProblem
					) {
						SecureField(
							OnboardingStrings.NetworkPicker.passwordLabel,
							text: $model.draft.accountPassword
						)
						.labelsHidden()
					}
				}
				.formStyle(.columns)

				Toggle(OnboardingStrings.NetworkPicker.useSASLCheckbox, isOn: $model.draft.usesSASL)
					.disabled(model.saslIsSupported == false)
				Text(verbatim: OnboardingStrings.NetworkPicker.accountIdentityHelp)
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
