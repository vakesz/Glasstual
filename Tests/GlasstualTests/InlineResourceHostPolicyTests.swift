import Foundation
@testable import Glasstual
import Testing

/// An inline-content module's `scriptResources` become `<script src>` in a
/// page that holds the native `app` bridge, so the host is checked before the
/// address is handed to the page.
@Suite("Inline resource host policy")
@MainActor
struct InlineResourceHostPolicyTests {
	@Test("A local file is copied and served from the theme directory")
	func fileURLsArePermitted() throws {
		let url = try #require(URL(string: "file:///tmp/module.js"))
		#expect(InlineResourceHostPolicy.permits(url))
	}

	@Test("The listed host may serve over HTTPS")
	func listedHostIsPermitted() throws {
		let url = try #require(URL(string: "https://platform.twitter.com/widgets.js"))
		#expect(InlineResourceHostPolicy.permits(url))
	}

	@Test("The host match is case insensitive")
	func hostMatchIgnoresCase() throws {
		let url = try #require(URL(string: "https://Platform.Twitter.COM/widgets.js"))
		#expect(InlineResourceHostPolicy.permits(url))
	}

	@Test(
		"Everything else is refused",
		arguments: [
			"http://platform.twitter.com/widgets.js",
			"https://example.com/evil.js",
			"https://platform.twitter.com.example.com/evil.js",
			"https://evil.platform.twitter.com/evil.js",
			"https://platform.twitter.com@example.com/evil.js",
			"data:text/javascript,alert(1)",
			"javascript:alert(1)",
			"ftp://platform.twitter.com/widgets.js",
			"https:///widgets.js",
		]
	)
	func unlistedResourcesAreRefused(address: String) throws {
		let url = try #require(URL(string: address))
		#expect(InlineResourceHostPolicy.permits(url) == false)
	}

	/// Every remote host named here also has to be listed in
	/// `Glasstual.permittedResourceHosts` in `corePrivate.js`.
	@Test("Only hosts the app ships a module for are listed")
	func theListStaysSmall() {
		#expect(LogViewContentPolicy.permittedScriptOrigins == ["https://platform.twitter.com"])
	}
}
