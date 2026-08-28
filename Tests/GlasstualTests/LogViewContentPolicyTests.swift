/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

/// The log view runs third-party style code, so the set of origins it can
/// reach is a security boundary rather than a convenience.
@Suite("Log view content policy")
@MainActor
struct LogViewContentPolicyTests {
	@Test("The bundled base layout declares exactly the policy the Swift side sends")
	func baseLayoutDeclaresTheSamePolicy() throws {
		let templateURL = try #require(
			Bundle.main.resourceURL?
				.appending(path: "Style Default Templates/Version 4/baseLayout.mustache")
		)
		let template = try String(contentsOf: templateURL, encoding: .utf8)
		let expected = """
		<meta http-equiv="Content-Security-Policy" content="\(LogViewContentPolicy.contentSecurityPolicy)">
		"""

		#expect(template.contains(expected))
	}

	@Test("Every permitted script origin appears in the policy")
	func permittedScriptOriginsAreInThePolicy() {
		for origin in LogViewContentPolicy.permittedScriptOrigins {
			#expect(LogViewContentPolicy.contentSecurityPolicy.contains(origin))
		}
		#expect(LogViewContentPolicy.contentSecurityPolicy.contains("default-src 'none'"))
	}

	@Test(
		"Only the theme scheme and the allowlisted origins may contribute script",
		arguments: [
			("glasstual-theme://theme/Users/me/style.js", true),
			("https://platform.twitter.com/widgets.js", true),
			("https://platform.twitter.com:443/widgets.js", true),
			("https://platform.twitter.com:8443/widgets.js", false),
			("http://platform.twitter.com/widgets.js", false),
			("https://evil.example/widgets.js", false),
			("file:///etc/passwd", false),
		]
	)
	func scriptResourcesAreFiltered(address: String, permitted: Bool) throws {
		let url = try #require(URL(string: address))
		#expect(LogViewContentPolicy.permitsScriptResource(at: url) == permitted)
	}

	@Test(
		"The main frame never leaves the theme",
		arguments: [
			("glasstual-theme://theme/Users/me/view.html", true),
			("about:blank", true),
			("https://example.com/", false),
			("http://example.com/", false),
			("file:///etc/passwd", false),
			("javascript:alert(1)", false),
			("about:srcdoc", false),
		]
	)
	func mainFrameNavigationIsRestricted(address: String, permitted: Bool) throws {
		let url = try #require(URL(string: address))
		#expect(LogViewContentPolicy.permitsNavigation(to: url, inMainFrame: true) == permitted)
	}

	@Test(
		"Subframes may reach HTTPS because inline media embeds video players there",
		arguments: [
			("https://www.youtube.com/embed/a", true),
			("http://www.youtube.com/embed/a", false),
			("file:///etc/passwd", false),
		]
	)
	func subframeNavigationAllowsSecureEmbeds(address: String, permitted: Bool) throws {
		let url = try #require(URL(string: address))
		#expect(LogViewContentPolicy.permitsNavigation(to: url, inMainFrame: false) == permitted)
	}

	@Test("An absent address is refused")
	func absentAddressIsRefused() {
		#expect(LogViewContentPolicy.permitsNavigation(to: nil, inMainFrame: true) == false)
		#expect(LogViewContentPolicy.permitsNavigation(to: nil, inMainFrame: false) == false)
	}

	@Test(
		"A file path survives the round trip through a theme URL",
		arguments: [
			"/Users/me/Library/Caches/Cached Style Resources/design.css",
			"/Users/me/Themes/a b/c#d?e.css",
			"/Users/me/Themes/ünïcode/scripts.js",
		]
	)
	func filePathsRoundTrip(path: String) throws {
		let url = try #require(LogViewContentPolicy.resourceURL(forFilePath: path))

		#expect(url.scheme == LogViewContentPolicy.themeScheme)
		#expect(url.host() == LogViewContentPolicy.themeHost)
		#expect(LogViewContentPolicy.filePath(for: url) == path)
	}

	@Test("A relative path has no theme URL")
	func relativePathHasNoResourceURL() {
		#expect(LogViewContentPolicy.resourceURL(forFilePath: "design.css") == nil)
	}

	@Test("Only theme URLs name a file")
	func onlyThemeURLsNameAFile() throws {
		let url = try #require(URL(string: "https://example.com/etc/passwd"))
		#expect(LogViewContentPolicy.filePath(for: url) == nil)
	}

	@Test("A user style sheet cannot close the style element it lands in")
	func userStyleSheetCannotCloseTheStyleElement() throws {
		let sanitized = try #require(
			LogViewContentPolicy.sanitizedStyleSheetText("body { }</STYLE><script>alert(1)</script>")
		)

		#expect(sanitized.range(of: "</style", options: [.caseInsensitive]) == nil)
		#expect(sanitized.contains("body { }"))
	}

	@Test("Ordinary rules are passed through unchanged")
	func ordinaryRulesArePassedThrough() {
		#expect(LogViewContentPolicy.sanitizedStyleSheetText("body { color: red; }") == "body { color: red; }")
		#expect(LogViewContentPolicy.sanitizedStyleSheetText(nil) == nil)
	}

	@Test("Font names become safe CSS string literals")
	func fontNamesAreEscaped() {
		#expect(LogViewContentPolicy.cssStringLiteral("Helvetica Neue") == "\"Helvetica Neue\"")
		#expect(LogViewContentPolicy.cssStringLiteral("Bad\"Name") == "\"Bad\\\"Name\"")
		#expect(LogViewContentPolicy.cssStringLiteral("A\\B") == "\"A\\\\B\"")
		#expect(LogViewContentPolicy.cssStringLiteral("x</style>").contains("<") == false)
		#expect(LogViewContentPolicy.cssStringLiteral("line\nbreak") == "\"linebreak\"")
	}
}
