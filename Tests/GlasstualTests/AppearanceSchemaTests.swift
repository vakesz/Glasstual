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
@testable import Glasstual
import Testing

@Suite("Appearance schema")
@MainActor
struct AppearanceSchemaTests {
	private static let appearanceName = "Tahoe"

	@Test("The main window appearance plist decodes")
	func mainWindowAppearanceDecodes() throws {
		let schema = try #require(
			AppearanceSchema.load(
				MainWindowAppearanceSchema.self,
				resource: "TVCMainWindowAppearance",
				appearanceName: Self.appearanceName
			)
		)

		#expect(schema.defaultWindowSize.size == NSSize(width: 800, height: 474))
		#expect(schema.channelViewOverlayDefaultBackgroundColor?.color(forActiveWindow: true) != nil)
		#expect(schema.channelViewOverlayDefaultBackgroundColor?.color(forActiveWindow: false) != nil)
	}

	@Test("The input text view appearance plist decodes")
	func textViewAppearanceDecodes() throws {
		let schema = try #require(
			AppearanceSchema.load(
				MainWindowTextViewAppearanceSchema.self,
				resource: "TVCMainWindowTextViewAppearance",
				appearanceName: Self.appearanceName
			)
		)

		#expect(schema.textView.inset.size == NSSize(width: 1, height: 2))
		#expect(schema.textView.normalTextColor?.color != nil)
		#expect(schema.textView.placeholderTextColor?.color != nil)
		#expect(schema.backgroundView.contentBorderPadding == 23)
	}

	@Test("The channel spotlight appearance plist decodes")
	func channelSpotlightAppearanceDecodes() throws {
		let schema = try #require(
			AppearanceSchema.load(
				ChannelSpotlightAppearanceSchema.self,
				resource: "TDCChannelSpotlightAppearance",
				appearanceName: Self.appearanceName
			)
		)

		#expect(schema.searchField.controlTextColor?.color != nil)
		#expect(schema.searchField.noResultsTextColor?.color != nil)
		#expect(schema.searchResult.keyboardShortcutDeselectedOffset == 0)
		#expect(schema.searchResult.keyboardShortcutSelectedOffset == 3)
	}

	@Test("An appearance the file does not carry decodes to nil rather than crashing")
	func unknownAppearanceIsNil() {
		let schema = AppearanceSchema.load(
			MainWindowAppearanceSchema.self,
			resource: "TVCMainWindowAppearance",
			appearanceName: "Not An Appearance"
		)
		#expect(schema == nil)
	}

	/// Semantic colours used to be resolved with
	/// `NSColor.perform(NSSelectorFromString(value))`, which would send any
	/// zero-argument message the plist named. The table replaces that.
	@Test("Every semantic colour the shipped plists name is in the table")
	func shippedSystemColorsAreKnown() throws {
		let names = try Self.systemColorNames()
		#expect(names.isEmpty == false)

		for name in names {
			#expect(AppearanceColor.systemColors[name] != nil, "\(name) is not a known semantic colour")
		}
	}

	@Test("An unknown semantic colour resolves to nil instead of a runtime lookup")
	func unknownSystemColorIsNil() {
		#expect(AppearanceColor.system(name: "notAColorColor").color == nil)
		// A real NSColor class method that is not a colour: the selector-based
		// lookup would have called it.
		#expect(AppearanceColor.system(name: "clearColor").color == nil)
	}

	@Test("Colour components decode from their whitespace-separated spelling")
	func colorComponentsDecode() throws {
		let white = try Self.decodeColor(type: 1, value: "0.5 0.25")
		#expect(white == .calibratedWhite(white: 0.5, alpha: 0.25))

		let opaqueWhite = try Self.decodeColor(type: 1, value: "0.5")
		#expect(opaqueWhite == .calibratedWhite(white: 0.5, alpha: 1))

		let rgb = try Self.decodeColor(type: 2, value: "0.1 0.2 0.3 0.4")
		#expect(rgb == .calibratedRGB(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.4))

		let opaqueRGB = try Self.decodeColor(type: 2, value: "0.1 0.2 0.3")
		#expect(opaqueRGB == .calibratedRGB(red: 0.1, green: 0.2, blue: 0.3, alpha: 1))
	}

	@Test("A colour with too few components fails to decode")
	func malformedColorFailsToDecode() {
		#expect(throws: (any Error).self) { try Self.decodeColor(type: 2, value: "0.1 0.2") }
		#expect(throws: (any Error).self) { try Self.decodeColor(type: 1, value: "") }
	}

	@Test("A stateful colour keeps its two window states apart")
	func statefulColorDecodes() throws {
		let plist: [String: Any] = [
			"activeWindow": ["type": 2, "value": "1 0 0"],
			"inactiveWindow": ["type": 2, "value": "0 0 1"],
		]
		let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
		let color = try PropertyListDecoder().decode(AppearanceStatefulColor.self, from: data)

		#expect(color == .stateful(
			active: .calibratedRGB(red: 1, green: 0, blue: 0, alpha: 1),
			inactive: .calibratedRGB(red: 0, green: 0, blue: 1, alpha: 1)
		))
	}

	private static func decodeColor(type: Int, value: String) throws -> AppearanceColor {
		let data = try PropertyListSerialization.data(
			fromPropertyList: ["type": type, "value": value],
			format: .xml,
			options: 0
		)
		return try PropertyListDecoder().decode(AppearanceColor.self, from: data)
	}

	/// Every `type = 3` value across the three shipped appearance files.
	private static func systemColorNames() throws -> [String] {
		let directory = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.appending(path: "Sources/App/Resources/User Interface/Appearance")
		let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)

		var names: [String] = []
		for file in files where file.pathExtension == "plist" {
			let plist = try PropertyListSerialization.propertyList(
				from: Data(contentsOf: file),
				format: nil
			)
			collectSystemColorNames(in: plist, into: &names)
		}
		return names
	}

	private static func collectSystemColorNames(in node: Any, into names: inout [String]) {
		guard let dictionary = node as? [String: Any] else { return }

		if (dictionary["type"] as? Int) == 3, let value = dictionary["value"] as? String {
			names.append(value)
			return
		}

		for value in dictionary.values {
			collectSystemColorNames(in: value, into: &names)
		}
	}
}
