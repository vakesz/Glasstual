/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import SwiftUI

/// User-visible IRCv3 behavior and the capabilities negotiated by each live
/// connection. Protocol names stay verbatim because they are wire identifiers.
struct PreferencesIRCv3Pane: View {
	let model: PreferencesPaneModel

	/** The capabilities this pane switches individually.

	 A capability gated by a preference of its own — chat history, read
	 markers, echo-message — keeps that switch and stays out of this list, so
	 the draft and final spellings of one feature never appear as two
	 controls. */
	private var switchableCapabilities: [Capability] {
		CapabilityRegistry.defaultRegistry.capabilities
			.filter { $0.preference == .always }
			.sorted { $0.name < $1.name }
	}

	/** A capability's switch, read and written through the list of disabled
	 names: on means the name is absent. Absence as the enabled state is what
	 lets a capability added later start enabled. */
	private func capabilityBinding(for name: String) -> Binding<Bool> {
		let disabled = model.preferences.binding(for: Preferences.Connection.disabledCapabilities)

		return Binding(
			get: { disabled.wrappedValue.contains(name) == false },
			set: { isEnabled in
				var names = Set(disabled.wrappedValue)

				if isEnabled {
					names.remove(name)
				} else {
					names.insert(name)
				}

				disabled.wrappedValue = names.sorted()
			}
		)
	}

	var body: some View {
		PreferencesPaneLayout {
			Section(PreferencesIRCv3Strings.messages) {
				PreferencesToggle(
					title: PreferencesIRCv3Strings.displayTypingNotifications,
					isOn: model.preferences.binding(for: Preferences.Connection.displayTypingNotifications)
				)
				PreferencesToggle(
					title: PreferencesIRCv3Strings.sendTypingNotifications,
					isOn: model.preferences.binding(for: Preferences.Connection.sendTypingNotifications)
				)
				PreferencesToggle(
					title: PreferencesIRCv3Strings.echoMessage,
					isOn: model.preferences.binding(for: Preferences.Connection.echoMessageCapability)
				)
				PreferencesNote(PreferencesIRCv3Strings.reconnectNote)
			}

			Section(PreferencesIRCv3Strings.history) {
				PreferencesToggle(
					title: PreferencesIRCv3Strings.requestChatHistory,
					isOn: model.preferences.binding(for: Preferences.Connection.requestChatHistory)
				)
				PreferencesToggle(
					title: PreferencesIRCv3Strings.synchronizeReadMarkers,
					isOn: model.preferences.binding(for: Preferences.Connection.synchronizeReadMarkers)
				)
				PreferencesNote(PreferencesIRCv3Strings.historyNote)
			}

			Section(PreferencesIRCv3Strings.connectedServers) {
				if model.ircv3Connections.isEmpty {
					PreferencesNote(PreferencesIRCv3Strings.noConnections)
				} else {
					ForEach(model.ircv3Connections) { connection in
						connectionRow(connection)
					}
				}
			}

			Section(PreferencesIRCv3Strings.capabilities) {
				ForEach(switchableCapabilities, id: \.name) { capability in
					capabilityRow(capability)
				}
				PreferencesNote(PreferencesIRCv3Strings.reconnectNote)
			}
		}
	}

	private func capabilityRow(_ capability: Capability) -> some View {
		let summary = PreferencesIRCv3Strings.capabilitySummary(for: capability.name)

		return PreferencesCapabilityToggle(
			name: capability.name,
			summary: summary,
			accessibilityLabel: summary.map {
				PreferencesIRCv3Strings.capabilityAccessibilityLabel(name: capability.name, summary: $0)
			} ?? capability.name,
			specification: capability.specification,
			specificationTitle: PreferencesIRCv3Strings.capabilitySpecification,
			isOn: capabilityBinding(for: capability.name)
		)
	}

	private func connectionRow(_ connection: IRCv3ConnectionSummary) -> some View {
		VStack(alignment: .leading, spacing: 4) {
			HStack {
				Label(connection.name, systemImage: connection.isConnected ? "network" : "network.slash")
				Spacer()
				if connection.isConnected == false {
					Text(verbatim: PreferencesIRCv3Strings.disconnected)
						.foregroundStyle(.secondary)
				}
			}
			Text(verbatim: connection.capabilities.isEmpty
				? PreferencesIRCv3Strings.noCapabilities
				: connection.capabilities.joined(separator: ", "))
				.font(.caption)
				.foregroundStyle(.secondary)
				.textSelection(.enabled)
		}
		.padding(.vertical, 2)
	}
}
