// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

/// The one message the transfer workflow is waiting to have acknowledged,
/// shown by whichever view owns the presentation.
struct SettingsTransferAlert: ViewModifier {
	let message: SettingsTransferMessage?
	let acknowledge: () -> Void

	func body(content: Content) -> some View {
		content.alert(
			message?.title ?? "",
			isPresented: Binding(
				get: { message != nil },
				set: { isPresented in
					if isPresented == false {
						acknowledge()
					}
				}
			),
			presenting: message
		) { _ in
			Button(PromptStrings.Action.confirmation, action: acknowledge)
				.accessibilityIdentifier(AccessibilityIdentifier.settingsTransferResultConfirm)
		} message: { message in
			Text(verbatim: message.body)
		}
	}
}

/// One setting an import would change, under the name Settings shows it with,
/// or its stored name when no pane shows it.
private struct ChangedSetting: Identifiable {
	let id: String
	let displayName: String?
	let isRemoved: Bool

	var title: String {
		displayName ?? id
	}
}

struct SettingsTransferPreviewView: View {
	@Bindable var session: SettingsTransferSession
	/// What the sheet was presented with. The session owns the live value; this
	/// is what the sheet keeps drawing while it animates away.
	let presented: SettingsTransferPreview
	@Environment(\.dismiss) private var dismiss

	private var preview: SettingsTransferPreview {
		session.preview ?? presented
	}

	var body: some View {
		let plan = preview.plan
		return VStack(spacing: 0) {
			SheetHeading(.SettingsTransfer.previewTitle, subtitle: Text(verbatim: preview.filename))

			VStack(alignment: .leading, spacing: UISpacing.wide) {
				Picker(selection: $session.previewMode) {
					Text(.SettingsTransfer.merge).tag(SettingsTransferMode.merge)
						.disabled(preview.supports(.merge) == false)
					Text(.SettingsTransfer.restore).tag(SettingsTransferMode.restore)
						.disabled(preview.supports(.restore) == false)
				} label: { Text(.SettingsTransfer.mode) }
					.pickerStyle(.segmented)
					.fixedSize()
				Text(preview.mode == .restore ? .SettingsTransfer.restoreNotice : .SettingsTransfer
					.applySettingsAndAddOrUpdateServers)
					.fixedSize(horizontal: false, vertical: true)
				Text(preview.archive.source == .localRecovery ? .SettingsTransfer.localRecoveryNotice
					: .SettingsTransfer.passwordsAndCertificatesStayOnThisMac)
					.font(.callout).foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
				GroupBox {
					ScrollView {
						VStack(alignment: .leading, spacing: UISpacing.regular) {
							if let plan {
								riskyChanges(in: plan)
								changedSettings(in: plan)
								sessions(plan.addedSessions, title: String(localized: .SettingsTransfer.serversToAdd))
								sessions(plan.updatedSessions, title: String(localized: .SettingsTransfer.serversToUpdate))
								sessions(plan.removedSessions, title: String(localized: .SettingsTransfer.serversToRemove))
								if preview.archive.ignoredKeys.isEmpty == false {
									Text(.SettingsTransfer.keysNotImported(preview.archive.ignoredKeys.count))
								}
							} else {
								ValidationMessageLabel(String(localized: .SettingsTransfer.fileIsNotAValidConfigurationSnapshot))
							}
						}
						.frame(maxWidth: .infinity, alignment: .leading)
						.padding(UISpacing.tight)
					}
				}
				.accessibilityIdentifier(AccessibilityIdentifier.settingsTransferPreview)
			}
			.padding(.horizontal, SheetMetrics.margin)
			.padding(.top, UISpacing.regular)

			SheetActions(
				confirmTitle: Text(preview.mode == .restore ? .SettingsTransfer.restore : .SettingsTransfer.merge),
				confirmIsDisabled: plan == nil,
				confirmShortcut: preview.commitIsDefaultAction ? .defaultAction : nil,
				confirmIdentifier: AccessibilityIdentifier.settingsTransferCommit,
				cancelIdentifier: AccessibilityIdentifier.settingsTransferCancel,
				confirm: { Task { await session.commitPreview() } },
				cancel: { session.cancelPreview(); dismiss() },
				leading: {
					if session.isBusy {
						ProgressView().controlSize(.small)
					}
				}
			)
		}
		.sheetFrame(.wide, minHeight: 480, idealHeight: 560)
		.disabled(session.isBusy)
		.interactiveDismissDisabled(session.isBusy)
		.modifier(SettingsTransferAlert(
			message: session.previewMessage,
			acknowledge: session.acknowledge
		))
	}

