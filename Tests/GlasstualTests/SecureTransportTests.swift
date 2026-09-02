import CocoaExtensions
import Foundation
@testable import Glasstual
import Security
import Testing

@MainActor
@Suite("Secure transport cipher suites")
struct SecureTransportTests {
	private static let collections: [CipherSuiteCollection] = [.default, .mozilla2015, .mozilla2017, .none]

	/** `tls_ciphersuite_t` is what Network.framework negotiates from, and it
	 imports as a non-frozen `RawRepresentable`, so a raw value outside it is not
	 rejected anywhere -- `tls.cipherSuites(_:)` simply never offers it. A list
	 that advertises suites the platform cannot act on is a list the user chose
	 and did not get. */
	@Test("Every advertised suite is one the platform actually defines")
	func everyAdvertisedSuiteIsDefinedByThePlatform() {
		for collection in Self.collections {
			for includeDeprecated in [true, false] {
				let suites = SecureTransportSupport.cipherSuites(
					inCollection: collection,
					includeDeprecated: includeDeprecated
				)

				for suite in suites {
					#expect(
						tls_ciphersuite_t(rawValue: suite.uint16Value) != nil,
						"\(collection) offers 0x\(String(suite.uint16Value, radix: 16)), which tls_ciphersuite_t does not define"
					)
				}
			}
		}
	}

	@Test("Every advertised suite has a name to show for it")
	func everyAdvertisedSuiteIsNamed() throws {
		for collection in Self.collections {
			for suite in SecureTransportSupport.cipherSuites(inCollection: collection, includeDeprecated: true) {
				let value = try #require(tls_ciphersuite_t(rawValue: suite.uint16Value))
				let description = SecureTransportSupport.description(forCipherSuite: value)

				#expect(description != "Unknown", "0x\(String(suite.uint16Value, radix: 16)) has no name")
			}
		}
	}

	@Test("The list the sheet shows names one suite per suite offered")
	func describedListMatchesTheOfferedList() {
		for collection in Self.collections {
			let offered = SecureTransportSupport.cipherSuites(inCollection: collection)
			let described = SecureTransportSupport.descriptions(forCipherListCollection: collection)

			#expect(described.count == offered.count)
			#expect(described.contains("Unknown") == false)
		}
	}

	@Test("The compatibility list keeps the deprecated suites, ranked below their modern replacements")
	func compatibilityCipherListIncludesDeprecatedSuites() throws {
		let modernSuite = NSNumber(value: TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384)
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
