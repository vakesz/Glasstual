/* *********************************************************************
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the conditions in the project's
 * source license are met.
 *********************************************************************** */

@testable import Glasstual
import XCTest

@MainActor
final class LogRendererMigrationTests: XCTestCase {
	func testAttributedRenderingRemovesControlCharactersAndPreservesEffects() throws {
		let bold = String(UnicodeScalar(UInt8(IRCTextFormatterControlCharacter.bold)))
		let source = "plain \(bold)bold\(bold) plain"
		let font = try XCTUnwrap(NSFont(name: "Helvetica", size: 13))

		let rendered = TVCLogRenderer.renderBody(
			asAttributedString: source,
			withAttributes: [.attributedStringPreferredFontAttribute: font]
		)

		XCTAssertEqual(rendered.string, "plain bold plain")
		let boldRange = (rendered.string as NSString).range(of: "bold")
		XCTAssertEqual(
			rendered.attribute(
				NSAttributedString.Key(IRCTextFormatterAttributeName.boldAttributeName.rawValue),
				at: boldRange.location,
				effectiveRange: nil
			) as? Bool,
			true
		)
		let trailingRange = (rendered.string as NSString).range(of: "plain", options: .backwards)
		XCTAssertNil(
			rendered.attribute(
				NSAttributedString.Key(IRCTextFormatterAttributeName.boldAttributeName.rawValue),
				at: trailingRange.location,
				effectiveRange: nil
			)
		)
	}

	func testHTMLAndColorHelpersKeepLegacyResults() {
		XCTAssertEqual(TVCLogRenderer.escapeHTML("<a&b>"), "&lt;a&amp;b&gt;")
		XCTAssertEqual(TVCLogRenderer.mapColorCode(4), NSColor.formatterColors[4])
		XCTAssertEqual(TVCLogRenderer.mapColor(NSNumber(value: 4)), NSColor.formatterColors[4])
		XCTAssertNil(TVCLogRenderer.mapColor("4"))
	}

	func testConfigurationAndResultKeysRetainPersistedValues() {
		XCTAssertEqual(
			TVCLogRendererConfigurationAttribute.renderLinksAttribute,
			"TVCLogRendererConfigurationRenderLinksAttribute"
		)
		XCTAssertEqual(
			TVCLogRendererResultsAttribute.originalBodyWithoutEffectsAttribute,
			"TVCLogRendererResultsOriginalBodyWithoutEffectsAttribute"
		)
	}
}
