// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI
import UniformTypeIdentifiers

/** Importing and exporting the settings archive from the main window.

 The archive's import panel, its export panel, the options sheet in front of
 the export and the progress the session reports are one flow with four pieces
 of state, and they have nothing to do with the rest of the window. The window
 owns one of these and hands it to a modifier; `PreferencesTransferSession` is
 shared with the Settings window, which is why the host is stamped before the
 panel opens. */
@MainActor
@Observable
final class MainWindowPreferencesTransferModel {
	let session = PreferencesTransferSession.shared

	fileprivate var importRequest = PendingFileRequest<Void>()
	fileprivate var isChoosingExportOptions = false
	fileprivate var isExportingArchive = false
	fileprivate var archiveDocument: PreferencesPropertyListDocument?

	func requestImport() {
		guard importRequest.request == nil, session.canStart else { return }
		session.host = .mainWindow
		importRequest.present()
	}

	func requestExport() {
		guard session.canStart, isExportingArchive == false, isChoosingExportOptions == false else { return }
		session.host = .mainWindow
		isChoosingExportOptions = true
	}

	fileprivate func completeImport(_ result: Result<URL, Error>, requestID: UUID) {
		guard importRequest.complete(requestID) != nil else { return }
		switch result {
		case let .success(url):
			Task { await session.prepareImport(from: url) }
		case let .failure(error):
			session.report(error)
		}
	}

	fileprivate func export(includeConnectCommands: Bool) {
		Task { @MainActor in
			do {
				let data = try await session.exportData(includeConnectCommands: includeConnectCommands)
				archiveDocument = PreferencesPropertyListDocument(data: data)
				isExportingArchive = true
			} catch {
				session.report(error)
			}
		}
	}

	fileprivate func completeExport(_ result: Result<URL, Error>) {
		archiveDocument = nil
		session.completeExport(result)
	}
}

/// The two panels, the options sheet and the session's own presentation, as one
/// modifier on the window's root view.
private struct MainWindowPreferencesTransferPresentation: ViewModifier {
	@Bindable var model: MainWindowPreferencesTransferModel

	func body(content: Content) -> some View {
		let requestID = model.importRequest.request?.id
		content
			.fileImporter(
				isPresented: PendingFileRequest<Void>.presentation($model.importRequest),
				allowedContentTypes: [.propertyList]
			) { result in
				guard let requestID else { return }
				model.completeImport(result, requestID: requestID)
			}
			.fileExporter(
				isPresented: $model.isExportingArchive,
				document: model.archiveDocument,
				contentType: .propertyList,
				defaultFilename: PreferencesArchive.defaultArchiveFilename,
				onCompletion: model.completeExport
			)
			.modifier(PreferencesTransferPresentation(session: model.session, host: .mainWindow))
			.modifier(PreferencesExportOptionsPresentation(
				isPresented: $model.isChoosingExportOptions,
				export: model.export
			))
	}
}

extension View {
	func preferencesTransfer(_ model: MainWindowPreferencesTransferModel) -> some View {
		modifier(MainWindowPreferencesTransferPresentation(model: model))
	}
}
