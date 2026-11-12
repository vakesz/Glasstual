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
	@State private var exportData: Data?

	private var exporting: Binding<Bool> {
		Binding(
			get: { exportData != nil },
			set: {
				if $0 == false {
					exportData = nil
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
				.accessibilityIdentifier(AccessibilityIdentifier.settingsImport)
				Button(.SettingsTransfer.exportConfiguration) {
					session.host = .settings
					choosingExportOptions = true
				}
				.accessibilityIdentifier(AccessibilityIdentifier.settingsExport)
			}
			.disabled(
				session.canStart == false || importRequest.request != nil
					|| exportData != nil || choosingExportOptions
			)
			ForEach(session.backups) { backup in
				LabeledContent {
					Button(.SettingsTransfer.previewBackup) {
						session.host = .settings
						Task { await session.prepareRecovery(backup) }
					}
					.disabled(session.canStart == false)
					.accessibilityIdentifier(AccessibilityIdentifier.settingsRecoveryPreview)
				} label: {
					Text(backup.created, format: .dateTime.year().month().day().hour().minute().second())
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
			Text(.SettingsTransfer.backupsNotice)
		}
		.task { await session.refreshBackups() }
		.modifier(SettingsExportOptionsPresentation(
			isPresented: $choosingExportOptions,
			export: { includeCommands in
				Task {
					do {
						exportData = try await session.exportData(includeConnectCommands: includeCommands)
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
		.fileExporter(isPresented: exporting, item: exportData.map(PropertyListExport.init(data:)), contentTypes: [.propertyList],
		              defaultFilename: SettingsArchive.defaultArchiveFilename)
		{ result in
			exportData = nil
			session.completeExport(result)
		} onCancellation: {
			exportData = nil
			session.completeExport(.failure(CocoaError(.userCancelled)))
		}
		.fileDialogDefaultDirectory(ApplicationPaths.reviewFileDialogURL)
	}
}
