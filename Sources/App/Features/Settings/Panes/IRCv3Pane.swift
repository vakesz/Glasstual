// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

/// The IRCv3 row: the protocol features the user chooses to use, and the
/// capabilities each live connection has negotiated. Protocol names stay
/// verbatim because they are wire identifiers.
struct IRCv3Pane: View {
	let model: SettingsModel

	/** What a capability does, in one sentence, for the switch that turns it
	 off. Keyed by the wire name the registry declares, because that name is
	 what the pane shows and what the disabled list stores.

	 A capability with no entry here has no summary to show rather than an
	 English fallback in a translated interface. */
	private static let capabilitySummaries: [String: LocalizedStringResource] = [
		"account-notify": .Settings.ircv3CapabilityAccountNotify,
		"account-tag": .Settings.ircv3CapabilityAccountTag,
		"away-notify": .Settings.ircv3CapabilityAwayNotify,
		"batch": .Settings.ircv3CapabilityBatch,
		"cap-notify": .Settings.ircv3CapabilityCapNotify,
		"chghost": .Settings.ircv3CapabilityChghost,
		"draft/account-registration": .Settings.ircv3CapabilityAccountRegistration,
		"draft/channel-rename": .Settings.ircv3CapabilityChannelRename,
		"extended-join": .Settings.ircv3CapabilityExtendedJoin,
		"extended-monitor": .Settings.ircv3CapabilityExtendedMonitor,
		"invite-notify": .Settings.ircv3CapabilityInviteNotify,
		"labeled-response": .Settings.ircv3CapabilityLabeledResponse,
		"draft/extended-isupport": .Settings.ircv3CapabilityExtendedIsupport,
		"draft/message-redaction": .Settings.ircv3CapabilityMessageRedaction,
		"draft/metadata-2": .Settings.ircv3CapabilityMetadata,
		"message-tags": .Settings.ircv3CapabilityMessageTags,
		"multi-prefix": .Settings.ircv3CapabilityMultiPrefix,
		"draft/multiline": .Settings.ircv3CapabilityMultiline,
		"draft/no-implicit-names": .Settings.ircv3CapabilityNoImplicitNames,
		"draft/pre-away": .Settings.ircv3CapabilityPreAway,
		"sasl": .Settings.ircv3CapabilitySasl,
		"server-time": .Settings.ircv3CapabilityServerTime,
		"setname": .Settings.ircv3CapabilitySetname,
		"soju.im/bouncer-networks": .Settings.ircv3CapabilityBouncerNetworks,
		"soju.im/bouncer-networks-notify": .Settings.ircv3CapabilityBouncerNetworksNotify,
		"standard-replies": .Settings.ircv3CapabilityStandardReplies,
		"userhost-in-names": .Settings.ircv3CapabilityUserhostInNames,
		"znc.in/playback": .Settings.ircv3CapabilityZncPlayback,
		"znc.in/self-message": .Settings.ircv3CapabilityZncSelfMessage,
		"znc.in/server-time": .Settings.ircv3CapabilityZncServerTime,
		"znc.in/server-time-iso": .Settings.ircv3CapabilityZncServerTimeIso,
		"znc.in/tlsinfo": .Settings.ircv3CapabilityZncTlsinfo,
	]

	/// What a capability does, in one sentence, or `nil` for a name the session
	/// does not negotiate on its own.
	static func summary(for name: String) -> LocalizedStringResource? {
		capabilitySummaries[name]
	}

	/// The sentence a screen reader hears for one capability switch: the wire
	/// name and what it does, localized as one string rather than assembled.
	static func accessibilityLabel(for name: String, summary: String?) -> String {
		guard let summary else { return name }
		return String(localized: .Settings.ircv3CapabilityAccessibilityLabel(name, summary))
	}

	/** The capabilities this pane switches individually.

	 A capability gated by a setting of its own — chat history, read
	 markers, echo-message — keeps that switch and stays out of this list, so
	 the draft and final spellings of one feature never appear as two
	 controls. A capability's unprefixed alias is the same feature under its
	 ratified name, so it shares the switch of the name it stands for. */
	private var switchableCapabilities: [Capability] {
		CapabilityRegistry.defaultRegistry.capabilities
			.filter { $0.gate == .always && $0.aliasOf == nil }
			.sorted { $0.name < $1.name }
	}

	/** A capability's switch, read and written through the list of disabled
	 names: on means the name is absent. Absence as the enabled state is what
	 lets a capability added later start enabled. Every spelling of the feature
	 counts, so a switch-off stored under an older spelling still reads as off,
	 and turning the feature on clears them all. */
	private func capabilityBinding(for capability: Capability) -> Binding<Bool> {
		let disabled = model.settings.binding(for: SettingsKeys.Connection.disabledCapabilities)
		let spellings = CapabilityRegistry.defaultRegistry.spellings(of: capability)

		return Binding(
			get: { spellings.isDisjoint(with: disabled.wrappedValue) },
			set: { isEnabled in
				var names = Set(disabled.wrappedValue)

				if isEnabled {
					names.subtract(spellings)
				} else {
					names.insert(capability.name)
				}

				disabled.wrappedValue = names.sorted()
			}
		)
	}

