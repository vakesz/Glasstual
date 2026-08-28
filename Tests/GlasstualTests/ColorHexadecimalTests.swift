import AppKit
import CocoaExtensions
import Testing

/// Hexadecimal colours come from themes and from IRC messages, so parsing has
/// to be exact and formatting must not raise on a colour it cannot read.
@Suite("Hexadecimal colours")
@MainActor
struct ColorHexadecimalTests {
	private struct Channels {
		let red: Int
		let green: Int
		let blue: Int
		let alpha: Int
	}

	private func components(_ value: String) throws -> Channels {
		let color = try #require(NSColor.textual_color(hexadecimalValue: value))
		let converted = try #require(color.usingColorSpace(.sRGB))

		return Channels(
			red: Int((converted.redComponent * 0xFF).rounded()),
			green: Int((converted.greenComponent * 0xFF).rounded()),
			blue: Int((converted.blueComponent * 0xFF).rounded()),
			alpha: Int((converted.alphaComponent * 0xFF).rounded())
		)
	}

	@Test("A channel byte of one is nearly black, not full intensity")
	func channelOfOneIsNotFullIntensity() throws {
		let parsed = try components("#010101")

		#expect(parsed.red == 1)
		#expect(parsed.green == 1)
		#expect(parsed.blue == 1)
		#expect(parsed.alpha == 0xFF)
	}

	@Test("An alpha byte of one is nearly transparent")
	func alphaOfOneIsNearlyTransparent() throws {
		#expect(try components("#FFFFFF01").alpha == 1)
	}

	@Test("Six and eight digit values parse")
	func sixAndEightDigitValuesParse() throws {
		let opaque = try components("#FF8000")

		#expect(opaque.red == 0xFF)
		#expect(opaque.green == 0x80)
		#expect(opaque.blue == 0x00)
		#expect(opaque.alpha == 0xFF)

		#expect(try components("#FF800080").alpha == 0x80)
	}

	@Test("CSS shorthand expands")
	func shorthandExpands() throws {
		let parsed = try components("#F00")

		#expect(parsed.red == 0xFF)
		#expect(parsed.green == 0)
		#expect(parsed.blue == 0)
		#expect(parsed.alpha == 0xFF)

		#expect(try components("#F008").alpha == 0x88)

		/* Four digits used to be shifted as if they were RGB. */
		let fourDigit = try components("#AABB")

		#expect(fourDigit.red == 0xAA)
		#expect(fourDigit.green == 0xAA)
		#expect(fourDigit.blue == 0xBB)
		#expect(fourDigit.alpha == 0xBB)
	}

	@Test(
		"Lengths that are not a colour notation are refused",
		arguments: ["#F", "#FF", "#AABBC", "#AABBCCD", "#AABBCCDDEE", "#"]
	)
	func invalidLengthsAreRefused(value: String) {
		#expect(NSColor.textual_color(hexadecimalValue: value) == nil)
	}

	@Test("Non-hexadecimal digits are refused")
	func nonHexadecimalDigitsAreRefused() {
		#expect(NSColor.textual_color(hexadecimalValue: "#ZZZZZZ") == nil)
	}

	@Test("A catalog colour still yields a hexadecimal value")
	func catalogColorFormats() {
		/* These used to raise an uncatchable exception on component access. */
		#expect(NSColor.labelColor.textualHexadecimalValue.hasPrefix("#"))
		#expect(NSColor.textColor.textualHexadecimalValue.count == 7)
	}

	@Test("Formatting round-trips a parsed colour")
	func formattingRoundTrips() throws {
		let color = try #require(NSColor.textual_color(hexadecimalValue: "#3C6E71"))

		#expect(color.textualHexadecimalValue == "#3C6E71")
	}
}
