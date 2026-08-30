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

private let importExportLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "PreferencesImportExport"
)

@MainActor
public final class PreferencesImportExport: NSObject {
	public static func `import`(in window: NSWindow) {
		TDCAlert.alertSheet(
			with: window,
			body: PromptStrings.ConfigurationTransfer.importBody,
			title: PromptStrings.ConfigurationTransfer.importTitle,
			defaultButton: PromptStrings.Action.chooseFile,
			alternateButton: PromptStrings.Action.cancel,
			otherButton: nil,
			completionBlock: { outcome in
				importPreflight(outcome.response, in: window)
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

	public static func importPostflightBackupPreferences() -> Bool {
		let backupPath = NSHomeDirectory().appending(
			"/Glasstual-importBackup-\(UUID().uuidString).plist"
		)

		return exportPostflight(forPath: backupPath, filterJunk: false)
	}

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

		/* `Any` is what the serializer returns; it is narrowed here so the
		 import works in typed values from this point on. */
		guard let dictionary = [String: PropertyListValue](propertyList: propertyList) else {
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

	public static func importContentsOfDictionary(_ dictionary: [String: PropertyListValue]) {
		importContentsOfDictionary(dictionary, reloadPreferences: true)
	}

	public static func importContentsOfDictionary(
		_ dictionary: [String: PropertyListValue],
		reloadPreferences: Bool
	) {
		for (key, value) in dictionary {
			guard isKeyNameSupposedToBeIgnored(key) == false else {
				continue
			}

			importValue(value, withKey: key)
		}

		if reloadPreferences {
			TextualPreferences.performReloadAction(forKeys: Array(dictionary.keys))
		}
	}

	/** An imported plist is untrusted input: it can carry a string where an
	 integer belongs, or a dictionary where a boolean does. The declaration for
	 the key decides what the value has to be, coercing the representations that
	 are genuinely the same value and rejecting the rest with a log line. A key
	 the catalogue does not know is passed through, because its shape belongs to
	 whichever subsystem wrote it. */
	static func validatedValue(_ value: PropertyListValue, forKey key: String) -> PropertyListValue? {
		guard let declaration = Preferences.key(named: key) else {
			return value
		}

		guard let coerced = declaration.coerce(value) else {
			importExportLogger.error("Import rejected a value of the wrong type for \(key, privacy: .public)")
			return nil
		}

		return coerced
	}

	public static func importValue(_ value: PropertyListValue, withKey key: String) {
		guard let value = validatedValue(value, forKey: key) else {
			return
		}

		if key == TPCPreferencesThemeNameDefaultsKey {
			guard let name = value.string else {
				return
			}

			TextualPreferences.setThemeNameWithExistenceCheck(name)
		} else if key == TPCPreferencesThemeFontNameDefaultsKey {
			guard let name = value.string else {
				return
			}

			TextualPreferences.setThemeChannelViewFontNameWithExistenceCheck(name)
		} else if key == IRCWorldClientListDefaultsKey {
			for config in value.array?.compactMap(\.dictionary) ?? [] {
				importClientConfiguration(config)
			}
		} else {
			TextualUserDefaults.container.migrateObject(value.propertyListObject, forKey: key)
		}
	}

	public static func importClientConfiguration(_ config: [String: PropertyListValue]) {
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

	public static func importPostflightCleanup(_ changedKeys: [String]) {
		TextualPreferences.performReloadAction(forKeys: changedKeys)

		let mainWindow = AppController.shared.mainWindow!
		mainWindow.serverList?.endUpdates()
		AppController.shared.world.isImportingConfiguration = false
		_ = mainWindow.reloadLoadingScreen()
	}

	public static func isKeyNameSupposedToBeIgnored(_ key: String) -> Bool {
		TextualUserDefaults.keyIsExcludedFromExportImport(key)
	}

	public static func exportedPreferencesDictionary() -> [String: PropertyListValue] {
		exportedPreferencesDictionary(true, filterDefaults: true)
	}

	public static func exportedPreferencesDictionary(_ filterJunk: Bool) -> [String: PropertyListValue] {
		exportedPreferencesDictionary(filterJunk, filterDefaults: filterJunk)
	}

	/** The exportable set is the values the user actually wrote — the persistent
	 domains of the two stores the declarations name — rather than the whole
	 search list, which is where the arguments and global domains used to leak in
	 and have to be subtracted again by name. */
	private static func writtenValues() -> [String: PropertyListValue] {
		let defaults = TextualUserDefaults.container
		var written = [String: PropertyListValue](
			propertyList: defaults.persistentDomain(forName: defaults.suiteName) ?? [:]
		) ?? [:]

		if let bundleIdentifier = Bundle.main.bundleIdentifier,
		   let standard = [String: PropertyListValue](
		   	propertyList: UserDefaults.standard.persistentDomain(forName: bundleIdentifier) ?? [:]
		   )
		{
			// The handful of declarations stored in the application's own domain
			// rather than the container are exported alongside the rest.
			for (key, value) in standard where Preferences.storage(for: key) == .standard {
				written[key] = value
			}
		}

		return written
	}

	public static func exportedPreferencesDictionary(
		_ filterJunk: Bool,
		filterDefaults: Bool
	) -> [String: PropertyListValue] {
		let standardRegistrations = [String: PropertyListValue](
			propertyList: UserDefaults.standard.volatileDomain(forName: UserDefaults.registrationDomain)
		) ?? [:]
		let registeredDefaults = TextualPreferences.defaultPreferences()
			.merging(standardRegistrations) { current, _ in current }

		var exported: [String: PropertyListValue] = [:]

		for (key, value) in writtenValues() {
			if filterJunk, isKeyNameSupposedToBeIgnored(key) {
				continue
			}

			// Filter by value, not by name. Stripping every key that merely has
			// a registered default drops the settings the user actually chose,
			// which is most of them.
			if filterDefaults, let registered = registeredDefaults[key],
			   valueMatchesDefault(value, registered)
			{
				continue
			}

			exported[key] = value
		}

		return exported
	}

	/** `NSNumber` equality is what has always decided this, and it is looser
	 than the value's own: a flag a plist editor wrote as `1` still counts as
	 the default it was written from. */
	static func valueMatchesDefault(_ value: PropertyListValue?, _ registeredDefault: PropertyListValue) -> Bool {
		guard let value else {
			return false
		}

		return (value.propertyListObject as AnyObject).isEqual(registeredDefault.propertyListObject)
	}

	public static func export(in window: NSWindow) {
		TDCAlert.alertSheet(
			with: window,
			body: PromptStrings.ConfigurationTransfer.exportBody,
			title: PromptStrings.ConfigurationTransfer.exportTitle,
			defaultButton: PromptStrings.ConfigurationTransfer.exportButtonTitle,
			alternateButton: PromptStrings.Action.cancel,
			otherButton: nil,
			completionBlock: { outcome in
				exportPreflight(outcome.response, in: window)
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

	public static func exportPostflight(forPath path: String) -> Bool {
		exportPostflight(forPath: path, filterJunk: true)
	}

	public static func exportPostflight(for url: URL) -> Bool {
		exportPostflight(for: url, filterJunk: true)
	}

	public static func exportPostflight(forPath path: String, filterJunk: Bool) -> Bool {
		exportPostflight(for: URL(fileURLWithPath: path), filterJunk: filterJunk)
	}

	public static func exportPostflight(for url: URL, filterJunk: Bool) -> Bool {
		let exportedPreferences = exportedPreferencesDictionary(filterJunk)

		let propertyList: Data
		do {
			propertyList = try PropertyListSerialization.data(
				fromPropertyList: exportedPreferences.propertyListObject,
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
