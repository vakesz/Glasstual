// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Network
import Testing

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
	func addressParserTrimsAndAcceptsIPv4() throws {
		let data = Data("  203.0.113.42\n".utf8)
		let address = try InternetAddressLookup.address(from: data, response: response(statusCode: 200))

		#expect(address == "203.0.113.42")
	}

	@Test("An IPv6 answer is accepted as readily as an IPv4 one")
	func addressParserAcceptsIPv6() throws {
		let data = Data("2001:db8::1".utf8)
		let address = try InternetAddressLookup.address(from: data, response: response(statusCode: 200))

		#expect(address == "2001:db8::1")
	}

	@Test("A body that is not an address at all is rejected")
	func addressParserRejectsMalformedAddresses() throws {
		#expect(try InternetAddressLookup.address(
			from: Data("not an address".utf8),
			response: response(statusCode: 200)
		) == nil)
		#expect(try InternetAddressLookup.address(from: Data(), response: response(statusCode: 200)) == nil)
	}

	@Test("A failed status, or a body larger than an address could be, is rejected")
	func addressParserRejectsBadStatusAndOversizedResponse() throws {
		let addressData = Data("203.0.113.42".utf8)
		let oversizedData = Data(count: 1025)

		#expect(try InternetAddressLookup.address(
			from: addressData,
			response: response(statusCode: 500)
		) == nil)
		#expect(try InternetAddressLookup.address(
			from: oversizedData,
			response: response(statusCode: 200)
		) == nil)
	}

	@Test("An oversized chunked lookup is cancelled before the server finishes its body", .timeLimit(.minutes(1)))
	func streamedBodyIsBounded() async throws {
		let listening = try await DCCSocket.startListener(portRange: TransferFixture.portRange)
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
		let url = try #require(URL(string: "http://127.0.0.1:\(listening.port)/address"))
		let lookup = Task { await InternetAddressLookup.address(from: url) }
		let didSend = try await DCCSocket.withTimeout(.seconds(3), failingWith: .connectTimeout) {
			var iterator = sent.makeAsyncIterator()
			return await iterator.next()
		}
		#expect(didSend == true)
		let address = try await DCCSocket.withTimeout(.seconds(3), failingWith: .connectTimeout) {
			await lookup.value
		}
		#expect(address == nil)
	}
}
