import XCTest

// Preprocessor directives found in file:
// #import <XCTest/XCTest.h>
// #import "TLOInternetAddressLookupPrivate.h"
/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */
@objc
class TLOInternetAddressLookupDelegateSpy: NSObject, TLOInternetAddressLookupDelegate {
    @objc
    func internetAddressLookupReturnedAddress(_ address: String) {
    }
    @objc
    func internetAddressLookupFailed() {
    }
}
@objc
class TLOInternetAddressLookupTests: XCTestCase {
    @objc
    func responseWithStatusCode(_ statusCode: Int) -> NSHTTPURLResponse {
        return NSHTTPURLResponse(uRL: URL.URLWithString("https://example.invalid/address"), statusCode: statusCode, HTTPVersion: "HTTP/1.1", headerFields: nil)
    }
    @objc
    func testAddressParserTrimsAndAcceptsEnabledIPv4() {
        let data: NSData! = "  203.0.113.42\\n".dataUsingEncoding(NSUTF8StringEncoding)
        let address: String! = TLOInternetAddressLookup.addressFromData(data, response: self.responseWithStatusCode(200), allowIPv4: true, allowIPv6: false)

        XCTAssertEqualObjects(address, "203.0.113.42")
    }
    @objc
    func testAddressParserAcceptsEnabledIPv6() {
        let data: NSData! = "2001:db8::1".dataUsingEncoding(NSUTF8StringEncoding)
        let address: String! = TLOInternetAddressLookup.addressFromData(data, response: self.responseWithStatusCode(200), allowIPv4: false, allowIPv6: true)

        XCTAssertEqualObjects(address, "2001:db8::1")
    }
    @objc
    func testAddressParserRejectsDisabledOrMalformedAddresses() {
        let response = self.responseWithStatusCode(200)
        let IPv4Data: NSData! = "203.0.113.42".dataUsingEncoding(NSUTF8StringEncoding)
        let invalidData: NSData! = "not an address".dataUsingEncoding(NSUTF8StringEncoding)

        XCTAssertNil(TLOInternetAddressLookup.addressFromData(IPv4Data, response: response, allowIPv4: false, allowIPv6: true))
        XCTAssertNil(TLOInternetAddressLookup.addressFromData(invalidData, response: response, allowIPv4: true, allowIPv6: true))
    }
    @objc
    func testAddressParserRejectsBadStatusAndOversizedResponse() {
        let addressData: NSData! = "203.0.113.42".dataUsingEncoding(NSUTF8StringEncoding)
        let oversizedData: NSData! = NSMutableData.dataWithLength(1025)

        XCTAssertNil(TLOInternetAddressLookup.addressFromData(addressData, response: self.responseWithStatusCode(500), allowIPv4: true, allowIPv6: true))
        XCTAssertNil(TLOInternetAddressLookup.addressFromData(oversizedData, response: self.responseWithStatusCode(200), allowIPv4: true, allowIPv6: true))
    }
    @objc
    func testLookupDefaultsToBothAddressFamilies() {
        let delegate = TLOInternetAddressLookupDelegateSpy()
        let lookup: UnsafeMutablePointer<TLOInternetAddressLookup>! = TLOInternetAddressLookup(delegate: delegate)

        XCTAssertTrue(lookup.IPv4AddressIsValid)
        XCTAssertTrue(lookup.IPv6AddressIsValid)
    }
}