// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

/** The Bouncer Networks pane.

 For an account connection it holds the two switches that belong to the saved
 configuration and, below them, the live list of the bouncer's networks. For a
 network connection it only says where the connection comes from. */
struct ServerPropertiesBouncerPane: View {
	@Bindable var model: ServerPropertiesModel

	var body: some View {
		if let networks = model.bouncerNetworks {
			if model.isBouncerNetwork {
				BouncerNetworkConnectionNote(networks: networks)
			} else {
				BouncerAccountForm(model: model, networks: networks)
			}
		}
	}
}

private struct BouncerNetworkConnectionNote: View {
	let networks: BouncerNetworksModel

	var body: some View {
		Form {
			Section {
				Text(.ServerProperties.bouncerNetworkManagedBy(networks.parentName ?? ""))
				if networks.parentIsHidden {
					Button(.ServerProperties.bouncerShowConnection) {
						networks.showParentConnection()
					}
				}
			}
		}
		.formStyle(.grouped)
	}
}

private struct BouncerAccountForm: View {
	@Bindable var model: ServerPropertiesModel
	let networks: BouncerNetworksModel
	@State private var selection: String?
	@State private var draft: BouncerNetworkDraft?
	@State private var pendingDeletion: BouncerNetwork?

	private var selectedNetwork: BouncerNetwork? {
		networks.networks.first { $0.id == selection }
	}

	var body: some View {
		Form {
			Section {
				Toggle(.ServerProperties.bouncerDiscoverNetworks, isOn: $model.config.bouncerDiscoversNetworks)
				Toggle(.ServerProperties.bouncerHideConnection, isOn: $model.config.bouncerHidesParent)
					.disabled(model.config.bouncerDiscoversNetworks == false)
			} footer: {
				Text(.ServerProperties.bouncerNetworksFooter)
			}

			Section(.ServerProperties.bouncerNetworksSection) {
				if networks.canManage {
					list
					buttons
				} else {
					Text(.ServerProperties.bouncerNetworksUnavailable)
						.foregroundStyle(.secondary)
				}
				if let failure = networks.failure {
					ValidationMessageLabel(
						String(localized: .ServerProperties.bouncerNetworkFailure(failure.description, failure.code))
					)
				}
			}
		}
		.formStyle(.grouped)
		.sheet(item: $draft) { current in
			BouncerNetworkEditorView(draft: current) { finished in
				if let original = finished.original {
					networks.change(original, with: finished.edit)
				} else {
					networks.add(finished.edit)
				}
				draft = nil
			} cancel: {
				draft = nil
			}
		}
		.confirmationDialog(
			.ServerProperties.bouncerNetworkDeleteTitle(pendingDeletion?.displayName ?? ""),
			isPresented: Binding(get: { pendingDeletion != nil }, set: {
				if !$0 {
					pendingDeletion = nil
				}
			}),
			titleVisibility: .visible
		) {
			Button(.ServerProperties.bouncerNetworkDelete, role: .destructive) {
				if let pendingDeletion {
					networks.remove(pendingDeletion)
				}
				pendingDeletion = nil
			}
		} message: {
			Text(.ServerProperties.bouncerNetworkDeleteMessage)
		}
	}

	private var list: some View {
		List(selection: $selection) {
			ForEach(networks.networks) { network in
				VStack(alignment: .leading) {
					Text(verbatim: network.displayName)
					Text(BouncerNetworkRowDetail(network: network).text)
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				.tag(network.id)
			}
		}
		.frame(minHeight: 120)
		.overlay {
			if networks.networks.isEmpty {
				Text(.ServerProperties.bouncerNetworksEmpty).foregroundStyle(.secondary)
			}
		}
	}

	private var buttons: some View {
		HStack {
			Button(.ServerProperties.bouncerNetworkAdd) { draft = BouncerNetworkDraft() }
			Button(.ServerProperties.bouncerNetworkEdit) { draft = BouncerNetworkDraft(editing: selectedNetwork) }
				.disabled(selectedNetwork == nil)
			Button(.ServerProperties.bouncerNetworkDelete) { pendingDeletion = selectedNetwork }
				.disabled(selectedNetwork == nil)
			Spacer()
			Button(.ServerProperties.bouncerNetworksRefresh) { networks.reload() }
		}
	}
}

/// The second line of a network's row: where it connects and how it is doing.
private struct BouncerNetworkRowDetail {
	let network: BouncerNetwork

	var text: String {
		var parts: [String] = []
		if let host = network.host {
			parts.append(network.port.map { "\(host):\($0)" } ?? host)
		}
		switch network.state {
		case .connected: parts.append(String(localized: .ServerProperties.bouncerNetworkStateConnected))
		case .connecting: parts.append(String(localized: .ServerProperties.bouncerNetworkStateConnecting))
		case .disconnected: parts.append(String(localized: .ServerProperties.bouncerNetworkStateDisconnected))
		case nil: break
		}
		if let error = network.error {
			parts.append(error)
		}
		return parts.formatted(.list(type: .and, width: .narrow))
	}
}
