@testable import Glasstual
import Testing

/// `TLOpenLink` hands a remote peer's URL to `NSWorkspace`, so the allowlist
/// that decides what becomes clickable also decides what may be launched.
@Suite("Link scheme policy")
@MainActor
struct LinkSchemePolicyTests {
	@Test("Web schemes are permitted", arguments: ["http", "https", "HTTP", "HTTPS"])
	func webSchemesArePermitted(scheme: String) {
		#expect(LinkParser.isPermittedScheme(scheme))
	}

	@Test(
		"Schemes that reach the file system or system settings are refused",
		arguments: ["file", "FILE", "smb", "afp", "nfs", "cifs", "x-apple.systempreferences"]
	)
	func dangerousSchemesAreRefused(scheme: String) {
		#expect(LinkParser.isPermittedScheme(scheme) == false)
	}

	@Test("A scheme nobody registered is refused")
	func unknownSchemeIsRefused() {
		#expect(LinkParser.isPermittedScheme("com.example.some-app") == false)
	}
}
