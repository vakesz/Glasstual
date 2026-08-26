/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import AppKit
import CoreServices
import Foundation
import os

public typealias TPCThemeController = ThemeController

public extension Notification.Name {
	static let themeListDidChange = Notification.Name("TPCThemeControllerThemeListDidChangeNotification")
}

private enum ThemeNamePrefix {
	static let custom = "user"
	static let customComplete = "user:"
	static let bundled = "resource"
	static let bundledComplete = "resource:"
}

@MainActor
@objc(TPCThemeController)
@objcMembers
public final class ThemeController: NSObject {
	private static let logger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
		category: "ThemeController"
	)

	private var cachedThemeName = ""
	public private(set) var cacheToken = ""
	private var themeStorage: Theme!
	private var currentCopyOperation: ThemeCopyOperation?
	private var bundledThemes: [String: Theme] = [:]
	private var customThemes: [String: Theme] = [:]
	private var themeMonitor: XRFileSystemMonitor?

	override public init() {
		super.init()
		prepareInitialState()
	}

	deinit {
		themeMonitor?.stopMonitoring()
	}

	public nonisolated var theme: Theme! {
		MainActor.assumeIsolated { themeStorage }
	}

	public nonisolated var settings: ThemeSettings {
		MainActor.assumeIsolated { themeStorage.settings }
	}

	public nonisolated var storageLocation: TPCThemeStorageLocation {
		MainActor.assumeIsolated { themeStorage.storageLocation }
	}

	public nonisolated var name: String {
		MainActor.assumeIsolated { themeStorage.name }
	}

	public nonisolated var originalURL: URL {
		MainActor.assumeIsolated { themeStorage.originalURL }
	}

	public nonisolated var temporaryURL: URL {
		MainActor.assumeIsolated { themeStorage.temporaryURL }
	}

	public nonisolated var originalPath: String {
		originalURL.path
	}

	public nonisolated var temporaryPath: String {
		temporaryURL.path
	}

	@objc(isBundledTheme)
	public nonisolated var isBundledTheme: Bool {
		storageLocation == .bundle
	}

	private func prepareInitialState() {
		populateThemes()
		startMonitoringThemes()

		let center = NotificationCenter.default
		center.addObserver(
			self,
			selector: #selector(applicationAppearanceChanged(_:)),
			name: Notification.Name("TXApplicationAppearanceChangedNotification"),
			object: nil
		)
		center.addObserver(
			self,
			selector: #selector(themeIntegrityCompromised(_:)),
			name: .themeIntegrityCompromised,
			object: nil
		)
		center.addObserver(
			self,
			selector: #selector(themeWasDeleted(_:)),
			name: .themeWasDeleted,
			object: nil
		)
		center.addObserver(
			self,
			selector: #selector(themeWasModified(_:)),
			name: .themeWasModified,
			object: nil
		)
		center.addObserver(
			self,
			selector: #selector(themeVarietyChanged(_:)),
			name: .themeAppearanceChanged,
			object: nil
		)
		center.addObserver(
			self,
			selector: #selector(themeVarietyChanged(_:)),
			name: .themeVarietyChanged,
			object: nil
		)
	}

	public nonisolated func prepareForApplicationTermination() {
		MainActor.assumeIsolated {
			Self.logger.info("Preparing theme controller")
			NotificationCenter.default.removeObserver(self)
			stopMonitoringThemes()
			removeTemporaryCopyOfTheme()
		}
	}

	public func themeExists(_ themeName: String) -> Bool {
		theme(named: themeName, createIfNecessary: true)?.usable == true
	}

	@objc(themeNamed:)
	public func theme(named themeName: String) -> Theme? {
		theme(named: themeName, createIfNecessary: false)
	}

	@objc(themeNamed:createIfNecessary:)
	public func theme(named themeName: String, createIfNecessary: Bool) -> Theme? {
		guard let fileName = Self.extractThemeName(themeName) else {
			return nil
		}

		let location = Self.storageLocation(ofThemeWithName: themeName)
		guard location != .unknown,
		      let path = Self.pathOfTheme(withFilename: fileName, storageLocation: location)
		else {
			return nil
		}

		return theme(
			at: URL(fileURLWithPath: path, isDirectory: true),
			filename: fileName,
			storageLocation: location,
			createIfNecessary: createIfNecessary,
			skipFileExists: false
		).theme
	}

	private func theme(
		at url: URL,
		filename: String,
		storageLocation: TPCThemeStorageLocation,
		createIfNecessary: Bool,
		skipFileExists: Bool
	) -> (theme: Theme?, created: Bool) {
		precondition(url.isFileURL)
		precondition(filename.isEmpty == false)
		precondition(storageLocation != .unknown)

		if let existing = themeList(for: storageLocation)[filename] {
			return (existing, false)
		}

		guard createIfNecessary else {
			return (nil, false)
		}

		if skipFileExists == false, FileManager.default.directoryExists(at: url) == false {
			return (nil, false)
		}

		let newTheme = Theme(url: url, inStorageLocation: storageLocation)
		setTheme(newTheme, filename: filename, storageLocation: storageLocation)
		return (newTheme, true)
	}

	private func setTheme(
		_ theme: Theme?,
		filename: String,
		storageLocation: TPCThemeStorageLocation
	) {
		precondition(filename.isEmpty == false)
		precondition(storageLocation != .unknown)

		switch storageLocation {
		case .bundle:
			bundledThemes[filename] = theme
		case .custom:
			customThemes[filename] = theme
		case .unknown:
			break
		@unknown default:
			break
		}
	}

	@objc(pathOfThemeWithName:)
	public static func pathOfTheme(withName themeName: String) -> String? {
		pathOfTheme(withName: themeName, storageLocation: nil)
	}

	@objc(pathOfThemeWithName:storageLocation:)
	public static func pathOfTheme(
		withName themeName: String,
		storageLocation locationOut: UnsafeMutablePointer<TPCThemeStorageLocation>?
	) -> String? {
		let location = storageLocation(ofThemeWithName: themeName)
		locationOut?.pointee = location

		guard location != .unknown, let filename = extractThemeName(themeName) else {
			return nil
		}

		return pathOfTheme(withFilename: filename, storageLocation: location)
	}

	private static func pathOfTheme(
		withFilename filename: String,
		storageLocation: TPCThemeStorageLocation
	) -> String? {
		precondition(filename.isEmpty == false)
		precondition(storageLocation != .unknown)

		guard let basePath = path(of: storageLocation) else {
			return nil
		}

		let path = (basePath as NSString).appendingPathComponent(filename)
		return (path as NSString).standardizingPath
	}

	private static func path(of storageLocation: TPCThemeStorageLocation) -> String? {
		switch storageLocation {
		case .bundle:
			PathInfo.bundledThemes
		case .custom:
			PathInfo.customThemes
		case .unknown:
			nil
		@unknown default:
			nil
		}
	}

	private func themeList(for storageLocation: TPCThemeStorageLocation) -> [String: Theme] {
		switch storageLocation {
		case .bundle:
			bundledThemes
		case .custom:
			customThemes
		case .unknown:
			[:]
		@unknown default:
			[:]
		}
	}

	private func startMonitoringThemes() {
		guard let path = Self.path(of: .custom) else {
			return
		}

		let url = URL(fileURLWithPath: path, isDirectory: true)
		let monitor = XRFileSystemMonitor(
			fileURL: url,
			context: NSNumber(value: TPCThemeStorageLocation.custom.rawValue)
		) {
			[weak self] events in
			Task { @MainActor [weak self] in
				self?.react(toMonitoringEvents: events)
			}
		}
		monitor.startMonitoring(withLatency: 1)
		themeMonitor = monitor
	}

	private func stopMonitoringThemes() {
		themeMonitor?.stopMonitoring()
		themeMonitor = nil
	}

	private func react(toMonitoringEvents events: [XRFileSystemEvent]) {
		for event in events {
			react(toMonitoringEvent: event)
		}
	}

	private func react(toMonitoringEvent event: XRFileSystemEvent) {
		guard event.flags & UInt32(kFSEventStreamEventFlagItemIsDir) != 0,
		      let context = themeMonitor?.contextObject(for: event.url.deletingLastPathComponent()) as? NSNumber,
		      let location = TPCThemeStorageLocation(rawValue: context.uintValue)
		else {
			return
		}

		let url = event.url
		guard FileManager.default.fileExists(at: url) else {
			return
		}

		let result = theme(
			at: url,
			filename: url.lastPathComponent,
			storageLocation: location,
			createIfNecessary: true,
			skipFileExists: true
		)
		guard result.created else {
			return
		}

		Self.logger.debug(
			"Theme '\(String(describing: result.theme), privacy: .public)' named '\(url.lastPathComponent, privacy: .public)' created"
		)
		NotificationCenter.default.post(name: .themeListDidChange, object: self)
	}

	private func populateThemes() {
		populateThemes(from: .bundle)
		populateThemes(from: .custom)
	}

	private func populateThemes(from storageLocation: TPCThemeStorageLocation) {
		guard let path = Self.path(of: storageLocation) else {
			return
		}

		let url = URL(fileURLWithPath: path, isDirectory: true)
		do {
			let children = try FileManager.default.contentsOfDirectory(
				at: url,
				includingPropertiesForKeys: [.nameKey, .isDirectoryKey],
				options: [.skipsHiddenFiles, .skipsPackageDescendants]
			)

			for child in children {
				guard try child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
					continue
				}
				_ = theme(
					at: child,
					filename: child.lastPathComponent,
					storageLocation: storageLocation,
					createIfNecessary: true,
					skipFileExists: true
				)
			}
		} catch {
			Self.logger
				.error("Failed to list contents of theme folder: \(error.localizedDescription, privacy: .public)")
		}
	}

	@objc(enumerateAvailableThemesWithBlock:)
	public func enumerateAvailableThemes(
		_ enumerationBlock: (String, TPCThemeStorageLocation, Bool, UnsafeMutablePointer<ObjCBool>) -> Void
	) {
		var locationsByName: [String: [TPCThemeStorageLocation]] = [:]

		for location in [TPCThemeStorageLocation.bundle, .custom] {
			for (name, candidate) in themeList(for: location) where candidate.usable {
				locationsByName[name, default: []].append(location)
			}
		}

		var stop = ObjCBool(false)
		for themeName in locationsByName.keys.sorted() {
			let locations = locationsByName[themeName, default: []]
			for location in locations {
				enumerationBlock(themeName, location, locations.count > 1, &stop)
				if stop.boolValue {
					return
				}
			}
		}
	}

	@objc private func applicationAppearanceChanged(_: Notification) {
		theme?.updateAppearance()
	}

	@objc private func themeVarietyChanged(_: Notification) {
		updatePreferences()
	}

	@objc private func themeIntegrityCompromised(_ notification: Notification) {
		guard let affectedTheme = notification.object as? Theme, affectedTheme === theme else {
			return
		}

		guard resetPreferencesForActiveTheme() else {
			return
		}

		Self.logger.info("Reloading theme because it failed validation")
		TPCPreferences.performReloadAction(.style)
		NotificationCenter.default.post(name: .themeListDidChange, object: self)
		presentIntegrityCompromisedAlert()
	}

	@objc private func themeWasDeleted(_ notification: Notification) {
		guard let deletedTheme = notification.object as? Theme else {
			return
		}

		setTheme(nil, filename: deletedTheme.name, storageLocation: deletedTheme.storageLocation)

		guard deletedTheme === theme else {
			NotificationCenter.default.post(name: .themeListDidChange, object: self)
			return
		}

		guard resetPreferencesForActiveTheme() else {
			Self.logger.fault("Active theme deletion did not produce a recoverable preference")
			return
		}

		Self.logger.info("Reloading theme because it was deleted")
		TPCPreferences.performReloadAction(.style)
		NotificationCenter.default.post(name: .themeListDidChange, object: self)
	}

	@objc private func themeWasModified(_ notification: Notification) {
		guard let modifiedTheme = notification.object as? Theme,
		      modifiedTheme === theme,
		      TPCPreferences.automaticallyReloadCustomThemesWhenTheyChange()
		else {
			return
		}

		Self.logger.info("Reloading theme because it was modified")
		TPCPreferences.performReloadAction(.style)
	}

	public func load() {
		resetPreferencesForPreferredTheme()
		reload()
	}

	public func reload() {
		let themeName = TPCPreferences.themeName()
		guard let nextTheme = theme(named: themeName, createIfNecessary: true) else {
			preconditionFailure("Missing style resource files: \(themeName)")
		}

		guard nextTheme !== theme else {
			return
		}

		themeStorage = nextTheme
		cachedThemeName = themeName
		cacheToken = String(UInt32.random(in: 0 ..< 1_000_000))
		updatePreferences()
		createTemporaryCopyOfTheme()
		presentCompatibilityAlert()
		presentInvertSidebarColorsAlert()
	}

	private func updatePreferences() {
		guard let settings = theme?.settings else {
			return
		}

		TPCPreferences.setThemeChannelViewFontPreferenceUserConfigurable(settings.themeChannelViewFont == nil)
		TPCPreferences.setThemeNicknameFormatPreferenceUserConfigurable(settings.themeNicknameFormat?.isEmpty ?? true)
		TPCPreferences.setThemeTimestampFormatPreferenceUserConfigurable(settings.themeTimestampFormat?.isEmpty ?? true)
	}

	public func recreateTemporaryCopyOfThemeIfNecessary() {
		guard FileManager.default.fileExists(at: temporaryURL) == false else {
			return
		}
		createTemporaryCopyOfTheme()
	}

	private func removeTemporaryCopyOfTheme() {
		guard let theme, FileManager.default.fileExists(at: theme.temporaryURL) else {
			return
		}

		do {
			try FileManager.default.removeItem(at: theme.temporaryURL)
		} catch {
			Self.logger.error("Failed to remove temporary directory: \(error.localizedDescription, privacy: .public)")
		}
	}

	private func createTemporaryCopyOfTheme() {
		_ = FileManager.default.replaceItem(
			at: temporaryURL,
			withItemAt: originalURL,
			options: 1 << 1
		)
	}

	private func presentCompatibilityAlert() {
		guard settings.usesIncompatibleTemplateEngineVersion else {
			return
		}

		let suppressionKey = "incompatible_theme_dialog_\((cachedThemeName as NSString).hash)"
		_ = TDCAlert.alert(
			withMessage: LocalizedKey("Prompts[76t-pn]"),
			title: LocalizedKey("Prompts[py0-cr]", name),
			defaultButton: LocalizedKey("Prompts[2a3-5s]"),
			alternateButton: LocalizedKey("Prompts[c7s-dq]"),
			suppressionKey: suppressionKey,
			suppressionText: nil
		) { response, _, _ in
			guard response == .default else {
				return
			}
			NSObject.masterController().menuController?.showStylePreferences(nil)
		}
	}

	private func presentInvertSidebarColorsAlert() {
		guard settings.invertSidebarColors,
		      SharedApplication.sharedAppearance().properties.isDarkAppearance == false
		else {
			return
		}

		let suppressionKey = "theme_appearance_dialog_\((cachedThemeName as NSString).hash)"
		_ = TDCAlert.alert(
			withMessage: LocalizedKey("Prompts[193-6o]"),
			title: LocalizedKey("Prompts[ezn-rm]", name),
			defaultButton: LocalizedKey("Prompts[hf0-w3]"),
			alternateButton: LocalizedKey("Prompts[hv0-79]"),
			suppressionKey: suppressionKey,
			suppressionText: nil
		) { response, _, _ in
			guard response != .default else {
				return
			}
			TPCPreferences.setAppearance(.dark)
			TPCPreferences.performReloadAction(.appearance)
		}
	}

	private func presentIntegrityCompromisedAlert() {
		_ = TDCAlert.alert(
			withMessage: LocalizedKey("Prompts[3wd-gj]"),
			title: LocalizedKey("Prompts[fjw-hj]", name),
			defaultButton: LocalizedKey("Prompts[c4z-2b]"),
			alternateButton: LocalizedKey("Prompts[c7s-dq]")
		) { response, _, _ in
			guard response == .default else {
				return
			}
			NSObject.masterController().menuController?.showStylePreferences(nil)
		}
	}

	private func resetPreferencesForPreferredTheme() {
		_ = resetPreferences(forThemeNamed: TPCPreferences.themeName())
	}

	private func resetPreferencesForActiveTheme() -> Bool {
		resetPreferences(forThemeNamed: cachedThemeName)
	}

	private func resetPreferences(forThemeNamed themeName: String) -> Bool {
		let result = validate(themeName: themeName)
		guard result.isValid == false else {
			return false
		}

		if let fontName = result.suggestedFontName {
			TPCPreferences.setThemeChannelViewFontName(fontName)
		}
		if let themeName = result.suggestedThemeName {
			TPCPreferences.setThemeName(themeName)
		}
		return true
	}

	private func validate(themeName validatedTheme: String) -> ThemeValidationResult {
		var result = ThemeValidationResult()
		let fontName = TPCPreferences.themeChannelViewFontName()
		let fontIsAvailable = NSFont(name: fontName, size: 9) != nil || NSFontManager.shared.availableFonts.contains {
			$0.compare(fontName, options: .caseInsensitive) == .orderedSame
		}
		if fontIsAvailable == false {
			result.suggestedFontName = TPCPreferences.themeChannelViewFontNameDefault()
		}

		let themeName = Self.extractThemeName(validatedTheme)
		let themeSource = Self.extractThemeSource(validatedTheme)
		Self.logger.info(
			"Performing validation on theme named '\(themeName ?? "(invalid)", privacy: .public)' with source '\(themeSource ?? "(none)", privacy: .public)'"
		)

		if themeSource == nil || themeSource == ThemeNamePrefix.bundled {
			let remappedTheme = remappedThemeName(validatedTheme)
			if let remappedTheme {
				result.suggestedThemeName = remappedTheme
			}

			let recoverableTheme = remappedTheme ?? validatedTheme
			if themeExists(recoverableTheme) == false {
				result.suggestedThemeName = TPCPreferences.themeNameDefault()
			}
		} else if themeSource == ThemeNamePrefix.custom, themeExists(validatedTheme) == false {
			let bundledTheme = themeName.flatMap {
				Self.buildFilename($0, for: .bundle)
			}
			result.suggestedThemeName = bundledTheme.flatMap { themeExists($0) ? $0 : nil }
				?? TPCPreferences.themeNameDefault()
		}

		return result
	}

	private func remappedThemeName(_ themeName: String) -> String? {
		ResourceManager.dictionary(
			fromResources: "StaticStore",
			key: "TPCThemeController Remapped Themes"
		)?[themeName] as? String
	}

	@objc(buildFilename:forStorageLocation:)
	public static func buildFilename(
		_ name: String,
		for storageLocation: TPCThemeStorageLocation
	) -> String? {
		guard name.isEmpty == false else {
			return nil
		}

		return switch storageLocation {
		case .bundle:
			ThemeNamePrefix.bundledComplete + name
		case .custom:
			ThemeNamePrefix.customComplete + name
		case .unknown:
			nil
		@unknown default:
			nil
		}
	}

	@objc(descriptionForStorageLocation:)
	public static func description(for storageLocation: TPCThemeStorageLocation) -> String? {
		switch storageLocation {
		case .bundle:
			LocalizedKey("BasicLanguage[7lm-bq]")
		case .custom:
			LocalizedKey("BasicLanguage[bm2-4p]")
		case .unknown:
			nil
		@unknown default:
			nil
		}
	}

	@objc(extractThemeSource:)
	public static func extractThemeSource(_ source: String) -> String? {
		guard source.hasPrefix(ThemeNamePrefix.customComplete) ||
			source.hasPrefix(ThemeNamePrefix.bundledComplete)
		else {
			return nil
		}
		return source.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init)
	}

	@objc(extractThemeName:)
	public static func extractThemeName(_ source: String) -> String? {
		guard source.hasPrefix(ThemeNamePrefix.customComplete) ||
			source.hasPrefix(ThemeNamePrefix.bundledComplete),
			let separator = source.firstIndex(of: ":")
		else {
			return nil
		}

		let name = String(source[source.index(after: separator)...])
		return name.isEmpty ? nil : name
	}

	@objc(storageLocationOfThemeWithName:)
	public static func storageLocation(ofThemeWithName themeName: String) -> TPCThemeStorageLocation {
		if themeName.hasPrefix(ThemeNamePrefix.customComplete) {
			return .custom
		}
		if themeName.hasPrefix(ThemeNamePrefix.bundledComplete) {
			return .bundle
		}
		return .unknown
	}

	@objc(copyActiveThemeToDestinationLocation:reloadOnCopy:openOnCopy:)
	public func copyActiveTheme(
		to destinationLocation: TPCThemeStorageLocation,
		reloadOnCopy: Bool,
		openOnCopy: Bool
	) {
		precondition(currentCopyOperation == nil, "A theme copy operation is already in progress")

		guard storageLocation != destinationLocation else {
			Self.logger.error("Tried to copy the active theme to its current storage location")
			return
		}
		guard destinationLocation != .bundle else {
			Self.logger.error("Tried to copy the active theme into the application bundle")
			return
		}

		let operation = ThemeCopyOperation(
			themeController: self,
			themeName: name,
			sourcePath: originalPath,
			destinationLocation: destinationLocation,
			reloadWhenCopied: reloadOnCopy,
			openWhenCopied: openOnCopy
		)
		currentCopyOperation = operation
		operation.begin()
	}

	fileprivate func copyActiveThemeOperationCompleted() {
		currentCopyOperation = nil
	}
}

