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

import Foundation
@testable import Glasstual
import Testing

/// `NSAllowsArbitraryLoadsInWebContent` cannot be turned off at runtime, so
/// `permitsInlineMedia(at:)` is what actually decides whether a cleartext URL
/// an IRC peer posted reaches the web view. The inline-content service calls it
/// before it will fetch or embed anything.
@Suite("Inline media cleartext policy", .serialized)
@MainActor
struct InlineMediaCleartextPolicyTests {
	private func withCleartextAllowed(_ allowed: Bool, _ body: () throws -> Void) rethrows {
		let original = Preferences.InlineMedia.allowsCleartextHTTP.value
		Preferences.InlineMedia.allowsCleartextHTTP.value = allowed
		defer { Preferences.InlineMedia.allowsCleartextHTTP.value = original }

		try body()
	}

	@Test("Cleartext inline media is allowed by default")
	func defaultsToAllowingCleartext() {
		#expect(Preferences.InlineMedia.allowsCleartextHTTP.defaultValue)
	}

	@Test(
		"https is always inlined",
		arguments: ["https://example.com/a.png", "HTTPS://example.com/a.png"]
	)
	func allowsSecureURLs(_ string: String) throws {
		let url = try #require(URL(string: string))

		withCleartextAllowed(false) {
			#expect(TextualPreferences.permitsInlineMedia(at: url))
		}
	}

	@Test(
		"http is inlined only while the preference allows it",
		arguments: ["http://example.com/a.png", "HTTP://example.com/a.png"]
	)
	func gatesCleartextURLs(_ string: String) throws {
		let url = try #require(URL(string: string))

		withCleartextAllowed(true) {
			#expect(TextualPreferences.permitsInlineMedia(at: url))
		}
		withCleartextAllowed(false) {
			#expect(TextualPreferences.permitsInlineMedia(at: url) == false)
		}
	}

	@Test(
		"Every other scheme is refused whatever the preference says",
		arguments: [
			"file:///etc/passwd",
			"data:image/png;base64,AAAA",
			"ftp://example.com/a.png",
			"javascript:alert(1)",
		]
	)
	func refusesOtherSchemes(_ string: String) throws {
		let url = try #require(URL(string: string))

		withCleartextAllowed(true) {
			#expect(TextualPreferences.permitsInlineMedia(at: url) == false)
		}
	}
}
