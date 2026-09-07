/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// One alert per message the transfer workflow produces, shown by whichever
/// view owns the presentation.
private struct PreferencesTransferAlert: ViewModifier {
	let title: String
	let message: String?
	let isEnabled: Bool
	let acknowledge: () -> Void

	func body(content: Content) -> some View {
		content.alert(title, isPresented: Binding(
			get: { isEnabled && message != nil },
			set: { isPresented in
				if isPresented == false {
					acknowledge()
				}
			}
		)) {
			Button(PromptStrings.Action.confirmation, action: acknowledge)
		} message: {
			Text(verbatim: message ?? "")
		}
	}
}

struct PreferencesTransferPreviewView: View {
	@Bindable var session: PreferencesTransferSession
	/// What the sheet was presented with. The session owns the live value; this
	/// is what the sheet keeps drawing while it animates away.
	let presented: PreferencesTransferPreview
	@Environment(\.dismiss) private var dismiss

	private var preview: PreferencesTransferPreview {
		session.preview ?? presented
	}

	var body: some View {
		let plan = preview.plan
		return VStack(alignment: .leading, spacing: 16) {
			Text(.PreferencesTransfer.previewTitle).font(.title2)
			Text(verbatim: preview.filename).foregroundStyle(.secondary)
			/* A legacy file has no restore plan at all, so that segment is
			 absent rather than shown as something the user could pick. */
			Picker(selection: $session.previewMode) {
				Text(.PreferencesTransfer.merge).tag(PreferencesTransferMode.merge)
				if preview.supportsRestore {
					Text(.PreferencesTransfer.restore).tag(PreferencesTransferMode.restore)
				}
			} label: { Text(.PreferencesTransfer.mode) }
				.pickerStyle(.segmented)
			if preview.supportsRestore == false {
				Text(.PreferencesTransfer.legacyNotice).foregroundStyle(.secondary)
			}
			Text(preview.mode == .restore ? .PreferencesTransfer.restoreNotice : .PreferencesTransfer
				.applySettingsAndAddOrUpdateServers)
			Text(preview.archive.source == .localRecovery ? .PreferencesTransfer.localRecoveryNotice
				: .PreferencesTransfer.passwordsAndCertificatesStayOnThisMac)
				.font(.callout).foregroundStyle(.secondary)
			ScrollView {
				VStack(alignment: .leading, spacing: 8) {
					if let plan {
						Text(.PreferencesTransfer.preferencesChanged(plan.changedKeys.count))
						ForEach(plan.changedKeys, id: \.self) { name in
							Label(name, systemImage: plan.removedKeys.contains(name) ? "minus.circle" : "pencil")
								.font(.caption)
						}
						clientList(plan.addedClients, title: String(localized: .PreferencesTransfer.serversToAdd))
						clientList(plan.updatedClients, title: String(localized: .PreferencesTransfer.serversToUpdate))
						clientList(plan.removedClients, title: String(localized: .PreferencesTransfer.serversToRemove))
						if !preview.archive.ignoredKeys.isEmpty {
							Text(.PreferencesTransfer.keysNotImported(preview.archive.ignoredKeys.count))
							ForEach(preview.archive.ignoredKeys, id: \.self) { Text(verbatim: $0).font(.caption) }
						}
					} else {
						Text(.PreferencesTransfer.fileIsNotAValidConfigurationSnapshot).foregroundStyle(.red)
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
				Button(preview.mode == .restore ? .PreferencesTransfer.restore : .PreferencesTransfer.merge) {
					Task { await session.commitPreview() }
				}
				.keyboardShortcut(.defaultAction)
				.disabled(plan == nil)
			}
		}
		.padding(24)
		.frame(width: 580, height: 560)
		.disabled(session.isBusy)
		.interactiveDismissDisabled(session.isBusy)
		.modifier(PreferencesTransferAlert(
			title: String(localized: .PreferencesTransfer.configurationTransferStopped),
			message: session.errorMessage,
			isEnabled: true,
			acknowledge: session.acknowledge
		))
	}

	private func clientList(_ names: [String], title: String) -> some View {
		VStack(alignment: .leading) {
			Text(verbatim: title).font(.headline)
			Text(verbatim: names.isEmpty ? "0" : names.joined(separator: ", "))
		}
	}
}

/// Recovery is visible every time Settings opens, not only in a transient alert.
struct PreferencesRecoverySection: View {
	@Bindable var session = PreferencesTransferSession.shared
	@State private var importRequest = PendingFileRequest<Void>()
	@State private var exporting = false
	@State private var choosingExportOptions = false
	@State private var document: PreferencesPropertyListDocument?

	var body: some View {
		let importRequestID = importRequest.request?.id
		Section {
			HStack {
				Button(.PreferencesTransfer.importConfiguration) {
					session.host = .settings
					importRequest.present()
				}
				Button(.PreferencesTransfer.exportConfiguration) {
					session.host = .settings
					choosingExportOptions = true
				}
			}
			.disabled(
				session.canStart == false || importRequest.request != nil || exporting || choosingExportOptions
			)
			Text(.PreferencesTransfer.backupsNotice).font(.callout).foregroundStyle(.secondary)
			if let result = session.result {
				Text(verbatim: result.summary)
			}
			ForEach(session.backups) { backup in
				HStack {
					Text(backup.created, format: .dateTime.year().month().day().hour().minute().second())
					Spacer()
					Button(.PreferencesTransfer.previewBackup) {
						session.host = .settings
						Task { await session.prepareRecovery(backup) }
					}
					.disabled(session.canStart == false)
				}
			}
			if let newest = session.backups.first {
				/* Reveal the newest backup rather than opening the folder: the
				 Finder window comes up with the file selected, and a folder URL
				 handed to `openURL` is a document the workspace opens. */
				Button(.PreferencesTransfer.showBackups) {
					NSWorkspace.shared.activateFileViewerSelecting([newest.url])
				}
			}
		} header: { Text(.PreferencesTransfer.configuration) }
			.task { await session.refreshBackups() }
			.modifier(PreferencesExportOptionsPresentation(
				isPresented: $choosingExportOptions,
				export: { includeCommands in
					Task {
						do {
							document = try await PreferencesPropertyListDocument(data: session
								.exportData(includeConnectCommands: includeCommands))
							exporting = true
						} catch { session.report(error) }
					}
				}
			))
			.fileImporter(
				isPresented: PendingFileRequest<Void>.presentation($importRequest),
				allowedContentTypes: [.propertyList]
			) { result in
				guard let importRequestID, importRequest.complete(importRequestID) != nil else { return }
				switch result {
				case let .success(url): Task { await session.prepareImport(from: url) }
				case let .failure(error): session.report(error)
				}
			}
			.fileExporter(isPresented: $exporting, document: document, contentType: .propertyList,
			              defaultFilename: PreferencesImportExport.defaultArchiveFilename)
			{ result in
				document = nil
				session.completeExport(result)
			}
	}
}

/// Both export entry points require an explicit selection, reset to OFF for each export.
struct PreferencesExportOptionsView: View {
	let confirm: (Bool) -> Void
	@Environment(\.dismiss) private var dismiss
	@State private var includeConnectCommands = false

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			Text(.PreferencesTransfer.exportOptions).font(.title2)
			Toggle(.PreferencesTransfer.includeConnectCommands, isOn: $includeConnectCommands)
			Text(.PreferencesTransfer.connectCommandsWarning).font(.callout).foregroundStyle(.secondary)
			HStack {
				Spacer()
				Button(PromptStrings.Action.cancel) { dismiss() }.keyboardShortcut(.cancelAction)
				Button(PromptStrings.ConfigurationTransfer.exportButtonTitle) { confirm(includeConnectCommands) }
					.keyboardShortcut(.defaultAction)
			}
		}
		.padding(24)
		.frame(width: 460)
		.onAppear { includeConnectCommands = false }
	}
}

