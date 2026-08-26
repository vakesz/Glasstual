/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
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

public extension Notification.Name {
	static let themeIntegrityCompromised = Notification.Name("TPCThemeIntegrityCompromisedNotification")
	static let themeIntegrityRestored = Notification.Name("TPCThemeIntegrityRestoredNotification")
	static let themeAppearanceChanged = Notification.Name("TPCThemeAppearanceChangedNotification")
	static let themeVarietyChanged = Notification.Name("TPCThemeVarietyChangedNotification")
	static let themeWasModified = Notification.Name("TPCThemeWasModifiedNotification")
	static let themeWasDeleted = Notification.Name("TPCThemeWasDeletedNotification")
}

public typealias TPCTheme = Theme
public typealias TPCThemeSettings = ThemeSettings

private enum VarietyChoice {
	case unchanged
	case unavailable
	case changed
}

private struct MonitoringResult: OptionSet {
	let rawValue: UInt

	static let reloadableFileModified = Self(rawValue: 1 << 0)
	static let criticalFileDeleted = Self(rawValue: 1 << 1)
	static let varietyCreated = Self(rawValue: 1 << 2)
	static let varietyDeleted = Self(rawValue: 1 << 3)
	static let themeDeleted = Self(rawValue: 1 << 4)
}

@MainActor
@objc(TPCTheme)
@objcMembers
public final class Theme: NSObject {
	private nonisolated static let logger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
		category: "Theme"
	)

	public private(set) var name: String
	public private(set) var originalURL: URL
	public private(set) var temporaryURL: URL
	public private(set) var storageLocation: TPCThemeStorageLocation
	public private(set) var usable = false

	fileprivate var globalVariety: ThemeVariety!
	fileprivate var variety: ThemeVariety?
	private var varieties: [ThemeVariety] = []
	private nonisolated(unsafe) var templateCache = NSCache<NSString, GRMustacheTemplate>()
	private nonisolated(unsafe) var defaultTemplateRepository: GRMustacheTemplateRepository!
	private var fileSystemMonitor: XRFileSystemMonitor?

	public private(set) var cssFiles: [URL] = []
	public private(set) var jsFiles: [URL] = []
	public private(set) var temporaryCSSFiles: [URL] = []
	public private(set) var temporaryJSFiles: [URL] = []
	public private(set) nonisolated(unsafe) var templateRepositories: [GRMustacheTemplateRepository] = []
	private var settingsStorage: ThemeSettings!
	public var settings: ThemeSettings {
		settingsStorage
	}

	@available(*, unavailable)
	override public init() {
		fatalError("Use init(url:inStorageLocation:)")
	}

	@objc(initWithURL:inStorageLocation:)
	public init(url: URL, inStorageLocation storageLocation: TPCThemeStorageLocation) {
		precondition(url.isFileURL)
		precondition(storageLocation != .unknown)

		let standardizedURL = url.standardizedFileURL
		name = standardizedURL.lastPathComponent
		originalURL = standardizedURL
		temporaryURL = standardizedURL
		self.storageLocation = storageLocation
		super.init()
		loadTheme()
	}

	deinit {
		fileSystemMonitor?.stopMonitoring()
	}

	public var appearance: TPCThemeAppearanceType {
		variety?.appearance ?? .default
	}

	public var cssFilePaths: [String] {
		cssFiles.map(\.path)
	}

	public var jsFilePaths: [String] {
		jsFiles.map(\.path)
	}

	public var temporaryCSSFilePaths: [String] {
		temporaryCSSFiles.map(\.path)
	}

	public var temporaryJSFilePaths: [String] {
		temporaryJSFiles.map(\.path)
	}

	public var applicationTemplateRepositoryPath: String {
		applicationTemplateRepositoryURL.path
	}

	public func updateAppearance() {
		_ = chooseBestVariety()
	}

	@objc(templateWithLineType:)
	public nonisolated func template(withLineType type: TVCLogLineType) -> GRMustacheTemplate? {
		guard let typeString = TVCLogLine.string(for: type) else {
			return nil
		}

		if let template = loadTemplate(named: "Line Types/\(typeString)", logErrors: false) {
			return template
		}

		guard let fallbackName = Self.templateLineTypes[typeString] else {
			return nil
		}

		return loadTemplate(named: fallbackName, logErrors: true)
	}

	@objc(templateWithName:)
	public nonisolated func template(withName name: String) -> GRMustacheTemplate? {
		loadTemplate(named: name, logErrors: true)
	}

	private func loadTheme() {
		assignTemporaryURL()
		globalVariety = ThemeVariety(url: originalURL, isGlobalVariety: true)
		loadVarieties()
		usable = chooseBestVariety() == .changed
		startMonitoring()
	}

	private func loadVarieties() {
		let directoryURL = varietiesURL
		guard FileManager.default.fileExists(at: directoryURL) else {
			varieties = []
			return
		}

		do {
			let urls = try FileManager.default.contentsOfDirectory(
				at: directoryURL,
				includingPropertiesForKeys: [.isDirectoryKey],
				options: .skipsHiddenFiles
			)
			varieties = urls.compactMap { url in
				guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
					return nil
				}
				return ThemeVariety(url: url)
			}
		} catch {
			Self.logger.error(
				"Failed to list contents of Varieties folder: \(error.localizedDescription, privacy: .public)"
			)
			varieties = []
		}
	}

	private var varietiesURL: URL {
		originalURL.appendingPathComponent("Varieties", isDirectory: true)
	}

	private func assignTemporaryURL() {
		let sourceURL = PathInfo.applicationCachesURL ?? FileManager.default.temporaryDirectory
		temporaryURL = sourceURL
			.appendingPathComponent("Cached-Style-Resources", isDirectory: true)
			.standardizedFileURL
	}

	// MARK: Monitoring

	private func startMonitoring() {
		let monitor = XRFileSystemMonitor(fileURL: originalURL) { [weak self] events in
			Task { @MainActor [weak self] in
				self?.react(to: events)
			}
		}
		monitor.startMonitoring(withLatency: 5)
		fileSystemMonitor = monitor
	}

	private func stopMonitoring() {
		fileSystemMonitor?.stopMonitoring()
		fileSystemMonitor = nil
	}

	private func react(to events: [XRFileSystemEvent]) {
		let result = events.reduce(into: MonitoringResult()) { partialResult, event in
			partialResult.formUnion(monitoringResult(for: event.url, flags: event.flags))
		}
		concludeMonitoring(with: result)
	}

	private func concludeMonitoring(with result: MonitoringResult) {
		if result.contains(.themeDeleted) {
			reactToDeletion()
			return
		}

		let requiresIntegrityCheck = result.contains(.criticalFileDeleted) ||
			result.contains(.varietyCreated) ||
			result.contains(.varietyDeleted)
		if requiresIntegrityCheck {
			_ = verifyIntegrity()
		} else if result.contains(.reloadableFileModified) {
			NotificationCenter.default.post(name: .themeWasModified, object: self)
		}
	}

	private func monitoringResult(
		for url: URL,
		flags: FSEventStreamEventFlags
	) -> MonitoringResult {
		if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsFile) != 0 {
			return monitoringResultForFile(at: url)
		}
		if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir) != 0 {
			return monitoringResultForDirectory(at: url)
		}
		return []
	}

	private func monitoringResultForFile(at url: URL) -> MonitoringResult {
		guard let changedVariety = variety(at: url.deletingLastPathComponent()) else {
			return []
		}

		var result: MonitoringResult = []
		if changedVariety.reevaluateFile(at: url) {
			result.insert(.criticalFileDeleted)
		}

		guard changedVariety === variety || changedVariety === globalVariety else {
			return result
		}

		if url.pathExtension == "css" || url.pathExtension == "js" {
			result.insert(.reloadableFileModified)
		}
		return result
	}

	private func monitoringResultForDirectory(at url: URL) -> MonitoringResult {
		if directoriesAreEqual(url, originalURL) {
			return FileManager.default.directoryExists(at: url) ? [] : .themeDeleted
		}

		guard directoriesAreEqual(url.deletingLastPathComponent(), varietiesURL) else {
			return []
		}
		return monitoringResultForVarietyDirectory(at: url)
	}

	private func monitoringResultForVarietyDirectory(at url: URL) -> MonitoringResult {
		let wasDeleted = !FileManager.default.directoryExists(at: url)
		if let existingVariety = variety(at: url) {
			varieties.removeAll { $0 === existingVariety }
		} else if wasDeleted {
			return []
		}

		if !wasDeleted {
			varieties.append(ThemeVariety(url: url))
		}
		return wasDeleted ? .varietyDeleted : .varietyCreated
	}

	private func reactToDeletion() {
		stopMonitoring()
		changeVariety(to: nil)
		usable = false
		NotificationCenter.default.post(name: .themeWasDeleted, object: self)
	}

	private func directoriesAreEqual(_ lhs: URL, _ rhs: URL) -> Bool {
		lhs.standardizedFileURL.path == rhs.standardizedFileURL.path
	}

	private func variety(at url: URL) -> ThemeVariety? {
		if directoriesAreEqual(url, globalVariety.url) {
			return globalVariety
		}
		return varieties.first { directoriesAreEqual(url, $0.url) }
	}

	// MARK: Integrity and Variety Selection

	@discardableResult
	private func verifyIntegrity() -> Bool {
		let choice = chooseBestVariety()
		if usable {
			switch choice {
			case .unchanged:
				return false
			case .unavailable:
				usable = false
				changeVariety(to: nil)
				NotificationCenter.default.post(name: .themeIntegrityCompromised, object: self)
			case .changed:
				break
			}
		} else {
			guard choice != .unavailable else {
				return false
			}
			usable = true
			NotificationCenter.default.post(name: .themeIntegrityRestored, object: self)
		}
		return true
	}

	private func chooseBestVariety() -> VarietyChoice {
		guard let bestVariety else {
			return .unavailable
		}
		guard variety !== bestVariety else {
			return .unchanged
		}
		changeVariety(to: bestVariety)
		return .changed
	}

	private var bestVariety: ThemeVariety? {
		let wantsDarkAppearance = TXSharedApplication.sharedAppearance().properties.isDarkAppearance
		let globalHasCSS = globalVariety.cssFile != nil
		let globalHasJS = globalVariety.jsFile != nil
		var best: ThemeVariety?

		for candidate in varieties {
			let matchesAppearance =
				(candidate.appearance == .light && !wantsDarkAppearance) ||
				(candidate.appearance == .dark && wantsDarkAppearance)
			guard matchesAppearance || best == nil else {
				continue
			}
			guard globalHasCSS || candidate.cssFile != nil,
			      globalHasJS || candidate.jsFile != nil
			else {
				continue
			}
			best = candidate
		}

		if best == nil, globalHasCSS, globalHasJS {
			best = globalVariety
		}
		return best
	}

	private func changeVariety(to newVariety: ThemeVariety?) {
		let previousVariety = variety
		templateCache.removeAllObjects()
		variety = newVariety
		combineFiles()
		settingsStorage = ThemeSettings(theme: self)
		assignDefaultTemplateRepository()

		guard let previousVariety, let newVariety, usable else {
			return
		}
		let notification: Notification.Name = previousVariety.appearance == newVariety.appearance
			? .themeVarietyChanged
			: .themeAppearanceChanged
		NotificationCenter.default.post(name: notification, object: self)
	}

	private func combineFiles() {
		guard let variety else {
			cssFiles = []
			jsFiles = []
			temporaryCSSFiles = []
			temporaryJSFiles = []
			templateRepositories = []
			return
		}

		let selectedVarieties = variety.isGlobalVariety ? [globalVariety!] : [globalVariety!, variety]
		cssFiles = selectedVarieties.compactMap(\.cssFile)
		jsFiles = selectedVarieties.compactMap(\.jsFile)
		temporaryCSSFiles = cssFiles.map(remapToTemporaryURL)
		temporaryJSFiles = jsFiles.map(remapToTemporaryURL)

		let repositoryVarieties = variety.isGlobalVariety ? [globalVariety!] : [variety, globalVariety!]
		templateRepositories = repositoryVarieties.compactMap(\.templateRepository)
	}

	private func remapToTemporaryURL(_ url: URL) -> URL {
		let originalPath = originalURL.standardizedFileURL.path
		let path = url.standardizedFileURL.path
		guard path == originalPath || path.hasPrefix(originalPath + "/") else {
			return url
		}
		let suffix = String(path.dropFirst(originalPath.count).trimmingPrefix("/"))
		return temporaryURL.appendingPathComponent(suffix).standardizedFileURL
	}

	// MARK: Templates

	private nonisolated static let templateLineTypes: [String: String] =
		TPCResourceManager.dictionary(fromResources: "TemplateLineTypes") as? [String: String] ?? [:]

	private var applicationTemplateRepositoryURL: URL {
		PathInfo.applicationResourcesURL
			.appendingPathComponent("Style Default Templates", isDirectory: true)
			.appendingPathComponent("Version \(settings.templateEngineVersion)", isDirectory: true)
	}

	private func assignDefaultTemplateRepository() {
		defaultTemplateRepository = GRMustacheTemplateRepository(baseURL: applicationTemplateRepositoryURL)
	}

	private nonisolated func loadTemplate(named name: String, logErrors: Bool) -> GRMustacheTemplate? {
		if let cached = templateCache.object(forKey: name as NSString) {
			return cached
		}

		let repositories = templateRepositories + [defaultTemplateRepository].compactMap(\.self)
		for repository in repositories {
			do {
				let template = try repository.templateNamed(name)
				templateCache.setObject(template, forKey: name as NSString)
				return template
			} catch let error as NSError {
				let templateNotFoundErrorCode = 1
				if error.code == templateNotFoundErrorCode || error
					.code == NSFileReadNoSuchFileError
				{
					continue
				}
				if logErrors {
					Self.logger.error(
						"Failed to load template '\(name, privacy: .public)': \(error.localizedDescription, privacy: .public)"
					)
				}
			}
		}
		return nil
	}
}

