/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import SwiftUI

struct NetworkPickerView: View {
	@Bindable var model: NetworkPickerModel
	let confirm: () -> Void

	var body: some View {
		HSplitView {
			VStack(spacing: 8) {
				TextField(OnboardingStrings.NetworkPicker.searchPlaceholder, text: $model.query)
					.textFieldStyle(.roundedBorder)

				List(selection: $model.selectionID) {
					if model.popularOptions.isEmpty == false {
						Section(OnboardingStrings.NetworkPicker.popularGroup) {
							ForEach(model.popularOptions) { option in
								networkRow(option).tag(option.id)
							}
						}
					}

					Section(OnboardingStrings.NetworkPicker.allNetworksGroup) {
						ForEach(model.remainingOptions) { option in
							networkRow(option).tag(option.id)
						}
					}

					Section {
						networkRow(model.customOption).tag(model.customOption.id)
					}
				}
				.listStyle(.sidebar)
				.accessibilityLabel(Text(verbatim: OnboardingStrings.NetworkPicker.accessibilityLabel))
			}
			.frame(minWidth: 230, idealWidth: 250)
			.padding(.trailing, 8)

			ScrollView {
				if model.hasSelection {
					NetworkPickerDetailView(model: model)
						.padding(.horizontal, 14)
				} else {
					ContentUnavailableView(
						OnboardingStrings.NetworkPicker.missingServer,
						systemImage: "network"
					)
					.frame(maxWidth: .infinity, minHeight: 300)
				}
			}
			.frame(minWidth: 330, maxWidth: .infinity)
		}
		.frame(minHeight: 300)
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
					.accessibilityLabel(Text(verbatim: OnboardingStrings.NetworkPicker
							.secureConnectionAccessibilityLabel))
			}
		}
		.contentShape(Rectangle())
		.onTapGesture(count: 2) {
			model.selectionID = option.id
			confirm()
		}
	}
}

private struct NetworkPickerDetailView: View {
	@Bindable var model: NetworkPickerModel

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			HStack {
				Text(verbatim: model.selectedTitle).font(.headline)
				if model.selectedNetworkRequiresRegistration {
					Text(verbatim: OnboardingStrings.NetworkPicker.registrationRequired)
						.font(.caption.weight(.medium))
						.foregroundStyle(.orange)
						.padding(.horizontal, 6)
						.padding(.vertical, 2)
						.overlay(Capsule().stroke(.orange))
				}
				Spacer()
				if let websiteURL = model.websiteURL {
					Link(websiteURL.host() ?? websiteURL.absoluteString, destination: websiteURL)
						.font(.callout)
				}
			}

			Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
				GridRow {
					Text(verbatim: OnboardingStrings.NetworkPicker.serverAddressLabel)
						.gridColumnAlignment(.trailing)
					TextField(
						OnboardingStrings.NetworkPicker.serverAddressPlaceholder,
						text: $model.serverAddress
					)
					Text(verbatim: OnboardingStrings.NetworkPicker.portLabel)
					TextField(OnboardingStrings.NetworkPicker.portPlaceholder, text: $model.serverPort)
						.frame(width: 58)
						.monospacedDigit()
				}
			}

			Toggle(OnboardingStrings.NetworkPicker.useTLSCheckbox, isOn: $model.prefersSecuredConnection)

			if model.accountFieldsApply {
				GroupBox(OnboardingStrings.NetworkPicker.accountGroup) {
					VStack(alignment: .leading, spacing: 8) {
						LabeledContent(OnboardingStrings.NetworkPicker.accountNameLabel) {
							TextField(
								OnboardingStrings.NetworkPicker.accountNameLabel,
								text: Binding(
									get: { model.accountName },
									set: model.setAccountName
								)
							)
						}
						LabeledContent(OnboardingStrings.NetworkPicker.passwordLabel) {
							SecureField(
								OnboardingStrings.NetworkPicker.passwordLabel,
								text: $model.accountPassword
							)
						}
						Toggle(OnboardingStrings.NetworkPicker.useSASLCheckbox, isOn: $model.usesSASL)
							.disabled(model.saslIsSupported == false)

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
		.padding(.vertical, 8)
	}
}
