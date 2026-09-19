import CocoaExtensions
import Foundation
@testable import Glasstual
import Security
import Testing

@MainActor
@Suite("Secure transport cipher suites")
struct SecureTransportTests {
	private static let collections: [CipherSuiteCollection] = [.system, .modern, .intermediate]

	/// Everything a handshake can be offered: a collection's own suites, plus the
	/// legacy ones the transport's fallback adds to them.
	private static func everyOfferableSuite() -> [NSNumber] {
		collections.flatMap { SecureTransportSupport.cipherSuites(inCollection: $0) }
			+ SecureTransportSupport.legacyCipherSuites
	}

	/** `tls_ciphersuite_t` is what Network.framework negotiates from, and it
	 imports as a non-frozen `RawRepresentable`, so a raw value outside it is not
	 rejected anywhere -- `tls.cipherSuites(_:)` simply never offers it. A list
	 that advertises suites the platform cannot act on is a list the user chose
	 and did not get. */
	@Test("Every advertised suite is one the platform actually defines")
	func everyAdvertisedSuiteIsDefinedByThePlatform() {
		for suite in Self.everyOfferableSuite() {
			#expect(
				tls_ciphersuite_t(rawValue: suite.uint16Value) != nil,
				"0x\(String(suite.uint16Value, radix: 16)) is offered, and tls_ciphersuite_t does not define it"
			)
		}
	}

	@Test("Every advertised suite has a name to show for it")
	func everyAdvertisedSuiteIsNamed() throws {
		for suite in Self.everyOfferableSuite() {
			let value = try #require(tls_ciphersuite_t(rawValue: suite.uint16Value))
			let description = SecureTransportSupport.description(forCipherSuite: value)

			#expect(description != "Unknown", "0x\(String(suite.uint16Value, radix: 16)) has no name")
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

	/// `.system` offers nothing of its own on purpose: `ConnectionParameters`
	/// reads the empty list as "hand the handshake the platform's own group".
	@Test("The system collection names no suite of its own")
	func systemCollectionNamesNoSuites() {
		#expect(SecureTransportSupport.cipherSuites(inCollection: .system).isEmpty)
	}

	@Test("No collection a user can pick offers a suite without forward secrecy")
	func noSelectableCollectionOffersALegacySuite() throws {
		for collection in Self.collections {
			for suite in SecureTransportSupport.cipherSuites(inCollection: collection) {
				let value = try #require(tls_ciphersuite_t(rawValue: suite.uint16Value))

				#expect(
					SecureTransportSupport.isCipherSuiteLegacy(value) == false,
					"\(collection) offers \(SecureTransportSupport.description(forCipherSuite: value))"
				)
			}
		}
	}

	@Test("Every suite the fallback adds is one without forward secrecy")
	func everyFallbackSuiteIsLegacy() throws {
		let suites = SecureTransportSupport.legacyCipherSuites

		#expect(suites.isEmpty == false)

		for suite in suites {
			let value = try #require(tls_ciphersuite_t(rawValue: suite.uint16Value))

			#expect(SecureTransportSupport.isCipherSuiteLegacy(value))
		}
	}

	/// The GCM suites come first so that a server with both takes the one with an
	/// AEAD rather than the CBC-and-SHA-1 pair.
	@Test("The fallback ranks its suites, strongest first")
	func fallbackSuitesAreRanked() throws {
		let suites = SecureTransportSupport.legacyCipherSuites
		let gcm = try #require(suites.firstIndex(of: NSNumber(value: TLS_RSA_WITH_AES_256_GCM_SHA384)))
		let cbc = try #require(suites.firstIndex(of: NSNumber(value: TLS_RSA_WITH_AES_256_CBC_SHA)))

		#expect(gcm < cbc)
	}

	@Test("The 3DES suite counts as legacy although nothing offers it")
	func tripleDESIsLegacy() throws {
		let suite = try #require(tls_ciphersuite_t(rawValue: 0x000A))

		#expect(SecureTransportSupport.isCipherSuiteLegacy(suite))
		#expect(SecureTransportSupport.legacyCipherSuites.contains(NSNumber(value: 0x000A as UInt16)) == false)
	}

	@Test("A closed client is not reported as an untrusted certificate")
	func closedSessionIsNotACertificateError() {
		/* -9816 is errSSLClosedNoNotify: the server dropped the session, which
		 is what a throttled reconnect looks like. -9825 is the peer rejecting
		 the session's certificate. Neither is the server's certificate failing. */
		#expect(SecureTransportSupport.description(forBadCertificateErrorCode: -9816) == nil)
		#expect(SecureTransportSupport.description(forBadCertificateErrorCode: -9825) == nil)
		#expect(SecureTransportSupport.description(forBadCertificateErrorCode: -9830) == nil)
		#expect(SecureTransportSupport.description(forErrorCode: -9816).isEmpty == false)
	}

	@Test("A certificate the client cannot trust is reported as one")
	func serverCertificateFailuresAreCertificateErrors() {
		for code in [-9807, -9808, -9812, -9813, -9814, -9815, -9843] {
			#expect(SecureTransportSupport.description(forBadCertificateErrorCode: code) != nil, "\(code)")
		}
	}

	/// The owner's report read "Secure Transport Error: Handshake failure
	/// (-9824)", which names the alert and not the cause.
	@Test("A handshake failure says there was no cipher suite in common")
	func handshakeFailureNamesTheMissingCipherSuite() {
		for code in [-9824, -9801] {
			let description = SecureTransportSupport.description(forErrorCode: code)

			#expect(description.contains("\(code)"), "\(code): \(description)")
			#expect(description.localizedCaseInsensitiveContains("cipher suite"), "\(code): \(description)")
		}

		#expect(
			SecureTransportSupport.description(forErrorCode: -9816)
				.localizedCaseInsensitiveContains("cipher suite") == false
		)
	}
}