@MainActor
private final class ThemeVariety {
	let url: URL
	let isGlobalVariety: Bool
	private(set) var appearance: TPCThemeAppearanceType = .default
	private(set) var cssFile: URL?
	private(set) var jsFile: URL?
	private(set) var settings: [String: Any] = [:]
	private(set) var templateRepository: GRMustacheTemplateRepository?

	init(url: URL, isGlobalVariety: Bool = false) {
		self.url = url.standardizedFileURL
		self.isGlobalVariety = isGlobalVariety
		load()
	}

	func reevaluateFile(at fileURL: URL) -> Bool {
		switch fileURL.lastPathComponent {
		case "design.css":
			updateFileReference(&cssFile, for: fileURL)
		case "scripts.js":
			updateFileReference(&jsFile, for: fileURL)
		default:
			false
		}
	}

	private func load() {
		let cssURL = url.appendingPathComponent("design.css")
		if FileManager.default.fileExists(at: cssURL) {
			cssFile = cssURL
		}

		let jsURL = url.appendingPathComponent("scripts.js")
		if FileManager.default.fileExists(at: jsURL) {
			jsFile = jsURL
		}

		templateRepository = GRMustacheTemplateRepository(baseURL: Self.templatesURL(for: url))
		settings = Self.loadSettings(from: Self.settingsURL(for: url))

		switch settings["Appearance"] as? String {
		case "dark": appearance = .dark
		case "light": appearance = .light
		default: appearance = .default
		}
	}

