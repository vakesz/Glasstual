import Foundation
import InlineContentKit
import Testing

/// The URL a module resolves ends up in a `src` attribute in the log view, so
/// it is filtered rather than trusted.
@Suite("Inline content URL policy")
struct InlineContentURLPolicyTests {
	@Test("HTTP addresses resolve")
	func webAddressesResolve() {
		#expect(InlineContentHelpers.url(with: "https://example.com/a.png")?.absoluteString
			== "https://example.com/a.png")
		#expect(InlineContentHelpers.url(with: "http://example.com/a.png")?.absoluteString
			== "http://example.com/a.png")
	}

	@Test("A protocol-relative address is completed as HTTPS")
	func protocolRelativeAddressIsCompleted() {
		#expect(InlineContentHelpers.url(with: "//example.com/a.png")?.scheme == "https")
	}

	@Test(
		"Everything else is refused",
		arguments: [
			"file:///etc/passwd",
			"FILE:///etc/passwd",
			"javascript:alert(1)",
			"data:text/html;base64,AAAA",
			"smb://example.com/share",
			"about:blank",
		]
	)
	func otherSchemesAreRefused(address: String) {
		#expect(InlineContentHelpers.url(with: address) == nil)
	}

	@Test("An unparseable address is refused")
	func unparseableAddressIsRefused() {
		#expect(InlineContentHelpers.url(with: "") == nil)
	}

	@Test("A payload will not take an out-of-policy inline URL")
	func payloadRejectsOutOfPolicyURL() throws {
		let payload = try InlineContentPayloadMutable(
			url: #require(URL(string: "https://example.com/page")),
			withUniqueIdentifier: "identifier",
			atLineNumber: "1",
			index: 0,
			inView: "view"
		)

		payload.urlToInline = try #require(URL(string: "https://example.com/image.png"))
		#expect(payload.urlToInline.absoluteString == "https://example.com/image.png")

		/* Rejected rather than trapped, and the previous value stands. */
		payload.urlToInline = URL(fileURLWithPath: "/etc/passwd")
		#expect(payload.urlToInline.absoluteString == "https://example.com/image.png")
	}
}