	var body: some View {
		Section {
			SettingsToggle(
				title: .Settings.ircv3DisplayTypingNotifications,
				isOn: model.settings.binding(for: SettingsKeys.Connection.displayTypingNotifications)
			)
			SettingsToggle(
				title: .Settings.ircv3SendTypingNotifications,
				isOn: model.settings.binding(for: SettingsKeys.Connection.sendTypingNotifications)
			)
			SettingsToggle(
				title: .Settings.ircv3EchoMessage,
				isOn: model.settings.binding(for: SettingsKeys.Connection.echoMessageCapability)
			)
			SettingsToggle(
				title: .Settings.ircv3ShowChannelContextInChannel,
				isOn: model.settings.binding(for: SettingsKeys.Connection.showChannelContextMessagesInChannel)
			)
		} header: {
			Text(.Settings.ircv3Messages)
		} footer: {
			Text(.Settings.ircv3ReconnectNote)
		}

		Section {
			SettingsToggle(
				title: .Settings.ircv3RequestChatHistory,
				isOn: model.settings.binding(for: SettingsKeys.Connection.requestChatHistory)
			)
			SettingsToggle(
				title: .Settings.ircv3DiscoverMissedDirectMessages,
				isEnabled: model.settings[SettingsKeys.Connection.requestChatHistory],
				isOn: model.settings.binding(for: SettingsKeys.Connection.discoverMissedDirectMessages)
			)
			SettingsToggle(
				title: .Settings.ircv3SynchronizeReadMarkers,
				isOn: model.settings.binding(for: SettingsKeys.Connection.synchronizeReadMarkers)
			)
		} header: {
			Text(.Settings.ircv3History)
		} footer: {
			Text(.Settings.ircv3HistoryNote)
		}

		Section {
			if model.ircv3Connections.isEmpty {
				Text(.Settings.ircv3NoConnections)
					.foregroundStyle(.secondary)
			} else {
				ForEach(model.ircv3Connections) { connection in
					connectionRow(connection)
				}
			}
		} header: {
			Text(.Settings.ircv3ConnectedServers)
		}

		Section {
			ForEach(switchableCapabilities, id: \.name) { capability in
				capabilityRow(capability)
			}
		} header: {
			Text(.Settings.ircv3Capabilities)
		} footer: {
			Text(.Settings.ircv3ReconnectNote)
		}
	}

	private func capabilityRow(_ capability: Capability) -> some View {
		let summary = Self.summary(for: capability.name)

		return SettingsCapabilityToggle(
			name: capability.name,
			summary: summary,
			accessibilityLabel: Self.accessibilityLabel(
				for: capability.name,
				summary: summary.map { String(localized: $0) }
			),
			specification: capability.specification,
			specificationTitle: .Settings.ircv3CapabilitySpecification,
			isOn: capabilityBinding(for: capability)
		)
	}

	private func connectionRow(_ connection: IRCv3ConnectionSummary) -> some View {
		VStack(alignment: .leading, spacing: UISpacing.tight) {
			LabeledContent {
				if connection.isConnected == false {
					Text(.Settings.ircv3Disconnected)
				}
			} label: {
				Label(connection.name, systemImage: connection.isConnected ? "network" : "network.slash")
			}
			if connection.capabilities.isEmpty {
				Text(.Settings.ircv3NoCapabilities)
					.font(.caption)
					.foregroundStyle(.secondary)
			} else {
				Text(verbatim: connection.capabilities.joined(separator: ", "))
					.font(.caption)
					.foregroundStyle(.secondary)
					.textSelection(.enabled)
			}
		}
		.padding(.vertical, 2)
	}
}

/** One protocol capability the user can switch off: its wire name, what it
 does in a sentence, and a link to the document that defines it.

 The name is verbatim because it is the identifier the server and the session
 exchange; the summary is what says why anyone would keep it on. The spoken
 label is passed in already composed, so the sentence a screen reader hears is
 localized as one string rather than assembled here. */
private struct SettingsCapabilityToggle: View {
	let name: String
	let summary: LocalizedStringResource?
	let accessibilityLabel: String
	let specification: URL?
	let specificationTitle: LocalizedStringResource
	@Binding var isOn: Bool

	var body: some View {
		VStack(alignment: .leading, spacing: UISpacing.tight) {
			Toggle(isOn: $isOn) {
				VStack(alignment: .leading, spacing: 2) {
					Text(verbatim: name)
					if let summary {
						Text(summary)
							.font(.callout)
							.foregroundStyle(.secondary)
							.fixedSize(horizontal: false, vertical: true)
					}
				}
			}
			.toggleStyle(.switch)
			.accessibilityLabel(Text(verbatim: accessibilityLabel))

			if let specification {
				Link(destination: specification) {
					Text(specificationTitle)
				}
				.font(.callout)
			}
		}
		.padding(.vertical, 2)
	}
}
