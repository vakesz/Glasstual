import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Secure transport cipher suites")
struct RCMSecureTransportTests {
	@Test("The compatibility list keeps the deprecated suites, ranked below their modern replacements")
	func compatibilityCipherListIncludesDeprecatedSuites() throws {
		let modernSuite = NSNumber(value: TLS_DHE_RSA_WITH_AES_256_GCM_SHA384)
		let deprecatedSuite = NSNumber(value: TLS_RSA_WITH_AES_256_GCM_SHA384)
		let cipherSuites = SecureTransportSupport.cipherSuites(
			inCollection: .default,
			includeDeprecated: true
		)

		let modernIndex = try #require(cipherSuites.firstIndex(of: modernSuite))
		let deprecatedIndex = try #require(cipherSuites.firstIndex(of: deprecatedSuite))

		#expect(modernIndex < deprecatedIndex)
	}

	@Test("The modern list drops the deprecated suites entirely")
	func modernCipherListExcludesDeprecatedSuites() {
		let cipherSuites = SecureTransportSupport.cipherSuites(
			inCollection: .default,
			includeDeprecated: false
		)

		#expect(cipherSuites.contains(NSNumber(value: TLS_RSA_WITH_AES_256_GCM_SHA384)) == false)
	}
}