	/** What the import would change, under the names the Settings window uses.

	 A stored key no pane shows is listed under its stored name: it is the only
	 name it has, and a file someone handed over is exactly where an
	 unexplained change must not hide inside a count. */
	@ViewBuilder
	private func changedSettings(in plan: SettingsTransferPlan) -> some View {
		let settings = plan.changedKeys
			.map { name in
				ChangedSetting(
					id: name,
					displayName: SettingsPaneKeys.displayName(forKeyNamed: name),
					isRemoved: plan.removedKeys.contains(name)
				)
			}
			.sorted { first, second in
				// Named settings first, then stored names, each alphabetically.
				guard (first.displayName == nil) == (second.displayName == nil) else {
					return first.displayName != nil
				}
				return first.title.localizedCaseInsensitiveCompare(second.title) == .orderedAscending
			}

		Text(.SettingsTransfer.preferencesChanged(plan.changedKeys.count))
		ForEach(settings) { setting in
			Label {
				if setting.displayName == nil {
					Text(verbatim: setting.title).monospaced()
				} else {
					Text(verbatim: setting.title)
				}
			} icon: {
				Image(systemName: setting.isRemoved ? "minus.circle" : "pencil")
			}
			.font(.caption)
			.accessibilityLabel(Text(stateDescription(of: setting)))
			.accessibilityIdentifier(AccessibilityIdentifier.settingsTransferChange(setting.id))
		}
	}

	/// What the import does to one setting, which its icon alone does not say to VoiceOver.
	private func stateDescription(of setting: ChangedSetting) -> LocalizedStringResource {
		setting.isRemoved
			? .SettingsTransfer.settingWillBeRemoved(setting.title)
			: .SettingsTransfer.settingWillChange(setting.title)
	}

	/** The changes that can send commands or widen what is trusted, each with
	 the content it would bring in, above everything else in the preview. */
	@ViewBuilder
	private func riskyChanges(in plan: SettingsTransferPlan) -> some View {
		if plan.riskyChanges.isEmpty == false {
			VStack(alignment: .leading, spacing: UISpacing.tight) {
				Label {
					Text(.SettingsTransfer.reviewBeforeImporting)
				} icon: {
					Image(systemName: "exclamationmark.triangle.fill")
						.symbolRenderingMode(.multicolor)
				}
				.font(.headline)
				Text(.SettingsTransfer.riskyChangesNotice)
					.font(.callout)
				ForEach(plan.riskyChanges, id: \.self) { change in
					Text(verbatim: Self.description(of: change))
						.font(.callout.monospaced())
						.textSelection(.enabled)
				}
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(.bottom, UISpacing.regular)
		}
	}

	private static func description(of change: SettingsRiskyChange) -> String {
		switch change {
		case let .messageRuleAction(title, action):
			String(localized: .SettingsTransfer.riskyRuleAction(title, action))
		case let .linkSchemes(schemes):
			String(localized: .SettingsTransfer.riskyLinkSchemes(schemes.formatted(.list(type: .and))))
		case .developerMode:
			String(localized: .SettingsTransfer.riskyDeveloperMode)
		case let .ctcpVersionReply(reply):
			String(localized: .SettingsTransfer.riskyCtcpVersionReply(reply))
		case let .connectCommands(server, commands):
			String(localized: .SettingsTransfer.riskyConnectCommands(server, commands.joined(separator: "\n")))
		case let .serverEndpoint(server, from, to, outcome):
			switch outcome {
			case .sameServer:
				String(localized: .SettingsTransfer.riskyServerEndpointSameServer(
					server, description(of: from), description(of: to)
				))
			case .newServerExistingKept:
				String(localized: .SettingsTransfer.riskyServerEndpointNewKept(
					server, description(of: from), description(of: to)
				))
			case .newServerExistingRemoved:
				String(localized: .SettingsTransfer.riskyServerEndpointNewRemoved(
					server, description(of: from), description(of: to)
				))
			}
		case let .certificateValidationDisabled(server):
			String(localized: .SettingsTransfer.riskyCertificateValidation(server))
		case let .newDestination(server, destination, mode):
			switch mode {
			case .merge:
				String(localized: .SettingsTransfer.riskyNewDestinationKept(server, description(of: destination)))
			case .restore:
				String(localized: .SettingsTransfer.riskyNewDestinationRemoved(server, description(of: destination)))
			}
		}
	}

	private static func description(of destination: SettingsRiskyChange.Destination) -> String {
		switch destination {
		case let .server(endpoint):
			description(of: endpoint)
		case let .proxy(host, port):
			String(localized: .SettingsTransfer.destinationProxy(host, String(port)))
		}
	}

	private static func description(of endpoint: SettingsRiskyChange.Endpoint) -> String {
		if let url = endpoint.webSocketURL {
			return String(localized: .SettingsTransfer.websocketEndpoint(url))
		}
		return endpoint.isEncrypted
			? String(localized: .SettingsTransfer.endpointEncrypted(endpoint.host, String(endpoint.port)))
			: String(localized: .SettingsTransfer.endpointPlain(endpoint.host, String(endpoint.port)))
	}

	@ViewBuilder
	private func sessions(_ names: [String], title: String) -> some View {
		if names.isEmpty == false {
			VStack(alignment: .leading) {
				Text(verbatim: title).font(.headline)
				Text(verbatim: names.formatted(.list(type: .and)))
			}
		}
	}
}
