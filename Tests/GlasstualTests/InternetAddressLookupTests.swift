/*  *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Network
import Testing

@MainActor
private final class InternetAddressLookupDelegateSpy: NSObject, InternetAddressLookupDelegate {
	let results = AsyncStream<Bool>.makeStream()

	func internetAddressLookupReturnedAddress(_: String) {
		results.continuation.yield(true)
	}

	func internetAddressLookupFailed() {
		results.continuation.yield(false)
	}
}

@MainActor
@Suite("Internet address lookup")
struct InternetAddressLookupTests {
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
		let delegate = InternetAddressLookupDelegateSpy()
		let lookup = InternetAddressLookup(delegate: delegate)

		#expect(lookup.ipv4AddressIsValid)
		#expect(lookup.ipv6AddressIsValid)
	}

	@Test("An oversized chunked lookup is cancelled before the server finishes its body", .timeLimit(.minutes(1)))
	func streamedBodyIsBounded() async throws {
		let listening = try await DCCTransfer.startListener(portRange: TransferFixture.portRange)
		defer { listening.task.cancel() }
		let (sent, continuation) = AsyncStream<Bool>.makeStream()
		let server = Task {
			defer { continuation.finish() }
			for await connection in listening.connections {
				do {
					_ = try await connection.receive(atLeast: 1, atMost: 4096)
					let header = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n401\r\n"
					try await connection
						.send(Data(header.utf8) + Data(repeating: 0x61, count: 1025) + Data("\r\n".utf8))
					continuation.yield(true)
					// No terminating chunk. A post-download size check would wait
					// for the resource timeout instead of rejecting this body now.
					try await Task.sleep(for: .seconds(60))
					withExtendedLifetime(connection) {}
				} catch {}
				return
			}
		}
		defer { server.cancel() }
		let delegate = InternetAddressLookupDelegateSpy()
		let lookup = InternetAddressLookup(delegate: delegate)
		let url = try #require(URL(string: "http://127.0.0.1:\(listening.port)/address"))
		lookup.performLookup(from: url)
		defer { lookup.cancelLookup() }
		let didSend = try await DCCTransfer.withTimeout(.seconds(3), failingWith: .connectTimeout) {
			var iterator = sent.makeAsyncIterator()
			return await iterator.next()
		}
		#expect(didSend == true)
		let results = delegate.results.stream
		let result = try await DCCTransfer.withTimeout(.seconds(3), failingWith: .connectTimeout) {
			var iterator = results.makeAsyncIterator()
			return await iterator.next()
		}
		#expect(result == false)
	}
}