	private func updateFileReference(_ reference: inout URL?, for fileURL: URL) -> Bool {
		if FileManager.default.fileExists(at: fileURL) {
			guard reference == nil else { return false }
			reference = fileURL
			return true
		}

		guard reference != nil else { return false }
		reference = nil
		return true
	}

	private static func loadSettings(from url: URL) -> [String: Any] {
		guard let data = try? Data(contentsOf: url),
		      let propertyList = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
		      let settings = propertyList as? [String: Any]
		else {
			return [:]
		}
		return settings
	}

	private static func settingsURL(for url: URL) -> URL {
		let legacyURL = url.appendingPathComponent("Data/Settings/styleSettings.plist")
		return FileManager.default.fileExists(at: legacyURL)
			? legacyURL
			: url.appendingPathComponent("settings.plist")
	}

	private static func templatesURL(for url: URL) -> URL {
		let legacyURL = url.appendingPathComponent("Data/Templates", isDirectory: true)
		return FileManager.default.fileExists(at: legacyURL)
			? legacyURL
			: url.appendingPathComponent("Templates", isDirectory: true)
	}
}

@MainActor
@objc(TPCThemeSettings)
@objcMembers
public final class ThemeSettings: NSObject {
	private static let templateEngineVersionRange = UInt(TPCThemeSettingsNewestTemplateEngineVersion) ... UInt(
		TPCThemeSettingsNewestTemplateEngineVersion
	)
	private static let missingStoreNameError = """
	Empty key-value store name in settings.plist — Set the key "Key-value Store Name" in settings.plist as a string. \
	The current style name is the recommended value.
	"""

