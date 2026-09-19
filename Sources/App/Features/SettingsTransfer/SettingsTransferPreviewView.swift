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
		return VStack(alignment: .leading, spacing: UISpacing.loose) {
			Text(.SettingsTransfer.previewTitle).font(.title2)
			Text(verbatim: preview.filename).foregroundStyle(.secondary)
			Picker(selection: $session.previewMode) {
				Text(.SettingsTransfer.merge).tag(SettingsTransferMode.merge)
				Text(.SettingsTransfer.restore).tag(SettingsTransferMode.restore)
			} label: { Text(.SettingsTransfer.mode) }
				.pickerStyle(.segmented)
			Text(preview.mode == .restore ? .SettingsTransfer.restoreNotice : .SettingsTransfer
				.applySettingsAndAddOrUpdateServers)
			Text(preview.archive.source == .localRecovery ? .SettingsTransfer.localRecoveryNotice
				: .SettingsTransfer.passwordsAndCertificatesStayOnThisMac)
				.font(.callout).foregroundStyle(.secondary)
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
						Text(.SettingsTransfer.fileIsNotAValidConfigurationSnapshot).foregroundStyle(.red)
					}
				}
				.frame(maxWidth: .infinity, alignment: .leading)
			}
			HStack {
				if session.isBusy {
					ProgressView().controlSize(.small)
				}
				Spacer()
				Button(PromptStrings.Action.cancel) { session.cancelPreview(); dismiss() }
					.keyboardShortcut(.cancelAction)
				/* Restore replaces the whole configuration — it resets every
				 setting the file leaves out and removes every server it does not
				 list — and a file that adds commands or trusted schemes needs
				 reading before it is accepted, so Return does neither. Only a
				 Merge with nothing to review, which writes just the settings and
				 servers the file carries, is bound to the default action. */
				Button(preview.mode == .restore ? .SettingsTransfer.restore : .SettingsTransfer.merge) {
					Task { await session.commitPreview() }
				}
				.keyboardShortcut(
					preview.mode == .merge && plan?.riskyChanges.isEmpty == true ? .defaultAction : nil
				)
				.disabled(plan == nil)
			}
		}
		.padding(SettingsWindowMetrics.sheetInset)
		.frame(width: 580, height: 560)
		.disabled(session.isBusy)
		.interactiveDismissDisabled(session.isBusy)
		.modifier(SettingsTransferAlert(
			message: session.pendingMessage,
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
		}
	}

	/** The changes that can send commands or widen what is trusted, each with
	 the content it would bring in, above everything else in the preview. */
	@ViewBuilder
	private func riskyChanges(in plan: SettingsTransferPlan) -> some View {
		if plan.riskyChanges.isEmpty == false {
			VStack(alignment: .leading, spacing: UISpacing.tight) {
				Label(.SettingsTransfer.reviewBeforeImporting, systemImage: "exclamationmark.triangle.fill")
					.font(.headline)
					.foregroundStyle(.orange)
				Text(.SettingsTransfer.riskyChangesNotice)
					.font(.callout)
				ForEach(plan.riskyChanges, id: \.self) { change in
					Text(verbatim: Self.description(of: change))
						.font(.callout.monospaced())
						.textSelection(.enabled)
				}
			}
			.padding(UISpacing.regular)
			.frame(maxWidth: .infinity, alignment: .leading)
			.background(.orange.opacity(0.12), in: .rect(cornerRadius: UISpacing.regular))
		}
	}

	private static func description(of change: SettingsRiskyChange) -> String {
		switch change {
		case let .messageRuleAction(title, action):
			String(localized: .SettingsTransfer.riskyChatFilterAction(title, action))
		case let .linkSchemes(schemes):
			String(localized: .SettingsTransfer.riskyLinkSchemes(schemes.formatted(.list(type: .and))))
		case .developerMode:
			String(localized: .SettingsTransfer.riskyDeveloperMode)
		case let .ctcpVersionReply(reply):
			String(localized: .SettingsTransfer.riskyCtcpVersionReply(reply))
		case let .connectCommands(server, commands):
			String(localized: .SettingsTransfer.riskyConnectCommands(server, commands.joined(separator: "\n")))
		}
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
