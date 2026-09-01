/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import CocoaExtensions
import os
import UniformTypeIdentifiers

/// What `ResourceFileImporter` can install.
public enum ResourceFileKind: Equatable, Sendable {
	case script
	case extensionBundle
}

/// Installs a script or an extension the user opened from the Finder.
///
/// This was an `NSDocument` subclass named as the `NSDocumentClass` of two
/// declared document types. `NSDocument.read(from:ofType:)` is nonisolated, so
/// the one thing the importer does — put alerts and a save panel on screen —
/// had to start with a runtime assumption about the calling thread, and the
/// document machinery brought an untitled document on reopen with it.
/// `NSApplicationDelegate.application(_:open:)` is main-actor isolated by
/// declaration and hands over the same URLs.
@MainActor
public final class ResourceFileImporter {
	public func open(_ urls: [URL]) {
		Task { @MainActor in
			for url in urls {
				await open(url)
			}
		}
	}

	private func open(_ url: URL) async {
		switch Self.kind(of: url) {
		case .script:
			await performImportOfScriptFile(url)
		case .extensionBundle:
			await performImportOfPluginFile(url)
		case nil:
			Self.logger.error(
				"Opened file '\(url.lastPathComponent, privacy: .public)' is neither a script nor an extension"
			)
		}
	}

	/// What kind of installable `url` names, or nil for anything else.
	///
	/// Separated from the import itself because the import puts alerts and a
	/// save panel on screen: this is the part with an answer worth testing.
	public static func kind(of url: URL) -> ResourceFileKind? {
		var contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType

		if contentType == nil {
			contentType = UTType(filenameExtension: url.pathExtension)
		}

		guard let contentType else {
			return nil
		}

		if let scriptType = UTType(filenameExtension: ResourceDocumentType.scriptFilenameExtension),
		   contentType.conforms(to: scriptType)
		{
			return .script
		}

		if contentType.conforms(to: .bundle),
		   url.pathExtension == ResourceDocumentType.bundleFilenameExtension
		{
			return .extensionBundle
		}

		return nil
	}

	private static let logger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
		category: "ResourceFileImporter"
	)

	// MARK: - Custom Plugin Files

	private func performImportOfPluginFile(_ url: URL) async {
		let filename = url.lastPathComponent

		let performInstall = await confirmImport(of: filename)

		guard performInstall, let extensionsURL = PathInfo.customExtensionsURL else {
			return
		}

		let newPath = extensionsURL.appendingPathComponent(filename)

		guard importItem(url, into: newPath) else {
			return
		}

		let filenameWithoutExtension = (filename as NSString).deletingPathExtension

		_ = await Alerts.run(
			AlertRequest(
				title: PromptStrings.DocumentImport.extensionInstalledTitle(name: filenameWithoutExtension),
				body: PromptStrings.DocumentImport.extensionRestartBody,
				defaultButton: PromptStrings.Action.confirmation
			),
			on: .anyVisibleWindow
		)
	}

	// MARK: - Custom Script Files

	private func performImportOfScriptFile(_ url: URL) async {
		let filename = url.lastPathComponent

		let performInstall = await confirmImport(of: filename)

		guard performInstall,
		      let scriptsURL = SharedApplication.sharedPluginManager().customScriptsURL
		else {
			return
		}

		do {
			try FileManager.default.createDirectory(at: scriptsURL, withIntermediateDirectories: true)
		} catch {
			Self.logger.error("Could not create the scripts directory: \(error.localizedDescription, privacy: .public)")
			return
		}

		let destinationURL = scriptsURL.appendingPathComponent(filename, isDirectory: false)
		guard importItem(url, into: destinationURL) else { return }

		await performImportOfScriptFilePostflight(filename)
		SharedApplication.sharedPluginManager().refreshScriptCommands()
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

	private func confirmImport(of filename: String) async -> Bool {
		await Alerts.run(
			AlertRequest(
				title: PromptStrings.DocumentImport.documentOpenTitle(filename: filename),
				body: PromptStrings.DocumentImport.documentOpenBody,
				defaultButton: PromptStrings.Action.yes,
				alternateButton: PromptStrings.Action.no,
				style: .warning
			),
			on: .anyVisibleWindow
		).response == .default
	}

	// MARK: - General Import Controller

	private func importItem(_ url: URL, into destination: URL) -> Bool {
		let accessWasGranted = url.startAccessingSecurityScopedResource()
		defer {
			if accessWasGranted {
				url.stopAccessingSecurityScopedResource()
			}
		}
		return FileManager.default.replaceItem(
			at: destination,
			withItemAt: url
		)
	}
}