	public private(set) var invertSidebarColors = false
	public private(set) var js_postHandleEventNotifications = false
	public private(set) var js_postAppearanceChangesNotification = false
	public private(set) var js_postPreferencesDidChangesNotifications = false
	public private(set) var usesIncompatibleTemplateEngineVersion = true
	public private(set) var appearance: TPCThemeAppearanceType = .default
	public private(set) var themeChannelViewFont: NSFont?
	public private(set) var themeNicknameFormat: String?
	public private(set) nonisolated(unsafe) var themeTimestampFormat: String?
	public private(set) var settingsKeyValueStoreName: String?
	public private(set) var channelViewOverlayColor: NSColor?
	public private(set) var underlyingWindowColor: NSColor?
	public private(set) var indentationOffset = Double(TPCThemeSettingsDisabledIndentationOffset)
	public private(set) nonisolated(unsafe) var nicknameColorStyle: TPCThemeSettingsNicknameColorStyle = .default
	public private(set) var templateEngineVersion = UInt(TPCThemeSettingsNewestTemplateEngineVersion)

	@available(*, unavailable)
	override public init() {
		fatalError("Theme settings are created by Theme")
	}

	fileprivate init(theme: Theme) {
		super.init()
		loadSettings(for: theme)
	}

	public var underlyingWindowColorIsDark: Bool {
		guard let convertedColor = underlyingWindowColor?.usingColorSpace(.deviceRGB) else {
			return false
		}
		return convertedColor.brightnessComponent < 0.5
	}

