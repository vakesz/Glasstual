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

	private var automaticCapabilities: String {
		CapabilityRegistry.defaultRegistry.capabilities
			.filter { $0.preference == .always }
			.map(\.name)
			.sorted()
			.joined(separator: ", ")
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

			Section(PreferencesIRCv3Strings.automaticFeatures) {
				Text(verbatim: automaticCapabilities)
					.textSelection(.enabled)
				PreferencesNote(PreferencesIRCv3Strings.automaticFeaturesNote)
			}
		}
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
