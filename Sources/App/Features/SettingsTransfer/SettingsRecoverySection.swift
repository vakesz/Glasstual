// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Recovery is visible every time Settings opens, not only in a transient alert.
struct SettingsRecoverySection: View {
	@Bindable var session = SettingsTransferSession.shared
	@State private var importRequest = PendingFileRequest<Void>()
	@State private var choosingExportOptions = false
	@State private var document: SettingsPropertyListDocument?

	private var exporting: Binding<Bool> {
		Binding(
			get: { document != nil },
			set: {
				if $0 == false {
					document = nil
				}
			}
		)
	}

	var body: some View {
		let importRequestID = importRequest.request?.id
		Section {
			HStack {
				Button(.SettingsTransfer.importConfiguration) {
					session.host = .settings
					importRequest.present()
				}
				Button(.SettingsTransfer.exportConfiguration) {
					session.host = .settings
					choosingExportOptions = true
				}
			}
			.disabled(
				session.canStart == false || importRequest.request != nil
					|| document != nil || choosingExportOptions
			)
			ForEach(session.backups) { backup in
				HStack {
					Text(backup.created, format: .dateTime.year().month().day().hour().minute().second())
					Spacer()
					Button(.SettingsTransfer.previewBackup) {
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
				Button(.SettingsTransfer.showBackups) {
					NSWorkspace.shared.activateFileViewerSelecting([newest.url])
				}
			}
		} header: {
			Text(.SettingsTransfer.settingsAndRecovery)
		} footer: {
			Text(.SettingsTransfer.backupsNotice).font(.callout).foregroundStyle(.secondary)
		}
		.task { await session.refreshBackups() }
		.modifier(SettingsExportOptionsPresentation(
			isPresented: $choosingExportOptions,
			export: { includeCommands in
				Task {
					do {
						document = try await SettingsPropertyListDocument(data: session
							.exportData(includeConnectCommands: includeCommands))
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
		.fileExporter(isPresented: exporting, document: document, contentType: .propertyList,
		              defaultFilename: SettingsArchive.defaultArchiveFilename)
		{ result in
			document = nil
			session.completeExport(result)
		}
	}
}
