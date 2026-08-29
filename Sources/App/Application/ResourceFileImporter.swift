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
		var contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType

		if contentType == nil {
			contentType = UTType(filenameExtension: url.pathExtension)
		}

		guard let contentType else {
			reportUnsupportedFile(url)
			return
		}

		if let scriptType = UTType(filenameExtension: ResourceDocumentType.scriptFilenameExtension),
		   contentType.conforms(to: scriptType)
		{
			performImportOfScriptFile(url)

			return
		}

		if contentType.conforms(to: .bundle),
		   url.pathExtension == ResourceDocumentType.bundleFilenameExtension
		{
			performImportOfPluginFile(url)

			return
		}

		reportUnsupportedFile(url)
	}

	private func reportUnsupportedFile(_ url: URL) {
		Self.logger.error(
			"Opened file '\(url.lastPathComponent, privacy: .public)' is neither a script nor an extension"
		)
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
		guard let scriptsPath = PathInfo.customScripts,
		      Self.url(url, isContainedIn: URL(fileURLWithPath: scriptsPath))
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

		var folderRep = PathInfo.customScriptsURL

		if folderRep.map({ FileManager.default.fileExists(at: $0) }) != true {
			folderRep = PathInfo.userApplicationScriptsURL
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

			DispatchQueue.main.async {
				self.performImportOfScriptFilePostflight(importedFilename)
			}
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
