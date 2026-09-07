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
			withAttributes: LogRendererConfiguration(preferredFont: font)
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
			withAttributes: LogRendererConfiguration(preferredFont: font)
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

	@Test("Leading paired formatting toggles cancel before any text", arguments: [
		"\u{02}", "\u{1D}", "\u{16}", "\u{11}", "\u{1E}", "\u{1F}",
	])
	func leadingPairedTogglesCancel(control: String) {
		let body = LogRenderer.renderNativeBody(
			control + control + "plain", withAttributes: TranscriptRenderOptions(), members: []
		)
		#expect(body.runs == [TranscriptTextRun(text: "plain")])
	}

	@Test("Leading color resets clear both colors before any text", arguments: [
		"\u{03}04,02\u{03}",
		"\u{04}FF0000,0000FF\u{04}",
		"\u{03}04,02\u{0F}",
		"\u{03}04,02\u{03}99,99",
	])
	func leadingColorResetsClearBothColors(controls: String) {
		let body = LogRenderer.renderNativeBody(
			controls + "plain", withAttributes: TranscriptRenderOptions(), members: []
		)
		#expect(body.runs == [TranscriptTextRun(text: "plain")])
	}

	@Test("A foreground-only change retains the preceding background at offset zero")
	func leadingForegroundChangeRetainsBackground() {
		let body = LogRenderer.renderNativeBody(
			"\u{03}04,02\u{03}03plain", withAttributes: TranscriptRenderOptions(), members: []
		)
		#expect(body.runs == [TranscriptTextRun(text: "plain", foreground: .palette(3), background: .palette(2))])
	}

	@Test("Formatting splits retain the complete channel and canonical nickname targets")
	func formattedAnnotationsKeepCompleteTargets() {
		let body = LogRenderer.renderNativeBody(
			"a\u{02}LI\u{02}ce #sw\u{1D}IF\u{1D}t",
			withAttributes: TranscriptRenderOptions(lineType: .privateMessage),
			members: [RenderedMember(nickname: "Alice")]
		)
		#expect(body.plainText == "aLIce #swIFt")
		#expect(body.mentionedNicknames == ["Alice"])
		#expect(body.runs == [
			TranscriptTextRun(text: "a", action: .nickname("Alice")),
			TranscriptTextRun(text: "LI", traits: .bold, action: .nickname("Alice")),
			TranscriptTextRun(text: "ce", action: .nickname("Alice")),
			TranscriptTextRun(text: " "),
			TranscriptTextRun(text: "#sw", action: .channel("#swIFt")),
			TranscriptTextRun(text: "IF", traits: .italic, action: .channel("#swIFt")),
			TranscriptTextRun(text: "t", action: .channel("#swIFt")),
		])
	}
}
