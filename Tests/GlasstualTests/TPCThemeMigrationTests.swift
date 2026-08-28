/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import XCTest

@MainActor
final class TPCThemeMigrationTests: XCTestCase {
	func testGlobalThemeLoadsResourcesAndSettings() throws {
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

		XCTAssertTrue(theme.usable)
		XCTAssertEqual(theme.name, fixture.lastPathComponent)
		XCTAssertEqual(theme.originalURL, fixture.standardizedFileURL)
		XCTAssertEqual(theme.appearance, .dark)
		XCTAssertEqual(theme.cssFiles.map(\.lastPathComponent), ["design.css"])
		XCTAssertEqual(theme.jsFiles.map(\.lastPathComponent), ["scripts.js"])
		XCTAssertEqual(theme.settings.appearance, .dark)
		XCTAssertTrue(theme.settings.invertSidebarColors)
		XCTAssertEqual(theme.settings.indentationOffset, 12.5)
		XCTAssertEqual(theme.settings.nicknameColorStyle, .light)
		XCTAssertEqual(theme.settings.templateEngineVersion, UInt(TPCThemeSettingsNewestTemplateEngineVersion))
		XCTAssertFalse(theme.settings.usesIncompatibleTemplateEngineVersion)
	}

	func testVarietyOverridesGlobalSettingsAndResourceOrderIsStable() throws {
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

		XCTAssertTrue(theme.usable)
		XCTAssertEqual(theme.cssFiles.map(\.lastPathComponent), ["design.css", "design.css"])
		XCTAssertEqual(theme.jsFiles.map(\.lastPathComponent), ["scripts.js"])
		XCTAssertEqual(theme.settings.themeNicknameFormat, "variety")
	}

	func testInvalidTemplateVersionFallsBackAndIsReported() throws {
		let fixture = try makeThemeFixture(settings: [
			"Indentation Offset": -1,
			"Template Engine Versions": ["default": 99],
		])
		defer { try? FileManager.default.removeItem(at: fixture) }

		let settings = try XCTUnwrap(TPCTheme(url: fixture, inStorageLocation: .custom).settings)

		XCTAssertEqual(settings.indentationOffset, Double(TPCThemeSettingsDisabledIndentationOffset))
		XCTAssertEqual(settings.templateEngineVersion, UInt(TPCThemeSettingsNewestTemplateEngineVersion))
		XCTAssertTrue(settings.usesIncompatibleTemplateEngineVersion)
	}

	func testThemeControllerParsesCanonicalThemeNames() {
		XCTAssertEqual(TPCThemeController.extractThemeSource("resource:Default"), "resource")
		XCTAssertEqual(TPCThemeController.extractThemeName("resource:Default"), "Default")
		XCTAssertEqual(TPCThemeController.storageLocation(ofThemeWithName: "resource:Default"), .bundle)

		XCTAssertEqual(TPCThemeController.extractThemeSource("user:Solarized"), "user")
		XCTAssertEqual(TPCThemeController.extractThemeName("user:Solarized"), "Solarized")
		XCTAssertEqual(TPCThemeController.storageLocation(ofThemeWithName: "user:Solarized"), .custom)
	}

	func testThemeControllerRejectsMalformedThemeNames() {
		XCTAssertNil(TPCThemeController.extractThemeSource("Default"))
		XCTAssertNil(TPCThemeController.extractThemeName("resource:"))
		XCTAssertNil(TPCThemeController.extractThemeName("user:"))
		XCTAssertEqual(TPCThemeController.storageLocation(ofThemeWithName: "Default"), .unknown)
	}

	func testThemeControllerBuildsCanonicalThemeNames() {
		XCTAssertEqual(TPCThemeController.buildFilename("Default", for: .bundle), "resource:Default")
		XCTAssertEqual(TPCThemeController.buildFilename("Solarized", for: .custom), "user:Solarized")
		XCTAssertNil(TPCThemeController.buildFilename("Default", for: .unknown))
		XCTAssertNil(TPCThemeController.buildFilename("", for: .bundle))
	}

	func testPublishedThemeIsPopulated() {
		let controller = SharedApplication.sharedThemeController()
		XCTAssertNotNil(controller.theme)
		XCTAssertFalse(controller.name.isEmpty)
		XCTAssertTrue(controller.originalURL.isFileURL)
		XCTAssertTrue(controller.temporaryURL.isFileURL)
		XCTAssertNotEqual(controller.storageLocation, .unknown)
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