private struct ThemeValidationResult {
	var suggestedFontName: String?
	var suggestedThemeName: String?

	var isValid: Bool {
		suggestedFontName == nil && suggestedThemeName == nil
	}
}

@MainActor
private final class ThemeCopyOperation {
	private weak var themeController: ThemeController?
	private let themeName: String
	private let sourcePath: String
	private let destinationLocation: TPCThemeStorageLocation
	private let reloadWhenCopied: Bool
	private let openWhenCopied: Bool
	private var progressIndicator: ProgressIndicatorSheet?

	init(
		themeController: ThemeController,
		themeName: String,
		sourcePath: String,
		destinationLocation: TPCThemeStorageLocation,
		reloadWhenCopied: Bool,
		openWhenCopied: Bool
	) {
		self.themeController = themeController
		self.themeName = themeName
		self.sourcePath = sourcePath
		self.destinationLocation = destinationLocation
		self.reloadWhenCopied = reloadWhenCopied
		self.openWhenCopied = openWhenCopied
	}

	func begin() {
		let indicator = ProgressIndicatorSheet(window: NSApp.keyWindow)
		progressIndicator = indicator
		indicator.start()

		let sourceURL = URL(fileURLWithPath: sourcePath, isDirectory: true)
		guard let customThemesURL = PathInfo.customThemesURL else {
			invalidate()
			return
		}
		let destinationURL = customThemesURL.appendingPathComponent(themeName, isDirectory: true)

		Task.detached { [weak self] in
			let succeeded = FileManager.default.replaceItem(
				at: destinationURL,
				withItemAt: sourceURL,
				options: (1 << 5) | (1 << 1)
			)
			await self?.finishCopy(succeeded: succeeded, destinationURL: destinationURL)
		}
	}

	private func finishCopy(succeeded: Bool, destinationURL: URL) {
		guard succeeded else {
			invalidate()
			return
		}

		if openWhenCopied {
			NSWorkspace.shared.open(destinationURL)
		}
		if reloadWhenCopied,
		   let newThemeName = ThemeController.buildFilename(themeName, for: destinationLocation)
		{
			TPCPreferences.setThemeName(newThemeName)
			TPCPreferences.performReloadAction(.style)
		}
		invalidate()
	}

	private func invalidate() {
		progressIndicator?.stop()
		progressIndicator = nil
		themeController?.copyActiveThemeOperationCompleted()
	}
}
