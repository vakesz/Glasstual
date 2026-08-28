/*  *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

@MainActor
private final class TLOInternetAddressLookupDelegateSpy: NSObject, InternetAddressLookupDelegate {
	func internetAddressLookupReturnedAddress(_: String) {}

	func internetAddressLookupFailed() {}
}

@MainActor
@Suite("Internet address lookup")
struct TLOInternetAddressLookupTests {
	private func response(statusCode: Int) throws -> HTTPURLResponse {
		let url = try #require(URL(string: "https://example.invalid/address"))

		return try #require(
			HTTPURLResponse(
				url: url,
				statusCode: statusCode,
				httpVersion: "HTTP/1.1",
				headerFields: nil
			)
		)
	}

	@Test("An IPv4 answer is trimmed of the whitespace the service pads it with")
	func addressParserTrimsAndAcceptsEnabledIPv4() throws {
		let data = Data("  203.0.113.42\n".utf8)
		let address = try InternetAddressLookup.address(
			from: data,
			response: response(statusCode: 200),
			allowIPv4: true,
			allowIPv6: false
		)

		#expect(address == "203.0.113.42")
	}

	@Test("An IPv6 answer is accepted when IPv6 is the enabled family")
	func addressParserAcceptsEnabledIPv6() throws {
		let data = Data("2001:db8::1".utf8)
		let address = try InternetAddressLookup.address(
			from: data,
			response: response(statusCode: 200),
			allowIPv4: false,
			allowIPv6: true
		)

		#expect(address == "2001:db8::1")
	}

	@Test("An address of a disabled family, or no address at all, is rejected")
	func addressParserRejectsDisabledOrMalformedAddresses() throws {
		let successfulResponse = try response(statusCode: 200)
		let IPv4Data = Data("203.0.113.42".utf8)
		let invalidData = Data("not an address".utf8)

		#expect(InternetAddressLookup.address(
			from: IPv4Data,
			response: successfulResponse,
			allowIPv4: false,
			allowIPv6: true
		) == nil)
		#expect(InternetAddressLookup.address(
			from: invalidData,
			response: successfulResponse,
			allowIPv4: true,
			allowIPv6: true
		) == nil)
	}

	@Test("A failed status, or a body larger than an address could be, is rejected")
	func addressParserRejectsBadStatusAndOversizedResponse() throws {
		let addressData = Data("203.0.113.42".utf8)
		let oversizedData = Data(count: 1025)
		let failedResponse = try response(statusCode: 500)
		let successfulResponse = try response(statusCode: 200)

		#expect(InternetAddressLookup.address(
			from: addressData,
			response: failedResponse,
			allowIPv4: true,
			allowIPv6: true
		) == nil)
		#expect(InternetAddressLookup.address(
			from: oversizedData,
			response: successfulResponse,
			allowIPv4: true,
			allowIPv6: true
		) == nil)
	}

	/// The lookup and its delegate are main-actor isolated; the parser above
	/// is not.
	@Test("A lookup asks for both address families until it is told otherwise")
	func lookupDefaultsToBothAddressFamilies() {
		let delegate = TLOInternetAddressLookupDelegateSpy()
		let lookup = InternetAddressLookup(delegate: delegate)

		#expect(lookup.ipv4AddressIsValid)
		#expect(lookup.ipv6AddressIsValid)
	}
}