	@objc(styleSettingsRetrieveValueForKey:error:)
	public func styleSettingsRetrieveValue(
		forKey key: String,
		error resultError: AutoreleasingUnsafeMutablePointer<NSString?>?
	) -> Any? {
		guard !key.isEmpty else {
			resultError?.pointee = "Empty key value"
			return nil
		}
		guard let storeKey = keyValueStoreName else {
			resultError?.pointee = Self.missingStoreNameError as NSString
			return nil
		}
		return TextualUserDefaults.shared().dictionary(forKey: storeKey)?[key]
	}

	@objc(styleSettingsSetValue:forKey:error:)
	public func styleSettingsSetValue(
		_ value: Any?,
		forKey key: String,
		error resultError: AutoreleasingUnsafeMutablePointer<NSString?>?
	) -> Bool {
		guard !key.isEmpty else {
			resultError?.pointee = "Empty key value"
			return false
		}
		guard let storeKey = keyValueStoreName else {
			resultError?.pointee = Self.missingStoreNameError as NSString
			return false
		}

		let shouldRemove = value == nil || value is NSNull
		var settings = TextualUserDefaults.shared().dictionary(forKey: storeKey) ?? [:]
		if shouldRemove {
			guard !settings.isEmpty else { return true }
			settings.removeValue(forKey: key)
		} else {
			settings[key] = value
		}
		TextualUserDefaults.shared().set(settings, forKey: storeKey)
		return true
	}

	private var keyValueStoreName: String? {
		guard let storeName = settingsKeyValueStoreName, !storeName.isEmpty else {
			return nil
		}
		return "Internal Theme Settings Key-value Store -> \(storeName)"
	}

