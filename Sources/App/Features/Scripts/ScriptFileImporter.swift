// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import os
import UniformTypeIdentifiers

/// Validates scripts opened from Finder and presents installation instructions.
@MainActor
enum ScriptFileImporter {
	static func open(_ urls: [URL]) {
		Task { @MainActor in
			for url in urls {
				await open(url)
			}
		}
	}

	private static func open(_ url: URL) async {
		let accessWasGranted = url.startAccessingSecurityScopedResource()
		defer {
			if accessWasGranted {
				url.stopAccessingSecurityScopedResource()
			}
		}
		guard Self.isInstallableScript(url) else {
			Self.logger.error(
				"Opened file '\(url.lastPathComponent, privacy: .public)' is not a script"
			)
			await presentImportError(CocoaError(.fileReadUnknown))

			return
		}

		await showInstallationInstructions(url)
	}

	/// Accepts local files whose content type conforms to compiled AppleScript.
	static func isInstallableScript(_ url: URL) -> Bool {
		guard url.isFileURL else { return false }
		var contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType

		if contentType == nil {
			contentType = UTType(filenameExtension: url.pathExtension.lowercased())
		}

		guard
			let contentType,
			let scriptType = UTType(filenameExtension: ResourceDocumentKind.scriptFilenameExtension)
		else {
			return false
		}

		return contentType.conforms(to: scriptType)
	}

	private static let logger = Logger(
		subsystem: LogSubsystem.current,
		category: "ScriptFileImporter"
	)

	private static func showInstallationInstructions(_ url: URL) async {
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
				await showInstalledScript(url.lastPathComponent)
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

	private static func showInstalledScript(_ filename: String) async {
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

	private nonisolated enum ImportError: LocalizedError {
		case invalidScript

		var errorDescription: String? {
			switch self {
			case .invalidScript: String(localized: .Scripts.invalidScript)
			}
		}
	}

	private static func presentImportError(_ error: Error) async {
		logger.error("Script installation failed: \(error.localizedDescription, privacy: .public)")
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
