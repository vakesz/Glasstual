/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
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
import CocoaExtensions
import CoreServices
import Foundation
import os
import Synchronization

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

/** The parts of the active theme that code outside the main actor reads.

 `Theme` and `ThemeSettings` are main-actor classes, so they cannot be handed
 out from a background thread. Message rendering only needs these few values,
 so the controller republishes them as a value type whenever the theme changes. */
public struct ThemeSnapshot: Sendable {
	/** Safe to carry here because `Theme` is main-actor isolated (hence `Sendable`)
	 and the members the renderer reaches for are `nonisolated`. */
	public let theme: Theme
	public let storageLocation: TPCThemeStorageLocation
	public let name: String
	public let originalURL: URL
	public let temporaryURL: URL
	public let nicknameColorStyle: TPCThemeSettingsNicknameColorStyle
	public let timestampFormat: String?
	/** Where the theme's templates are read from. A render job builds its own
	 repositories out of these, so no compiled template is ever shared. */
	public let templateSources: ThemeTemplateSources
}

private struct PublishedTheme {
	let theme: Theme
	let settings: ThemeSettings
	let storageLocation: TPCThemeStorageLocation
	let name: String
	let originalURL: URL
	let temporaryURL: URL
}

@MainActor
public final class ThemeController: NSObject {
	private static let logger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
		category: "ThemeController"
	)

	private var cachedThemeName = ""
	public private(set) var cacheToken = ""
	private var publishedTheme: PublishedTheme?

	/** Static because the controller is a singleton and the readers are outside the
	 main actor, where the main-actor accessor is unreachable. */
	private nonisolated static let snapshotStorage = Mutex<ThemeSnapshot?>(nil) // nonisolated: let
	private var currentCopyOperation: ThemeCopyOperation?
	private var bundledThemes: [String: Theme] = [:]
	private var customThemes: [String: Theme] = [:]
	private var themeMonitorTask: Task<Void, Never>?
	/// The theme-integrity and theme-change notifications this controller answers.
	private let notifications = NotificationSubscriptions()

	override public init() {
		super.init()
		prepareInitialState()
	}

	isolated deinit {
		themeMonitorTask?.cancel()
		notifications.cancelAll()
	}

	/** The active theme's off-main-actor readable values. Nil until `reload()`. */
	public nonisolated static var activeSnapshot: ThemeSnapshot? { // nonisolated: pure
		snapshotStorage.withLock { $0 }
	}

	public var theme: Theme! {
		publishedTheme?.theme
	}

	public var settings: ThemeSettings! {
		publishedTheme?.settings
	}

	public var storageLocation: TPCThemeStorageLocation {
		publishedTheme?.storageLocation ?? .bundle
	}

	public var name: String {
		publishedTheme?.name ?? ""
	}

	public var originalURL: URL! {
		publishedTheme?.originalURL
	}

	public var temporaryURL: URL! {
		publishedTheme?.temporaryURL
	}

	public var originalPath: String {
		publishedTheme?.originalURL.path ?? ""
	}

	public var temporaryPath: String {
		publishedTheme?.temporaryURL.path ?? ""
	}

	public var isBundledTheme: Bool {
		storageLocation == .bundle
	}

	private func prepareInitialState() {
		populateThemes()
		startMonitoringThemes()

		notifications
			.observe(Notification.Name("TXApplicationAppearanceChangedNotification")) { [weak self] notification in
				self?.applicationAppearanceChanged(notification)
			}
		notifications.observe(.themeIntegrityCompromised) { [weak self] notification in
			self?.themeIntegrityCompromised(notification)
		}
		notifications.observe(.themeWasDeleted) { [weak self] notification in
			self?.themeWasDeleted(notification)
		}
		notifications.observe(.themeWasModified) { [weak self] notification in
			self?.themeWasModified(notification)
		}
		notifications.observe(.themeAppearanceChanged) { [weak self] notification in
			self?.themeVarietyChanged(notification)
		}
		notifications.observe(.themeVarietyChanged) { [weak self] notification in
			self?.themeVarietyChanged(notification)
		}
	}

	public func prepareForApplicationTermination() {
		Self.logger.info("Preparing theme controller")
		stopMonitoringThemes()
		removeTemporaryCopyOfTheme()
	}

	public func themeExists(_ themeName: String) -> Bool {
		theme(named: themeName, createIfNecessary: true)?.usable == true
	}

	public func theme(named themeName: String) -> Theme? {
		theme(named: themeName, createIfNecessary: false)
	}

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

	public static func pathOfTheme(withName themeName: String) -> String? {
		pathOfTheme(withName: themeName, storageLocation: nil)
	}

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
		themeMonitorTask = Task { [weak self] in
			for await events in XRFileSystemMonitor.events(for: url, latency: 1) {
				guard let self else { return }
				react(toMonitoringEvents: events)
			}
		}
	}

	private func stopMonitoringThemes() {
		themeMonitorTask?.cancel()
		themeMonitorTask = nil
	}

	private func react(toMonitoringEvents events: [XRFileSystemEvent]) {
		for event in events {
			react(toMonitoringEvent: event)
		}
	}

	private func react(toMonitoringEvent event: XRFileSystemEvent) {
		guard event.flags & UInt32(kFSEventStreamEventFlagItemIsDir) != 0 else {
			return
		}

		/* Only the custom folder is watched, so every event that arrives here
		 belongs to a custom theme. */
		let location = TPCThemeStorageLocation.custom

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

	private func applicationAppearanceChanged(_: Notification) {
		theme?.updateAppearance()
	}

	private func themeVarietyChanged(_: Notification) {
		updatePreferences()
	}

	private func themeIntegrityCompromised(_ notification: Notification) {
		guard let affectedTheme = notification.object as? Theme, affectedTheme === theme else {
			return
		}

		guard resetPreferencesForActiveTheme() else {
			return
		}

		Self.logger.info("Reloading theme because it failed validation")
		TextualPreferences.performReloadAction(.style)
		NotificationCenter.default.post(name: .themeListDidChange, object: self)
		presentIntegrityCompromisedAlert()
	}

	private func themeWasDeleted(_ notification: Notification) {
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
		TextualPreferences.performReloadAction(.style)
		NotificationCenter.default.post(name: .themeListDidChange, object: self)
	}

	private func themeWasModified(_ notification: Notification) {
		guard let modifiedTheme = notification.object as? Theme,
		      modifiedTheme === theme,
		      TextualPreferences.automaticallyReloadCustomThemesWhenTheyChange()
		else {
			return
		}

		Self.logger.info("Reloading theme because it was modified")
		TextualPreferences.performReloadAction(.style)
	}

	public func load() {
		resetPreferencesForPreferredTheme()
		reload()
	}

	public func reload() {
		let themeName = TextualPreferences.themeName()
		guard let nextTheme = theme(named: themeName, createIfNecessary: true) else {
			/* A missing style is recoverable: keep showing whatever is already
			 loaded rather than killing the app mid-session. */
			Self.logger.error("Missing style resource files: \(themeName, privacy: .public)")
			return
		}

		guard nextTheme !== theme else {
			return
		}

		publishedTheme = PublishedTheme(
			theme: nextTheme,
			settings: nextTheme.settings,
			storageLocation: nextTheme.storageLocation,
			name: nextTheme.name,
			originalURL: nextTheme.originalURL,
			temporaryURL: nextTheme.temporaryURL
		)
		publishSnapshot(for: nextTheme)
		cachedThemeName = themeName
		cacheToken = String(UInt32.random(in: 0 ..< 1_000_000))
		updatePreferences()
		createTemporaryCopyOfTheme()
		presentCompatibilityAlert()
		presentInvertSidebarColorsAlert()
	}

	private func publishSnapshot(for theme: Theme) {
		let snapshot = ThemeSnapshot(
			theme: theme,
			storageLocation: theme.storageLocation,
			name: theme.name,
			originalURL: theme.originalURL,
			temporaryURL: theme.temporaryURL,
			nicknameColorStyle: theme.settings.nicknameColorStyle,
			timestampFormat: theme.settings.themeTimestampFormat,
			templateSources: theme.templateSources
		)

		Self.snapshotStorage.withLock { $0 = snapshot }
	}

	private func updatePreferences() {
		guard let settings = theme?.settings else {
			return
		}

		TextualPreferences.setThemeChannelViewFontPreferenceUserConfigurable(settings.themeChannelViewFont == nil)
		TextualPreferences
			.setThemeNicknameFormatPreferenceUserConfigurable(settings.themeNicknameFormat?.isEmpty ?? true)
		TextualPreferences
			.setThemeTimestampFormatPreferenceUserConfigurable(settings.themeTimestampFormat?.isEmpty ?? true)
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
			options: .removeIfExists
		)
	}

	private func presentCompatibilityAlert() {
		guard settings.usesIncompatibleTemplateEngineVersion else {
			return
		}

		// Keyed by the style name. `NSString.hash` is not a documented stable
		// identity across releases, so a change to it silently resurrected the
		// alert and orphaned the key the user had already suppressed.
		let suppressionKey = "incompatible_theme_dialog_\(cachedThemeName)"
		TDCAlert.alert(
			withMessage: PromptStrings.Theme.incompatibleBody,
			title: PromptStrings.Theme.incompatibleTitle(name: name),
			defaultButton: PromptStrings.Theme.chooseDifferentStyleButtonTitle,
			alternateButton: PromptStrings.Action.confirmation,
			suppressionKey: suppressionKey,
			suppressionText: nil
		) { outcome in
			guard outcome.response == .default else {
				return
			}
			AppController.shared.menuController?.showStylePreferences(nil)
		}
	}

	private func presentInvertSidebarColorsAlert() {
		guard settings.invertSidebarColors,
		      SharedApplication.sharedAppearance().properties.isDarkAppearance == false
		else {
			return
		}

		let suppressionKey = "theme_appearance_dialog_\(cachedThemeName)"
		TDCAlert.alert(
			withMessage: PromptStrings.Theme.wantsDarkAppearanceBody,
			title: PromptStrings.Theme.wantsDarkAppearanceTitle(name: name),
			defaultButton: PromptStrings.Theme.keepLightButtonTitle,
			alternateButton: PromptStrings.Theme.switchToDarkButtonTitle,
			suppressionKey: suppressionKey,
			suppressionText: nil
		) { outcome in
			guard outcome.response != .default else {
				return
			}
			TextualPreferences.setAppearance(.dark)
			TextualPreferences.performReloadAction(.appearance)
		}
	}

	private func presentIntegrityCompromisedAlert() {
		TDCAlert.alert(
			withMessage: PromptStrings.Theme.modifiedBody,
			title: PromptStrings.Theme.modifiedTitle(name: name),
			defaultButton: PromptStrings.Theme.chooseDifferentStyleButtonTitle,
			alternateButton: PromptStrings.Action.confirmation
		) { outcome in
			guard outcome.response == .default else {
				return
			}
			AppController.shared.menuController?.showStylePreferences(nil)
		}
	}

	private func resetPreferencesForPreferredTheme() {
		_ = resetPreferences(forThemeNamed: TextualPreferences.themeName())
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
			TextualPreferences.setThemeChannelViewFontName(fontName)
		}
		if let themeName = result.suggestedThemeName {
			TextualPreferences.setThemeName(themeName)
		}
		return true
	}
}