	private func loadSettings(for theme: Theme) {
		var values = theme.globalVariety.settings
		if let variety = theme.variety, !variety.isGlobalVariety {
			values.merge(variety.settings) { _, varietyValue in varietyValue }
		}

		themeChannelViewFont = Self.font(forKey: "Override Channel Font", in: values)
		themeNicknameFormat = Self.nonemptyString(forKey: "Nickname Format", in: values)
		themeTimestampFormat = Self.nonemptyString(forKey: "Timestamp Format", in: values)
		invertSidebarColors = values["Force Invert Sidebars"] as? Bool ?? false
		channelViewOverlayColor = Self.color(forKey: "Channel View Overlay Color", in: values)
		underlyingWindowColor = Self.color(forKey: "Underlying Window Color", in: values)
		settingsKeyValueStoreName = Self.nonemptyString(forKey: "Key-value Store Name", in: values)
		js_postHandleEventNotifications = values["Post Glasstual.handleEvent() Notifications"] as? Bool ?? false
		js_postAppearanceChangesNotification =
			values["Post Glasstual.appearanceDidChange() Notifications"] as? Bool ?? false
		js_postPreferencesDidChangesNotifications =
			values["Post Glasstual.preferencesDidChange() Notifications"] as? Bool ?? false

		if let offset = (values["Indentation Offset"] as? NSNumber)?.doubleValue, offset >= 0 {
			indentationOffset = offset
		}

		let varietyAppearance = theme.variety?.appearance ?? .default
		appearance = varietyAppearance
		nicknameColorStyle = Self.nicknameColorStyle(
			from: values["Nickname Color Style"],
			appearance: varietyAppearance,
			windowIsDark: underlyingWindowColorIsDark
		)

		let versions = values["Template Engine Versions"] as? [String: Any] ?? [:]
		let applicationVersion = ApplicationInfo.applicationVersionShort()
		if let version = Self.compatibleTemplateVersion(versions[applicationVersion]) ??
			Self.compatibleTemplateVersion(versions["default"])
		{
			templateEngineVersion = version
			usesIncompatibleTemplateEngineVersion = false
		}
	}

	private static func nonemptyString(forKey key: String, in values: [String: Any]) -> String? {
		guard let value = values[key] as? String, !value.isEmpty else {
			return nil
		}
		return value
	}

	private static func color(forKey key: String, in values: [String: Any]) -> NSColor? {
		guard let value = values[key] as? String else { return nil }
		let hexadecimalValue = value.hasPrefix("#") ? String(value.dropFirst()) : value
		guard !hexadecimalValue.isEmpty,
		      hexadecimalValue.count <= 8,
		      hexadecimalValue.count.isMultiple(of: 2),
		      var color = UInt64(hexadecimalValue, radix: 16)
		else {
			return nil
		}

		if hexadecimalValue.count < 8 {
			color = color << 8 | 0xFF
		}
		return NSColor(
			deviceRed: CGFloat((color & 0xFF00_0000) >> 24) / 0xFF,
			green: CGFloat((color & 0x00FF_0000) >> 16) / 0xFF,
			blue: CGFloat((color & 0x0000_FF00) >> 8) / 0xFF,
			alpha: CGFloat(color & 0x0000_00FF) / 0xFF
		)
	}

	private static func font(forKey key: String, in values: [String: Any]) -> NSFont? {
		guard let fontValues = values[key] as? [String: Any],
		      let fontName = fontValues["Font Name"] as? String,
		      let fontSize = (fontValues["Font Size"] as? NSNumber)?.doubleValue,
		      fontSize >= 5
		else {
			return nil
		}
		return NSFont(name: fontName, size: fontSize)
	}

	private static func nicknameColorStyle(
		from value: Any?,
		appearance: TPCThemeAppearanceType,
		windowIsDark: Bool
	) -> TPCThemeSettingsNicknameColorStyle {
		if let value = value as? String {
			if value == "HSL-light" {
				return .light
			}
			if value == "HSL-dark" {
				return .dark
			}
		}
		switch appearance {
		case .light: return .light
		case .dark: return .dark
		default: return windowIsDark ? .dark : .light
		}
	}

	private static func compatibleTemplateVersion(_ value: Any?) -> UInt? {
		guard let number = value as? NSNumber else { return nil }
		let version = number.uintValue
		return templateEngineVersionRange.contains(version) ? version : nil
	}
}
