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

import AppKit
import CocoaExtensions
import os
import UniformTypeIdentifiers

/// What `ResourceFileImporter` can install.
enum ResourceFileKind: Equatable, Sendable {
	case script
}

/// Installs a user script the user opened from the Finder.
///
/// This was an `NSDocument` subclass named as the `NSDocumentClass` of two
/// declared document types. `NSDocument.read(from:ofType:)` is nonisolated, so
/// the one thing the importer does — put alerts and a save panel on screen —
/// had to start with a runtime assumption about the calling thread, and the
/// document machinery brought an untitled document on reopen with it.
/// `NSApplicationDelegate.application(_:open:)` is main-actor isolated by
/// declaration and hands over the same URLs.
@MainActor
final class ResourceFileImporter {
	func open(_ urls: [URL]) {
		Task { @MainActor in
			for url in urls {
				await open(url)
			}
		}
	}

	private func open(_ url: URL) async {
		let accessWasGranted = url.startAccessingSecurityScopedResource()
		defer {
			if accessWasGranted {
				url.stopAccessingSecurityScopedResource()
			}
		}
		switch Self.kind(of: url) {
		case .script:
			await performImportOfScriptFile(url)
		case nil:
			Self.logger.error(
				"Opened file '\(url.lastPathComponent, privacy: .public)' is not a script"
			)
			await presentImportError(CocoaError(.fileReadUnknown))
		}
	}

	/// What kind of installable `url` names, or nil for anything else.
	///
	/// Separated from the import itself because the import puts alerts and a
	/// save panel on screen: this is the part with an answer worth testing.
	static func kind(of url: URL) -> ResourceFileKind? {
		guard url.isFileURL else { return nil }
		var contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType

		if contentType == nil {
			contentType = UTType(filenameExtension: url.pathExtension.lowercased())
		}

		guard let contentType else {
			return nil
		}

		if let scriptType = UTType(filenameExtension: ResourceDocumentType.scriptFilenameExtension),
		   contentType.conforms(to: scriptType)
		{
			return .script
		}

		return nil
	}

	private static let logger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
		category: "ResourceFileImporter"
	)

	// MARK: - Custom Script Files

	private func performImportOfScriptFile(_ url: URL) async {
		do {
			guard UserScript(url: url, origin: .custom)?.kind == .appleScript,
			      NSAppleScript(contentsOf: url, error: nil) != nil
			else { throw ImportError.invalidScript }
			let defaultScriptsURL = ApplicationPaths.customScriptsURL

			guard let scriptsURL = AppServices.scripts.customScriptsURL ?? defaultScriptsURL
			else {
				throw CocoaError(.fileNoSuchFile)
			}
			if url.resolvingSymlinksInPath().standardizedFileURL.deletingLastPathComponent() ==
				scriptsURL.resolvingSymlinksInPath().standardizedFileURL
			{
				AppServices.scripts.refreshCommands()
				await performImportOfScriptFilePostflight(url.lastPathComponent)
				return
			}
			_ = await Alerts.run(
				AlertRequest(
					title: String(localized: .Scripts.scriptInstallTitle),
					body: String(localized: .Scripts.scriptInstallInstructions(scriptsURL.path)),
					defaultButton: PromptStrings.Action.confirmation
				),
				on: .anyVisibleWindow
			)
			// Application Scripts is read-only to the sandbox. Finder performs the copy.
			NSWorkspace.shared.activateFileViewerSelecting([url, scriptsURL])
		} catch {
			await presentImportError(error)
		}
	}

	private func performImportOfScriptFilePostflight(_ filename: String) async {
		let filenameWithoutExtension = (filename as NSString).deletingPathExtension

		_ = await Alerts.run(
			AlertRequest(
				title: PromptStrings.DocumentImport.scriptInstalledTitle(name: filenameWithoutExtension),
				body: PromptStrings.DocumentImport.scriptCommandBody(name: filenameWithoutExtension),
				defaultButton: PromptStrings.Action.confirmation
			),
			on: .anyVisibleWindow
		)
	}

	// MARK: - General Import Controller

	private nonisolated enum ImportError: LocalizedError { // nonisolated: value
		case invalidScript

		var errorDescription: String? {
			switch self {
			case .invalidScript: String(localized: .Scripts.invalidScript)
			}
		}
	}

	private func presentImportError(_ error: Error) async {
		Self.logger.error("Script installation failed: \(error.localizedDescription, privacy: .public)")
		_ = await Alerts.run(
			AlertRequest(
				title: String(localized: .Scripts.importFailedTitle),
				body: error.localizedDescription,
				defaultButton: PromptStrings.Action.confirmation
			),
			on: .anyVisibleWindow
		)
	}
}
