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
		var values = try InlineContentPayloadValues(
			url: #require(URL(string: "https://example.com/page")),
			uniqueIdentifier: "identifier",
			lineNumber: "1",
			index: 0,
			viewIdentifier: "view"
		)

		#expect(try values.setURLToInline(#require(URL(string: "https://example.com/image.png"))))
		#expect(values.urlToInline.absoluteString == "https://example.com/image.png")

		/* Refused rather than trapped, and the previous value stands. */
		#expect(values.setURLToInline(URL(fileURLWithPath: "/etc/passwd")) == false)
		#expect(values.urlToInline.absoluteString == "https://example.com/image.png")
	}
}
