@testable import Glasstual
import Testing

/// Everything the renderer emits lands in a `file://` document that holds the
/// native `app` bridge, so the two values a remote peer can steer — a link's
/// scheme and its combining marks — are filtered at the renderer boundary.
@Suite("Log renderer safety")
@MainActor
struct LogRendererSafetyTests {
	@Test(
		"Ordinary link schemes render as anchors",
		arguments: [
			"https://example.com/a",
			"http://example.com/a",
			"HTTPS://example.com/a",
			"xmpp:user@example.com",
			"magnet:?xt=urn:btih:abc",
		]
	)
	func permittedSchemesRender(location: String) {
		#expect(LogRenderer.isRenderableAnchorLocation(location))
	}

	/// `LinkParser`'s permitted set is user-configurable, so the renderer does
	/// not delegate the decision to it entirely.
	@Test(
		"Scripting and local schemes never reach an href",
		arguments: [
			"javascript:alert(1)",
			"JavaScript:alert(1)",
			"data:text/html;base64,PHNjcmlwdD4=",
			"vbscript:msgbox(1)",
			"blob:https://example.com/abc",
			"about:blank",
			"file:///etc/passwd",
			"smb://example.com/share",
		]
	)
	func refusedSchemesDoNotRender(location: String) {
		#expect(LogRenderer.isRenderableAnchorLocation(location) == false)
	}

	@Test(
		"A location without a usable scheme is refused",
		arguments: [
			"",
			"example.com/a",
			"/etc/passwd",
			"//example.com/a",
			"1http://example.com",
			"has space:whatever",
		]
	)
	func schemelessLocationsAreRefused(location: String) {
		#expect(LogRenderer.isRenderableAnchorLocation(location) == false)
	}

	/// An invalid pattern would make the filter a silent no-op, which is
	/// indistinguishable from a working one without this.
	@Test("Stacked combining marks are collapsed")
	func zalgoTextIsStripped() {
		let zalgo = "h\u{0300}\u{0301}\u{0302}\u{0303}e\u{0304}\u{0305}\u{0306}llo"
		let stripped = LogRenderer.strippingDangerousUnicodeCharacters(zalgo)

		#expect(stripped != zalgo)
		#expect(stripped.contains("\u{FFFD}"))
		#expect(stripped.unicodeScalars.contains { $0.properties.isDiacritic } == false)
	}

	@Test("Text with fewer than three marks in a row is left alone")
	func ordinaryAccentsSurvive() {
		let accented = "cafe\u{0301} nai\u{0308}ve"
		#expect(LogRenderer.strippingDangerousUnicodeCharacters(accented) == accented)
	}
}
