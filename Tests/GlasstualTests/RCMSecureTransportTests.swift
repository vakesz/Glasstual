import XCTest

// Preprocessor directives found in file:
// #import <XCTest/XCTest.h>
// #import "RCMSecureTransport.h"
@objc
class RCMSecureTransportTests: XCTestCase {
    @objc
    func testCompatibilityCipherListIncludesDeprecatedSuites() {
        let cipherSuites = RCMSecureTransport.cipherSuitesInCollection(RCMCipherSuiteCollectionDefault, includeDeprecated: true)
        let dheIndex: UInt = cipherSuites?.indexOfObject(TLS_DHE_RSA_WITH_AES_256_GCM_SHA384)
        let rsaIndex: UInt = cipherSuites?.indexOfObject(TLS_RSA_WITH_AES_256_GCM_SHA384)

        XCTAssertNotEqual(dheIndex, NSNotFound)
        XCTAssertTrue(cipherSuites?.containsObject(TLS_RSA_WITH_AES_256_GCM_SHA384))
        XCTAssertLessThan(dheIndex, rsaIndex)
    }
    @objc
    func testModernCipherListExcludesDeprecatedSuites() {
        let cipherSuites = RCMSecureTransport.cipherSuitesInCollection(RCMCipherSuiteCollectionDefault, includeDeprecated: false)

        XCTAssertFalse(cipherSuites?.containsObject(TLS_RSA_WITH_AES_256_GCM_SHA384))
    }
}

// MARK: - RCMSecureTransportTests
@objc
extension RCMSecureTransport {
    @objc
    static func cipherSuitesInCollection(_ collection: RCMCipherSuiteCollection, includeDeprecated: Bool) -> [NSNumber]? {
    }
}