public extension ThemeController {
	private func validate(themeName validatedTheme: String) -> ThemeValidationResult {
		var result = ThemeValidationResult()
		let fontName = TextualPreferences.themeChannelViewFontName()
		let fontIsAvailable = NSFont(name: fontName, size: 9) != nil || NSFontManager.shared.availableFonts.contains {
			$0.compare(fontName, options: .caseInsensitive) == .orderedSame
		}
		if fontIsAvailable == false {
			result.suggestedFontName = TextualPreferences.themeChannelViewFontNameDefault()
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
				result.suggestedThemeName = TextualPreferences.themeNameDefault()
			}
		} else if themeSource == ThemeNamePrefix.custom, themeExists(validatedTheme) == false {
			let bundledTheme = themeName.flatMap {
				Self.buildFilename($0, for: .bundle)
			}
			result.suggestedThemeName = bundledTheme.flatMap { themeExists($0) ? $0 : nil }
				?? TextualPreferences.themeNameDefault()
		}

		return result
	}

	private func remappedThemeName(_ themeName: String) -> String? {
		ResourceManager.dictionary(
			fromResources: "StaticStore",
			key: "TPCThemeController Remapped Themes"
		)?[themeName] as? String
	}

	static func buildFilename(
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

	static func description(for storageLocation: TPCThemeStorageLocation) -> String? {
		switch storageLocation {
		case .bundle:
			ApplicationStrings.builtInTheme
		case .custom:
			ApplicationStrings.customTheme
		case .unknown:
			nil
		@unknown default:
			nil
		}
	}

	static func extractThemeSource(_ source: String) -> String? {
		guard source.hasPrefix(ThemeNamePrefix.customComplete) ||
			source.hasPrefix(ThemeNamePrefix.bundledComplete)
		else {
			return nil
		}
		return source.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init)
	}

	static func extractThemeName(_ source: String) -> String? {
		guard source.hasPrefix(ThemeNamePrefix.customComplete) ||
			source.hasPrefix(ThemeNamePrefix.bundledComplete),
			let separator = source.firstIndex(of: ":")
		else {
			return nil
		}

		let name = String(source[source.index(after: separator)...])
		return name.isEmpty ? nil : name
	}

	static func storageLocation(ofThemeWithName themeName: String) -> TPCThemeStorageLocation {
		if themeName.hasPrefix(ThemeNamePrefix.customComplete) {
			return .custom
		}
		if themeName.hasPrefix(ThemeNamePrefix.bundledComplete) {
			return .bundle
		}
		return .unknown
	}

	func copyActiveTheme(
		to destinationLocation: TPCThemeStorageLocation,
		reloadOnCopy: Bool,
		openOnCopy: Bool
	) {
		/* The copy runs asynchronously, so a second click on "Create a copy of this
		 style" lands here while the first is still in flight. Ignore it. */
		guard currentCopyOperation == nil else {
			Self.logger.info("Ignoring theme copy request: one is already in progress")
			return
		}

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
				options: [.moveToTrash, .removeIfExists]
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
			TextualPreferences.setThemeName(newThemeName)
			TextualPreferences.performReloadAction(.style)
		}
		invalidate()
	}

	private func invalidate() {
		progressIndicator?.stop()
		progressIndicator = nil
		themeController?.copyActiveThemeOperationCompleted()
	}
}
