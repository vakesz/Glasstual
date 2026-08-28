@testable import Glasstual
import XCTest

/// Preprocessor directives found in file:
/// #import <XCTest/XCTest.h>
/** *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */
@objc
@MainActor
class TLOInternetAddressLookupDelegateSpy: NSObject, InternetAddressLookupDelegate {
	@objc
	func internetAddressLookupReturnedAddress(_: String) {}

	@objc
	func internetAddressLookupFailed() {}
}

@objc
@MainActor
class TLOInternetAddressLookupTests: XCTestCase {
	@objc
	func responseWithStatusCode(_ statusCode: Int) -> HTTPURLResponse {
		HTTPURLResponse(
			url: URL(string: "https://example.invalid/address")!,
			statusCode: statusCode,
			httpVersion: "HTTP/1.1",
			headerFields: nil
		)!
	}

	@objc
	func testAddressParserTrimsAndAcceptsEnabledIPv4() {
		let data = Data("  203.0.113.42\n".utf8)
		let address: String! = InternetAddressLookup.address(
			from: data,
			response: responseWithStatusCode(200),
			allowIPv4: true,
			allowIPv6: false
		)

		XCTAssertEqual(address, "203.0.113.42")
	}

	@objc
	func testAddressParserAcceptsEnabledIPv6() {
		let data = Data("2001:db8::1".utf8)
		let address: String! = InternetAddressLookup.address(
			from: data,
			response: responseWithStatusCode(200),
			allowIPv4: false,
			allowIPv6: true
		)

		XCTAssertEqual(address, "2001:db8::1")
	}

	@objc
	func testAddressParserRejectsDisabledOrMalformedAddresses() {
		let response = responseWithStatusCode(200)
		let IPv4Data = Data("203.0.113.42".utf8)
		let invalidData = Data("not an address".utf8)

		XCTAssertNil(InternetAddressLookup.address(
			from: IPv4Data,
			response: response,
			allowIPv4: false,
			allowIPv6: true
		))
		XCTAssertNil(InternetAddressLookup.address(
			from: invalidData,
			response: response,
			allowIPv4: true,
			allowIPv6: true
		))
	}

	@objc
	func testAddressParserRejectsBadStatusAndOversizedResponse() {
		let addressData = Data("203.0.113.42".utf8)
		let oversizedData = Data(count: 1025)

		XCTAssertNil(InternetAddressLookup.address(
			from: addressData,
			response: responseWithStatusCode(500),
			allowIPv4: true,
			allowIPv6: true
		))
		XCTAssertNil(InternetAddressLookup.address(
			from: oversizedData,
			response: responseWithStatusCode(200),
			allowIPv4: true,
			allowIPv6: true
		))
	}

	@objc
	func testLookupDefaultsToBothAddressFamilies() {
		let delegate = TLOInternetAddressLookupDelegateSpy()
		let lookup = InternetAddressLookup(delegate: delegate)

		XCTAssertTrue(lookup.ipv4AddressIsValid)
		XCTAssertTrue(lookup.ipv6AddressIsValid)
	}
}