struct PreferencesExportOptionsPresentation: ViewModifier {
	@Binding var isPresented: Bool
	let export: (Bool) -> Void
	@State private var confirmedChoice: Bool?

	func body(content: Content) -> some View {
		content.sheet(isPresented: $isPresented, onDismiss: {
			if let choice = confirmedChoice {
				confirmedChoice = nil
				export(choice)
			}
		}, content: {
			PreferencesExportOptionsView { includeCommands in
				confirmedChoice = includeCommands
				isPresented = false
			}
		})
	}
}

struct PreferencesTransferPresentation: ViewModifier {
	@Bindable var session: PreferencesTransferSession
	let host: PreferencesTransferHost
	/// The sheet outlives `session.preview` by one dismissal animation, and an
	/// alert raised in that window would land behind it.
	@State private var previewIsPresented = false

	/// Whether this host is the one that should be answering for the workflow.
	private var ownsPresentation: Bool {
		session.host == host && session.preview == nil && previewIsPresented == false
	}

	func body(content: Content) -> some View {
		content
			.sheet(item: Binding(
				get: { session.host == host ? session.preview : nil },
				set: { preview in
					if preview == nil, session.host == host {
						session.cancelPreview()
					}
				}
			), onDismiss: { previewIsPresented = false }, content: { preview in
				PreferencesTransferPreviewView(session: session, presented: preview)
					.onAppear { previewIsPresented = true }
			})
			.modifier(PreferencesTransferAlert(
				title: String(localized: .PreferencesTransfer.configurationTransferStopped),
				message: session.errorMessage,
				isEnabled: ownsPresentation,
				acknowledge: session.acknowledge
			))
			.modifier(PreferencesTransferAlert(
				title: String(localized: .PreferencesTransfer.configurationTransferComplete),
				message: session.completionMessage,
				isEnabled: ownsPresentation,
				acknowledge: session.acknowledge
			))
	}
}
