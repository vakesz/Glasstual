@testable import Glasstual
import XCTest

/** *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */
@MainActor
class TLOInternetAddressLookupDelegateSpy: NSObject, InternetAddressLookupDelegate {
	func internetAddressLookupReturnedAddress(_: String) {}

	func internetAddressLookupFailed() {}
}

class TLOInternetAddressLookupTests: XCTestCase {
	func responseWithStatusCode(_ statusCode: Int) throws -> HTTPURLResponse {
		try XCTUnwrap(
			HTTPURLResponse(
				url: XCTUnwrap(URL(string: "https://example.invalid/address")),
				statusCode: statusCode,
				httpVersion: "HTTP/1.1",
				headerFields: nil
			)
		)
	}

	func testAddressParserTrimsAndAcceptsEnabledIPv4() throws {
		let data = Data("  203.0.113.42\n".utf8)
		let address = try InternetAddressLookup.address(
			from: data,
			response: responseWithStatusCode(200),
			allowIPv4: true,
			allowIPv6: false
		)

		XCTAssertEqual(address, "203.0.113.42")
	}

	func testAddressParserAcceptsEnabledIPv6() throws {
		let data = Data("2001:db8::1".utf8)
		let address = try InternetAddressLookup.address(
			from: data,
			response: responseWithStatusCode(200),
			allowIPv4: false,
			allowIPv6: true
		)

		XCTAssertEqual(address, "2001:db8::1")
	}

	func testAddressParserRejectsDisabledOrMalformedAddresses() throws {
		let response = try responseWithStatusCode(200)
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

	func testAddressParserRejectsBadStatusAndOversizedResponse() throws {
		let addressData = Data("203.0.113.42".utf8)
		let oversizedData = Data(count: 1025)

		XCTAssertNil(try InternetAddressLookup.address(
			from: addressData,
			response: responseWithStatusCode(500),
			allowIPv4: true,
			allowIPv6: true
		))
		XCTAssertNil(try InternetAddressLookup.address(
			from: oversizedData,
			response: responseWithStatusCode(200),
			allowIPv4: true,
			allowIPv6: true
		))
	}

	/// The lookup and its delegate are main-actor isolated; the parser above
	/// is not.
	@MainActor
	func testLookupDefaultsToBothAddressFamilies() {
		let delegate = TLOInternetAddressLookupDelegateSpy()
		let lookup = InternetAddressLookup(delegate: delegate)

		XCTAssertTrue(lookup.ipv4AddressIsValid)
		XCTAssertTrue(lookup.ipv6AddressIsValid)
	}
}
