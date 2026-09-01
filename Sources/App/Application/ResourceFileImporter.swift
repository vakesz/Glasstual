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

import AppKit
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
public final class ResourceFileImporter: NSObject, NSOpenSavePanelDelegate {
	public func open(_ urls: [URL]) {
		for url in urls {
			open(url)
		}
	}

	private func open(_ url: URL) {
		switch Self.kind(of: url) {
		case .script:
			performImportOfScriptFile(url)
		case .extensionBundle:
			performImportOfPluginFile(url)
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

	private func performImportOfPluginFile(_ url: URL) {
		let filename = url.lastPathComponent

		let performInstall = TDCAlert.modalAlert(
			withMessage: PromptStrings.DocumentImport.documentOpenBody,
			title: PromptStrings.DocumentImport.documentOpenTitle(filename: filename),
			defaultButton: PromptStrings.Action.yes,
			alternateButton: PromptStrings.Action.no
		)

		guard performInstall, let extensionsURL = PathInfo.customExtensionsURL else {
			return
		}

		let newPath = extensionsURL.appendingPathComponent(filename)

		guard importItem(url, into: newPath) else {
			return
		}

		let filenameWithoutExtension = (filename as NSString).deletingPathExtension

		_ = TDCAlert.modalAlert(
			withMessage: PromptStrings.DocumentImport.extensionRestartBody,
			title: PromptStrings.DocumentImport.extensionInstalledTitle(name: filenameWithoutExtension),
			defaultButton: PromptStrings.Action.confirmation,
			alternateButton: nil
		)
	}

	// MARK: - Custom Script Files

	public func panel(_: Any, validate url: URL) throws {
		guard let scriptsURL = SharedApplication.sharedPluginManager().customScriptsURL,
		      Self.url(url, isContainedIn: scriptsURL)
		else {
			throw NSError(
				domain: "GlasstualErrorDomain",
				code: 27984,
				userInfo: [
					NSURLErrorKey: url,
					NSLocalizedDescriptionKey: PromptStrings.DocumentImport.scriptSaveErrorTitle,
					NSLocalizedRecoverySuggestionErrorKey: PromptStrings.DocumentImport.scriptSaveErrorBody,
				]
			)
		}
	}

	/// Whether `url` names something inside `directory`.
	///
	/// A string prefix test is not containment: it accepts a sibling whose name
	/// merely starts with the directory's, such as `…/Application Scripts-evil`.
	private static func url(_ url: URL, isContainedIn directory: URL) -> Bool {
		let components = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
		let directoryComponents = directory.standardizedFileURL.resolvingSymlinksInPath().pathComponents

		guard components.count > directoryComponents.count else {
			return false
		}

		return Array(components.prefix(directoryComponents.count)) == directoryComponents
	}

	private func performImportOfScriptFile(_ url: URL) {
		let filename = url.lastPathComponent

		let performInstall = TDCAlert.modalAlert(
			withMessage: PromptStrings.DocumentImport.documentOpenBody,
			title: PromptStrings.DocumentImport.documentOpenTitle(filename: filename),
			defaultButton: PromptStrings.Action.yes,
			alternateButton: PromptStrings.Action.no
		)

		guard performInstall else {
			return
		}

		var folderRep = SharedApplication.sharedPluginManager().customScriptsURL

		if folderRep.map({ FileManager.default.fileExists(at: $0) }) != true {
			folderRep = folderRep?.deletingLastPathComponent()
		}

		let bundleID = ApplicationInfo.applicationBundleIdentifier()
		let savePanel = NSSavePanel()

		savePanel.delegate = self
		savePanel.canCreateDirectories = true
		savePanel.directoryURL = folderRep
		savePanel.title = PromptStrings.Action.save
		savePanel.message = PromptStrings.DocumentImport.scriptSavePanelBody(bundleIdentifier: bundleID)
		savePanel.nameFieldStringValue = url.lastPathComponent
		savePanel.showsTagField = false

		savePanel.begin { [weak self] returnCode in
			guard let self, returnCode == .OK, let destinationURL = savePanel.url else {
				return
			}

			guard importItem(url, into: destinationURL) else {
				return
			}

			let importedFilename = destinationURL.lastPathComponent

			performImportOfScriptFilePostflight(importedFilename)
			SharedApplication.sharedPluginManager().refreshScriptCommands()
		}
	}

	private func performImportOfScriptFilePostflight(_ filename: String) {
		let filenameWithoutExtension = (filename as NSString).deletingPathExtension

		_ = TDCAlert.modalAlert(
			withMessage: PromptStrings.DocumentImport.scriptCommandBody(name: filenameWithoutExtension),
			title: PromptStrings.DocumentImport.scriptInstalledTitle(name: filenameWithoutExtension),
			defaultButton: PromptStrings.Action.confirmation,
			alternateButton: nil
		)
	}

	// MARK: - General Import Controller

	private func importItem(_ url: URL, into destination: URL) -> Bool {
		FileManager.default.replaceItem(
			at: destination,
			withItemAt: url
		)
	}
}
