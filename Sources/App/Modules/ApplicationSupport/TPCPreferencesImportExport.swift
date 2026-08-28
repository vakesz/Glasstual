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
import CocoaExtensions
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
	public static func `import`(in window: NSWindow) {
		TDCAlert.alertSheet(
			with: window,
			body: PromptStrings.ConfigurationTransfer.importBody,
			title: PromptStrings.ConfigurationTransfer.importTitle,
			defaultButton: PromptStrings.Action.chooseFile,
			alternateButton: PromptStrings.Action.cancel,
			otherButton: nil,
			completionBlock: { buttonClicked, _, _ in
				importPreflight(buttonClicked, in: window)
			}
		)
	}

	private static func importPreflight(_ buttonPressed: TDCAlertResponse, in window: NSWindow) {
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
	public static func importPostflightBackupPreferences() -> Bool {
		let backupPath = NSHomeDirectory().appending(
			"/Glasstual-importBackup-\(UUID().uuidString).plist"
		)

		return exportPostflight(forPath: backupPath, filterJunk: false)
	}

	@objc(importPostflight:)
	public static func importPostflight(_ pathURL: URL) {
		DispatchQueue.main.async {
			importPostflightOnMain(pathURL)
		}
	}

	private static func importPostflightOnMain(_ pathURL: URL) {
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

		let mainWindow = AppController.shared.mainWindow!
		mainWindow.loadingScreen?.showProgressView(withReason: MainWindowStrings.Loading.preferences)

		AppController.shared.world.isImportingConfiguration = true
		mainWindow.serverList?.beginUpdates()

		importContentsOfDictionary(dictionary, reloadPreferences: false)

		// The import runs to completion synchronously, so the cleanup follows it
		// directly rather than after a fixed delay that was either too long or,
		// for a large configuration, too short.
		importPostflightCleanup(Array(dictionary.keys))
	}

	@objc(importContentsOfDictionary:)
	public static func importContentsOfDictionary(_ dictionary: [String: Any]) {
		importContentsOfDictionary(dictionary, reloadPreferences: true)
	}

	@objc(importContentsOfDictionary:reloadPreferences:)
	public static func importContentsOfDictionary(_ dictionary: [String: Any], reloadPreferences: Bool) {
		for (key, object) in dictionary {
			guard isKeyNameSupposedToBeIgnored(key) == false else {
				continue
			}

			importValue(object, withKey: key)
		}

		if reloadPreferences {
			TextualPreferences.performReloadAction(forKeys: Array(dictionary.keys))
		}
	}

	@objc(import:withKey:)
	public static func importValue(_ object: Any, withKey key: String) {
		if key == TPCPreferencesThemeNameDefaultsKey {
			guard let value = object as? String else {
				return
			}

			TextualPreferences.setThemeNameWithExistenceCheck(value)
		} else if key == TPCPreferencesThemeFontNameDefaultsKey {
			guard let value = object as? String else {
				return
			}

			TextualPreferences.setThemeChannelViewFontNameWithExistenceCheck(value)
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
			TextualUserDefaults.shared().migrateObject(object, forKey: key)
		}
	}

	@objc(importClientConfiguration:)
	public static func importClientConfiguration(_ config: [String: Any]) {
		guard let clientConfig = PropertyListModel.decode(ClientConfig.self, from: config) else {
			return
		}

		let world = AppController.shared.world!

		if let client = world.findClient(withId: clientConfig.uniqueIdentifier) {
			client.updateConfig(clientConfig)
		} else {
			_ = world.createClient(with: clientConfig, reload: true)
		}
	}

	@objc(importPostflightCleanup:)
	public static func importPostflightCleanup(_ changedKeys: [String]) {
		TextualPreferences.performReloadAction(forKeys: changedKeys)

		let mainWindow = AppController.shared.mainWindow!
		mainWindow.serverList?.endUpdates()
		AppController.shared.world.isImportingConfiguration = false
		_ = mainWindow.reloadLoadingScreen()
	}

	@objc(isKeyNameSupposedToBeIgnored:)
	public static func isKeyNameSupposedToBeIgnored(_ key: String) -> Bool {
		TextualUserDefaults.keyIsExcludedFromExportImport(key)
	}

	@objc(exportedPreferencesDictionary)
	public static func exportedPreferencesDictionary() -> [String: Any] {
		exportedPreferencesDictionary(true, filterDefaults: true)
	}

	@objc(exportedPreferencesDictionary:)
	public static func exportedPreferencesDictionary(_ filterJunk: Bool) -> [String: Any] {
		exportedPreferencesDictionary(filterJunk, filterDefaults: filterJunk)
	}

	@objc(exportedPreferencesDictionary:filterDefaults:)
	public static func exportedPreferencesDictionary(_ filterJunk: Bool, filterDefaults: Bool) -> [String: Any] {
		var finalDictionary = TextualUserDefaults.shared().dictionaryRepresentation()

		var keysToStrip: [String] = []

		let argumentsDomain = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
		keysToStrip.append(contentsOf: argumentsDomain.keys)

		if filterJunk {
			let globalsDomain = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain) ?? [:]
			keysToStrip.append(contentsOf: globalsDomain.keys)
		}

		if filterDefaults {
			// Filter by value, not by name. Stripping every key that merely has
			// a registered default drops the settings the user actually chose,
			// which is most of them.
			let registeredDefaults = TextualPreferences.defaultPreferences()
			keysToStrip.append(contentsOf: finalDictionary.keys.filter { key in
				guard let registered = registeredDefaults[key] else {
					return false
				}

				return valueMatchesDefault(finalDictionary[key], registered)
			})
		}

		for key in keysToStrip {
			finalDictionary.removeValue(forKey: key)
		}

		if filterJunk {
			let ignoredKeys = finalDictionary.keys.filter { key in
				isKeyNameSupposedToBeIgnored(key)
			}

			for key in ignoredKeys {
				finalDictionary.removeValue(forKey: key)
			}
		}

		return finalDictionary
	}

	static func valueMatchesDefault(_ value: Any?, _ registeredDefault: Any) -> Bool {
		guard let value else {
			return false
		}

		return (value as AnyObject).isEqual(registeredDefault)
	}

	@objc(exportInWindow:)
	public static func export(in window: NSWindow) {
		TDCAlert.alertSheet(
			with: window,
			body: PromptStrings.ConfigurationTransfer.exportBody,
			title: PromptStrings.ConfigurationTransfer.exportTitle,
			defaultButton: PromptStrings.ConfigurationTransfer.exportButtonTitle,
			alternateButton: PromptStrings.Action.cancel,
			otherButton: nil,
			completionBlock: { buttonClicked, _, _ in
				exportPreflight(buttonClicked, in: window)
			}
		)
	}

	private static func exportPreflight(_ buttonPressed: TDCAlertResponse, in window: NSWindow) {
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
	public static func exportPostflight(forPath path: String) -> Bool {
		exportPostflight(forPath: path, filterJunk: true)
	}

	@objc(exportPostflightForURL:)
	public static func exportPostflight(for url: URL) -> Bool {
		exportPostflight(for: url, filterJunk: true)
	}

	@objc(exportPostflightForPath:filterJunk:)
	public static func exportPostflight(forPath path: String, filterJunk: Bool) -> Bool {
		exportPostflight(for: URL(fileURLWithPath: path), filterJunk: filterJunk)
	}

	@objc(exportPostflightForURL:filterJunk:)
	public static func exportPostflight(for url: URL, filterJunk: Bool) -> Bool {
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
