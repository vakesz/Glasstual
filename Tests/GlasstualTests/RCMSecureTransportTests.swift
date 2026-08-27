import CocoaExtensions
@testable import Glasstual
import XCTest

@objc
class RCMSecureTransportTests: XCTestCase {
	@objc
	func testCompatibilityCipherListIncludesDeprecatedSuites() {
		let cipherSuites = SecureTransportSupport.cipherSuites(
			inCollection: .default,
			includeDeprecated: true
		)
		let dheIndex = cipherSuites.firstIndex(of: NSNumber(value: TLS_DHE_RSA_WITH_AES_256_GCM_SHA384))
		let rsaIndex = cipherSuites.firstIndex(of: NSNumber(value: TLS_RSA_WITH_AES_256_GCM_SHA384))

		XCTAssertNotNil(dheIndex)
		XCTAssertTrue(cipherSuites.contains(NSNumber(value: TLS_RSA_WITH_AES_256_GCM_SHA384)))
		XCTAssertLessThan(try XCTUnwrap(dheIndex), try XCTUnwrap(rsaIndex))
	}

	@objc
	func testModernCipherListExcludesDeprecatedSuites() {
		let cipherSuites = SecureTransportSupport.cipherSuites(
			inCollection: .default,
			includeDeprecated: false
		)

		XCTAssertFalse(cipherSuites.contains(NSNumber(value: TLS_RSA_WITH_AES_256_GCM_SHA384)))
	}
}
