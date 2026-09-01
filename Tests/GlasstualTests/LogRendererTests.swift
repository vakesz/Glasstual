/* *********************************************************************
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the conditions in the project's
 * source license are met.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import Testing

@MainActor
@Suite("Log renderer")
struct LogRendererTests {
	@Test("Rendering strips the control characters and keeps the effect they opened")
	func attributedRenderingRemovesControlCharactersAndPreservesEffects() throws {
		let bold = String(UnicodeScalar(UInt8(IRCTextFormatterControlCharacter.bold)))
		let source = "plain \(bold)bold\(bold) plain"
		let font = try #require(NSFont(name: "Helvetica", size: 13))

		let rendered = LogRenderer.renderBody(
			asAttributedString: source,
			withAttributes: [.preferredFont: font]
		)

		#expect(rendered.string == "plain bold plain")

		let boldRange = (rendered.string as NSString).range(of: "bold")

		#expect(rendered.attribute(
			NSAttributedString.Key(IRCTextFormatterAttributeName.boldAttributeName.rawValue),
			at: boldRange.location,
			effectiveRange: nil
		) as? Bool == true)

		let trailingRange = (rendered.string as NSString).range(of: "plain", options: .backwards)

		#expect(rendered.attribute(
			NSAttributedString.Key(IRCTextFormatterAttributeName.boldAttributeName.rawValue),
			at: trailingRange.location,
			effectiveRange: nil
		) == nil)
	}

	@Test("Colour sequences and the reset control delimit one attributed run")
	func attributedRenderingAppliesColorUntilReset() throws {
		let color = String(UnicodeScalar(UInt8(IRCTextFormatterControlCharacter.colorDigit)))
		let reset = String(UnicodeScalar(UInt8(IRCTextFormatterControlCharacter.terminator)))
		let font = try #require(NSFont(name: "Helvetica", size: 13))
		let rendered = LogRenderer.renderBody(
			asAttributedString: "\(color)04red\(reset) plain",
			withAttributes: [.preferredFont: font]
		)

		#expect(rendered.string == "red plain")

		let colorKey = NSAttributedString.Key(
			IRCTextFormatterAttributeName.foregroundColorAttributeName.rawValue
		)
		let redRange = (rendered.string as NSString).range(of: "red")
		let plainRange = (rendered.string as NSString).range(of: "plain")

		#expect((rendered.attribute(colorKey, at: redRange.location, effectiveRange: nil) as? NSNumber)?.intValue == 4)
		#expect(rendered.attribute(colorKey, at: plainRange.location, effectiveRange: nil) == nil)
	}

	@Test("IRC palette codes map to native colours")
	func colorHelpersMapToNativeColors() {
		#expect(LogRenderer.mapColorCode(4) == NSColor.formatterColors[4])
		#expect(LogRenderer.mapColor(NSNumber(value: 4)) == NSColor.formatterColors[4])
		#expect(LogRenderer.mapColor("4") == nil)
	}
}
