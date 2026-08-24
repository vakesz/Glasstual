/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit
import os
import UniformTypeIdentifiers

private let importExportLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "PreferencesImportExport"
)

@objc(TPCPreferencesImportExport)
@MainActor
public final class PreferencesImportExport: NSObject {
	@objc(importInWindow:)
	public class func `import`(in window: NSWindow) {
		TDCAlert.alertSheet(
			with: window,
			body: LocalizedKey("Prompts[jsh-1a]"),
			title: LocalizedKey("Prompts[itb-3x]"),
			defaultButton: LocalizedKey("Prompts[502-6h]"),
			alternateButton: LocalizedKey("Prompts[qso-2g]"),
			otherButton: nil,
			completionBlock: { buttonClicked, _, _ in
				importPreflight(buttonClicked, in: window)
			}
		)
	}

	private class func importPreflight(_ buttonPressed: TDCAlertResponse, in window: NSWindow) {
		guard buttonPressed == .default else {
			return
		}

		let panel = NSOpenPanel()
		panel.canChooseFiles = true
		panel.canChooseDirectories = false
		panel.canCreateDirectories = false
		panel.resolvesAliases = true
		panel.allowsMultipleSelection = false
		panel.allowedContentTypes = [.propertyList]

		panel.beginSheetModal(for: window) { returnCode in
			guard returnCode == .OK, let pathURL = panel.urls.first else {
				return
			}

			importPostflight(pathURL)
		}
	}

	@objc(importPostflightBackupPreferences)
	public class func importPostflightBackupPreferences() -> Bool {
		let backupPath = NSHomeDirectory().appending(
			"/Glasstual-importBackup-\(NSString.withUUID()).plist"
		)

		return exportPostflight(forPath: backupPath, filterJunk: false)
	}

	@objc(importPostflight:)
	public class func importPostflight(_ pathURL: URL) {
		DispatchQueue.main.async {
			importPostflightOnMain(pathURL)
		}
	}

	private class func importPostflightOnMain(_ pathURL: URL) {
		guard importPostflightBackupPreferences() else {
			return
		}

		guard let fileContents = try? Data(contentsOf: pathURL) else {
			return
		}

		var format = PropertyListSerialization.PropertyListFormat.binary
		let propertyList: Any
		do {
			propertyList = try PropertyListSerialization.propertyList(
				from: fileContents,
				options: [],
				format: &format
			)
		} catch {
			importExportLogger.error("Import failed: \(error.localizedDescription, privacy: .public)")
			return
		}

		guard let dictionary = propertyList as? [String: Any] else {
			importExportLogger.error("Import failed: root object is not a dictionary")
			return
		}

		let mainWindow = NSObject.masterController().mainWindow
		mainWindow.loadingScreen?.showProgressView(withReason: LocalizedKey("TVCMainWindow[5g1-i9]"))

		NSObject.masterController().world.isImportingConfiguration = true
		mainWindow.serverList?.beginUpdates()

		importContentsOfDictionary(dictionary, reloadPreferences: false)

		DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
			importPostflightCleanup(Array(dictionary.keys))
		}
	}

	@objc(importContentsOfDictionary:)
	public class func importContentsOfDictionary(_ dictionary: [String: Any]) {
		importContentsOfDictionary(dictionary, reloadPreferences: true)
	}

	@objc(importContentsOfDictionary:reloadPreferences:)
	public class func importContentsOfDictionary(_ dictionary: [String: Any], reloadPreferences: Bool) {
		for (key, object) in dictionary {
			guard key is String, isKeyNameSupposedToBeIgnored(key) == false else {
				continue
			}

			importValue(object, withKey: key)
		}

		if reloadPreferences {
			TPCPreferences.performReloadAction(forKeys: Array(dictionary.keys))
		}
	}

	@objc(import:withKey:)
	public class func importValue(_ object: Any, withKey key: String) {
		if key == TPCPreferencesThemeNameDefaultsKey {
			guard let value = object as? String else {
				return
			}

			TPCPreferences.setThemeNameWithExistenceCheck(value)
		} else if key == TPCPreferencesThemeFontNameDefaultsKey {
			guard let value = object as? String else {
				return
			}

			TPCPreferences.setThemeChannelViewFontNameWithExistenceCheck(value)
		} else if key == IRCWorldClientListDefaultsKey {
			guard let clientList = object as? [Any] else {
				return
			}

			for entry in clientList {
				guard let config = entry as? [String: Any] else {
					continue
				}

				importClientConfiguration(config)
			}
		} else {
			TPCPreferencesUserDefaults.shared()._migrateObject(object, forKey: key)
		}
	}

	@objc(importClientConfiguration:)
	public class func importClientConfiguration(_ config: [String: Any]) {
		let clientConfig = IRCClientConfig(dictionary: config)
		let world = NSObject.masterController().world

		if let client = world.findClient(withId: clientConfig.uniqueIdentifier) {
			client.updateConfig(clientConfig)
		} else {
			_ = world.createClient(with: clientConfig, reload: true)
		}
	}

	@objc(importPostflightCleanup:)
	public class func importPostflightCleanup(_ changedKeys: [String]) {
		TPCPreferences.performReloadAction(forKeys: changedKeys)

		let mainWindow = NSObject.masterController().mainWindow
		mainWindow.serverList?.endUpdates()
		NSObject.masterController().world.isImportingConfiguration = false
		_ = mainWindow.reloadLoadingScreen()
	}

	@objc(isKeyNameSupposedToBeIgnored:)
	public class func isKeyNameSupposedToBeIgnored(_ key: String) -> Bool {
		TPCPreferencesUserDefaults.keyIsExcludedFromExportImport(key)
	}

	@objc(exportedPreferencesDictionary)
	public class func exportedPreferencesDictionary() -> [String: Any] {
		exportedPreferencesDictionary(true, filterDefaults: true)
	}

	@objc(exportedPreferencesDictionary:)
	public class func exportedPreferencesDictionary(_ filterJunk: Bool) -> [String: Any] {
		exportedPreferencesDictionary(filterJunk, filterDefaults: filterJunk)
	}

	@objc(exportedPreferencesDictionary:filterDefaults:)
	public class func exportedPreferencesDictionary(_ filterJunk: Bool, filterDefaults: Bool) -> [String: Any] {
		var keysToStrip: [String] = []

		let argumentsDomain = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
		keysToStrip.append(contentsOf: argumentsDomain.keys)

		if filterDefaults {
			let defaultsDomain = TPCPreferences.defaultPreferences()
			keysToStrip.append(contentsOf: defaultsDomain.keys)
		}

		if filterJunk {
			let globalsDomain = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain) ?? [:]
			keysToStrip.append(contentsOf: globalsDomain.keys)
		}

		let exportedPreferences = TPCPreferencesUserDefaults.shared().dictionaryRepresentation()
		var finalDictionary = exportedPreferences

		for key in keysToStrip {
			finalDictionary.removeValue(forKey: key)
		}

		if filterJunk {
			let keysToStrip2 = finalDictionary.keys.filter { key in
				isKeyNameSupposedToBeIgnored(key)
			}

			for key in keysToStrip2 {
				finalDictionary.removeValue(forKey: key)
			}
		}

		return finalDictionary
	}

	@objc(exportInWindow:)
	public class func export(in window: NSWindow) {
		TDCAlert.alertSheet(
			with: window,
			body: LocalizedKey("Prompts[syp-al]"),
			title: LocalizedKey("Prompts[1fm-up]"),
			defaultButton: LocalizedKey("Prompts[vun-f0]"),
			alternateButton: LocalizedKey("Prompts[qso-2g]"),
			otherButton: nil,
			completionBlock: { buttonClicked, _, _ in
				exportPreflight(buttonClicked, in: window)
			}
		)
	}

	private class func exportPreflight(_ buttonPressed: TDCAlertResponse, in window: NSWindow) {
		guard buttonPressed == .default else {
			return
		}

		let panel = NSSavePanel()
		panel.canCreateDirectories = true
		panel.allowedContentTypes = [.propertyList]
		panel.nameFieldStringValue = "GlasstualPreferences.plist"

		panel.beginSheetModal(for: window) { returnCode in
			guard returnCode == .OK, let pathURL = panel.url else {
				return
			}

			_ = exportPostflight(for: pathURL, filterJunk: true)
		}
	}

	@objc(exportPostflightForPath:)
	public class func exportPostflight(forPath path: String) -> Bool {
		exportPostflight(forPath: path, filterJunk: true)
	}

	@objc(exportPostflightForURL:)
	public class func exportPostflight(for url: URL) -> Bool {
		exportPostflight(for: url, filterJunk: true)
	}

	@objc(exportPostflightForPath:filterJunk:)
	public class func exportPostflight(forPath path: String, filterJunk: Bool) -> Bool {
		exportPostflight(for: URL(fileURLWithPath: path), filterJunk: filterJunk)
	}

	@objc(exportPostflightForURL:filterJunk:)
	public class func exportPostflight(for url: URL, filterJunk: Bool) -> Bool {
		let exportedPreferences = exportedPreferencesDictionary(filterJunk)

		let propertyList: Data
		do {
			propertyList = try PropertyListSerialization.data(
				fromPropertyList: exportedPreferences,
				format: .binary,
				options: 0
			)
		} catch {
			importExportLogger.error("Error Creating Property List: \(error.localizedDescription, privacy: .public)")
			return false
		}

		do {
			try propertyList.write(to: url, options: .atomic)
		} catch {
			importExportLogger.error("Write failed")
			return false
		}

		return true
	}
}
