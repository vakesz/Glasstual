/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Theme loading", .serialized)
struct TPCThemeMigrationTests {
	@Test("A theme reads its resources and its global settings")
	func globalThemeLoadsResourcesAndSettings() throws {
		let fixture = try makeThemeFixture(settings: [
			"Appearance": "dark",
			"Force Invert Sidebars": true,
			"Indentation Offset": 12.5,
			"Key-value Store Name": "Migration Tests",
			"Nickname Format": "<%@>",
			"Nickname Color Style": "HSL-light",
			"Template Engine Versions": ["default": TPCThemeSettingsNewestTemplateEngineVersion],
		])
		defer { try? FileManager.default.removeItem(at: fixture) }

		let theme = TPCTheme(url: fixture, inStorageLocation: .custom)

		#expect(theme.usable)
		#expect(theme.name == fixture.lastPathComponent)
		#expect(theme.originalURL == fixture.standardizedFileURL)
		#expect(theme.appearance == .dark)
		#expect(theme.cssFiles.map(\.lastPathComponent) == ["design.css"])
		#expect(theme.jsFiles.map(\.lastPathComponent) == ["scripts.js"])
		#expect(theme.settings.appearance == .dark)
		#expect(theme.settings.invertSidebarColors)
		#expect(theme.settings.indentationOffset == 12.5)
		#expect(theme.settings.nicknameColorStyle == .light)
		#expect(theme.settings.templateEngineVersion == UInt(TPCThemeSettingsNewestTemplateEngineVersion))
		#expect(theme.settings.usesIncompatibleTemplateEngineVersion == false)
	}

	@Test("A variety overrides the global settings and appends its own resources")
	func varietyOverridesGlobalSettingsAndResourceOrderIsStable() throws {
		let fixture = try makeThemeFixture(settings: [
			"Appearance": "light",
			"Nickname Format": "global",
			"Template Engine Versions": ["default": TPCThemeSettingsNewestTemplateEngineVersion],
		])
		let varietyURL = fixture
			.appendingPathComponent("Varieties", isDirectory: true)
			.appendingPathComponent("Dark", isDirectory: true)
		try FileManager.default.createDirectory(at: varietyURL, withIntermediateDirectories: true)
		try Data("variety".utf8).write(to: varietyURL.appendingPathComponent("design.css"))
		try writePropertyList([
			"Appearance": "dark",
			"Nickname Format": "variety",
		], to: varietyURL.appendingPathComponent("settings.plist"))
		defer { try? FileManager.default.removeItem(at: fixture) }

		let theme = TPCTheme(url: fixture, inStorageLocation: .custom)

		#expect(theme.usable)
		#expect(theme.cssFiles.map(\.lastPathComponent) == ["design.css", "design.css"])
		#expect(theme.jsFiles.map(\.lastPathComponent) == ["scripts.js"])
		#expect(theme.settings.themeNicknameFormat == "variety")
	}

	@Test("An unsupported template version falls back to the newest one and says so")
	func invalidTemplateVersionFallsBackAndIsReported() throws {
		let fixture = try makeThemeFixture(settings: [
			"Indentation Offset": -1,
			"Template Engine Versions": ["default": 99],
		])
		defer { try? FileManager.default.removeItem(at: fixture) }

		let settings = TPCTheme(url: fixture, inStorageLocation: .custom).settings

		#expect(settings.indentationOffset == Double(TPCThemeSettingsDisabledIndentationOffset))
		#expect(settings.templateEngineVersion == UInt(TPCThemeSettingsNewestTemplateEngineVersion))
		#expect(settings.usesIncompatibleTemplateEngineVersion)
	}

	@Test("A canonical theme name is split into its source, name and storage location")
	func themeControllerParsesCanonicalThemeNames() {
		#expect(TPCThemeController.extractThemeSource("resource:Default") == "resource")
		#expect(TPCThemeController.extractThemeName("resource:Default") == "Default")
		#expect(TPCThemeController.storageLocation(ofThemeWithName: "resource:Default") == .bundle)

		#expect(TPCThemeController.extractThemeSource("user:Solarized") == "user")
		#expect(TPCThemeController.extractThemeName("user:Solarized") == "Solarized")
		#expect(TPCThemeController.storageLocation(ofThemeWithName: "user:Solarized") == .custom)
	}

	@Test("A malformed theme name resolves to nothing")
	func themeControllerRejectsMalformedThemeNames() {
		#expect(TPCThemeController.extractThemeSource("Default") == nil)
		#expect(TPCThemeController.extractThemeName("resource:") == nil)
		#expect(TPCThemeController.extractThemeName("user:") == nil)
		#expect(TPCThemeController.storageLocation(ofThemeWithName: "Default") == .unknown)
	}

	@Test("A canonical theme name is built back from its parts")
	func themeControllerBuildsCanonicalThemeNames() {
		#expect(TPCThemeController.buildFilename("Default", for: .bundle) == "resource:Default")
		#expect(TPCThemeController.buildFilename("Solarized", for: .custom) == "user:Solarized")
		#expect(TPCThemeController.buildFilename("Default", for: .unknown) == nil)
		#expect(TPCThemeController.buildFilename("", for: .bundle) == nil)
	}

	@Test("The shared controller has published a theme")
	func publishedThemeIsPopulated() {
		let controller = SharedApplication.sharedThemeController()

		#expect(controller.theme != nil)
		#expect(controller.name.isEmpty == false)
		#expect(controller.originalURL.isFileURL)
		#expect(controller.temporaryURL.isFileURL)
		#expect(controller.storageLocation != .unknown)
		_ = controller.settings
	}

	private func makeThemeFixture(settings: [String: Any]) throws -> URL {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("GlasstualThemeTests-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		try Data("global".utf8).write(to: directory.appendingPathComponent("design.css"))
		try Data("global".utf8).write(to: directory.appendingPathComponent("scripts.js"))
		try writePropertyList(settings, to: directory.appendingPathComponent("settings.plist"))
		return directory
	}

	private func writePropertyList(_ propertyList: Any, to url: URL) throws {
		let data = try PropertyListSerialization.data(
			fromPropertyList: propertyList,
			format: .xml,
			options: 0
		)
		try data.write(to: url)
	}
}
