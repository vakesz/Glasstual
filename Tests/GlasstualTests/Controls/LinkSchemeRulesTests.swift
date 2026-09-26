@testable import Glasstual
import Testing

/// `OpenLink` hands a remote peer's URL to `NSWorkspace`, so the allowlist
/// that decides what becomes clickable also decides what may be launched.
@Suite("Link scheme rules")
struct LinkSchemeRulesTests {
	@Test("A denied scheme stays denied even when all schemes or that scheme are allowed",
	      arguments: ["file", "smb", "javascript", "data", "x-apple.systempreferences"])
	func customizationCannotPermitDeniedSchemes(scheme: String) {
		let rules = LinkSchemeRules(permitsAnyScheme: true, permittedSchemes: [scheme])
		#expect(rules.permits(scheme: scheme) == false)
		#expect(rules.permits(scheme: scheme.uppercased()) == false)
		#expect(rules.permits(link: "\(scheme):payload") == false)
	}

	@Test("Custom schemes are checked against the supplied snapshot")
	func customSchemesUseSnapshot() {
		let restricted = LinkSchemeRules(permittedSchemes: ["example"])
		#expect(restricted.permits(scheme: "EXAMPLE"))
		#expect(restricted.permits(link: "example:message"))
		#expect(restricted.permits(scheme: "other") == false)
		#expect(LinkSchemeRules(permitsAnyScheme: true).permits(scheme: "other"))
		#expect(LinkSchemeRules().permits(scheme: "example") == false)
	}

	@Test("Web schemes are permitted", arguments: ["http", "https", "HTTP", "HTTPS"])
	func webSchemesArePermitted(scheme: String) {
		#expect(LinkSchemeRules().permits(scheme: scheme))
	}

	@Test(
		"Schemes that reach the file system or system settings are refused",
		arguments: ["file", "FILE", "smb", "afp", "nfs", "cifs", "x-apple.systempreferences"]
	)
	func dangerousSchemesAreRefused(scheme: String) {
		#expect(LinkSchemeRules().permits(scheme: scheme) == false)
	}

	@Test("A scheme nobody registered is refused")
	func unknownSchemeIsRefused() {
		#expect(LinkSchemeRules().permits(scheme: "com.example.some-app") == false)
	}
}
