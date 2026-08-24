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
import UniformTypeIdentifiers

private let scriptDocumentTypeName = "Glasstual IRC Client Script"
private let pluginDocumentTypeName = "Glasstual IRC Client Extension"

@objc(TPCResourceManagerDocumentTypeImporter)
public final class ResourceManagerDocumentTypeImporter: NSDocument, NSOpenSavePanelDelegate {
	override public class var autosavesInPlace: Bool {
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

		if let scriptType = UTType(filenameExtension: TPCResourceManagerScriptDocumentTypeExtensionWithoutPeriod),
		   contentType.conforms(to: scriptType)
		{
			performImportOfScriptFile(url)

			return
		}

		if contentType.conforms(to: .bundle),
		   url.pathExtension == TPCResourceManagerBundleDocumentTypeExtensionWithoutPeriod
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
			withMessage: LocalizedKey("Prompts[6tj-yp]"),
			title: LocalizedKey("Prompts[xfl-8e]", filename),
			defaultButton: LocalizedKey("Prompts[mvh-ms]"),
			alternateButton: LocalizedKey("Prompts[99q-gg]")
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
			withMessage: LocalizedKey("Prompts[k69-q0]"),
			title: LocalizedKey("Prompts[xek-0t]", filenameWithoutExtension),
			defaultButton: LocalizedKey("Prompts[c7s-dq]"),
			alternateButton: nil
		)
	}

	// MARK: - Custom Script Files

	public func panel(_: Any, validate url: URL) throws {
		guard let scriptsPath = PathInfo.customScripts, url.path.hasPrefix(scriptsPath) else {
			throw NSError(
				domain: TXErrorDomain,
				code: 27984,
				userInfo: [
					NSURLErrorKey: url,
					NSLocalizedDescriptionKey: LocalizedKey("Prompts[m2r-gv]"),
					NSLocalizedRecoverySuggestionErrorKey: LocalizedKey("Prompts[ztu-nv]"),
				]
			)
		}
	}

	@MainActor
	private func performImportOfScriptFile(_ url: URL) {
		let filename = url.lastPathComponent

		let performInstall = TDCAlert.modalAlert(
			withMessage: LocalizedKey("Prompts[6tj-yp]"),
			title: LocalizedKey("Prompts[xfl-8e]", filename),
			defaultButton: LocalizedKey("Prompts[mvh-ms]"),
			alternateButton: LocalizedKey("Prompts[99q-gg]")
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
		savePanel.title = LocalizedKey("Prompts[6hx-ni]")
		savePanel.message = LocalizedKey("Prompts[0bj-ic]", bundleID)
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
			withMessage: LocalizedKey("Prompts[3ze-xh]", filenameWithoutExtension),
			title: LocalizedKey("Prompts[4ua-v5]", filenameWithoutExtension),
			defaultButton: LocalizedKey("Prompts[c7s-dq]"),
			alternateButton: nil
		)
	}

	// MARK: - General Import Controller

	private func importItem(_ url: URL, into destination: URL) -> Bool {
		FileManager.default.replaceItem(
			at: destination,
			withItemAt: url,
			options: [.optionsMoveToTrash, .optionsRemoveIfExists]
		)
	}
}
