/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit
import CocoaExtensions
import UniformTypeIdentifiers

private let scriptDocumentTypeName = "Glasstual IRC Client Script"
private let pluginDocumentTypeName = "Glasstual IRC Client Extension"

@objc(TPCResourceManagerDocumentTypeImporter)
public final class ResourceManagerDocumentTypeImporter: NSDocument, NSOpenSavePanelDelegate {
	override public static var autosavesInPlace: Bool {
		true
	}

	override public func read(from url: URL, ofType typeName: String) throws {
		try MainActor.assumeIsolated {
			try performRead(from: url, ofType: typeName)
		}
	}

	@MainActor
	private func performRead(from url: URL, ofType typeName: String) throws {
		if typeName == scriptDocumentTypeName {
			performImportOfScriptFile(url)

			return
		}

		if typeName == pluginDocumentTypeName {
			performImportOfPluginFile(url)

			return
		}

		var contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType

		if contentType == nil {
			contentType = UTType(filenameExtension: url.pathExtension)
		}

		guard let contentType else {
			throw CocoaError(.fileReadUnknown)
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

		throw CocoaError(.fileReadUnknown)
	}

	// MARK: - Custom Plugin Files

	@MainActor
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

	@MainActor
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

	@MainActor
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
