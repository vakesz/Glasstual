// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
struct DCCWireFormatTests {
	/// `UInt64(address) ?? UInt64.max` fabricated 255.255.255.255 for an
	/// overflowing digit string and silently dropped the high bits of
	/// anything above UInt32.max.
	@Test(arguments: ["4294967296", "99999999999999999999", "18446744073709551616"])
	func addressesWiderThanThirtyTwoBitsAreNotTurnedIntoIPv4(_ address: String) {
		#expect(DCCWireFormat.displayAddress(address) == address)
	}

	@Test
	func packedAddressesStillRoundTrip() {
		#expect(DCCWireFormat.displayAddress("3232235786") == "192.168.1.10")
		#expect(DCCWireFormat.displayAddress("4294967295") == "255.255.255.255")
		#expect(DCCWireFormat.wireAddress("192.168.1.10") == "3232235786")
		#expect(DCCWireFormat.wireAddress("255.255.255.255") == "4294967295")
	}

	/// Octets went through `integerValue` and were OR-ed in, so an
	/// out-of-range octet corrupted its neighbours.
	@Test(arguments: ["192.168.1.256", "192.168.1.-1", "999.1.1.1", "1.2.3", "1.2.3.4.5", "a.b.c.d", "1..2.3"])
	func outOfRangeOctetsAreRejected(_ address: String) {
		#expect(DCCWireFormat.wireAddress(address) == nil)
	}

	@Test(arguments: [
		"127.0.0.1", "10.1.2.3", "192.168.0.5", "172.16.0.1", "172.31.255.254",
		"169.254.1.1", "0.0.0.0", "100.64.0.1", "224.0.0.1", "255.255.255.255",
		"::1", "fe80::1", "fd00::1", "not-an-address", "",
	])
	func nonRoutableAddressesAreNotDialable(_ address: String) {
		#expect(DCCWireFormat.isDialableAddress(address) == false)
	}

	@Test(arguments: ["93.184.216.34", "8.8.8.8", "172.32.0.1", "2001:db8::1"])
	func routableAddressesAreDialable(_ address: String) {
		#expect(DCCWireFormat.isDialableAddress(address))
	}

	/** Matching text prefixes let every IPv6 spelling of a refused IPv4 address
	 through: `::ffff:` maps one, the deprecated compatible form embeds one with
	 no marker at all, and `64:ff9b::/96` reaches one through NAT64. */
	@Test(arguments: [
		"::ffff:127.0.0.1", "::ffff:10.0.0.1", "::ffff:192.168.1.1", "::FFFF:169.254.1.1",
		"::127.0.0.1", "64:ff9b::7f00:1", "64:ff9b::a00:1",
	])
	func ipv6SpellingsOfRefusedIPv4AddressesAreNotDialable(_ address: String) {
		#expect(DCCWireFormat.isDialableAddress(address) == false)
	}

	/// `::1` written out in full is still loopback, and `::` in full is still
	/// unspecified. Comparing the text against the compressed spelling missed both.
	@Test(arguments: ["0:0:0:0:0:0:0:1", "0000:0000:0000:0000:0000:0000:0000:0001", "0:0:0:0:0:0:0:0"])
	func expandedLoopbackAndUnspecifiedAddressesAreNotDialable(_ address: String) {
		#expect(DCCWireFormat.isDialableAddress(address) == false)
	}

	/// The documentation and benchmarking ranges route nowhere, so an offer that
	/// names one is either a mistake or an attempt to have the client dial itself.
	@Test(arguments: [
		"192.0.2.1", "192.0.0.1", "198.18.0.1", "198.19.255.254", "198.51.100.7", "203.0.113.9",
	])
	func documentationAndBenchmarkRangesAreNotDialable(_ address: String) {
		#expect(DCCWireFormat.isDialableAddress(address) == false)
	}

	/// The neighbours of those ranges are ordinary routable space and stay dialable.
	@Test(arguments: ["192.0.3.1", "198.20.0.1", "198.51.101.1", "203.0.114.1", "2606:4700::1111"])
	func neighboursOfTheReservedRangesStayDialable(_ address: String) {
		#expect(DCCWireFormat.isDialableAddress(address))
	}

	/// A mapped address whose embedded IPv4 half is routable is still routable.
	@Test
	func mappedRoutableAddressesAreDialable() {
		#expect(DCCWireFormat.isDialableAddress("::ffff:8.8.8.8"))
	}

	/// `inet_pton` is strict where `inet_aton` is not: an octal, short or
	/// zone-suffixed spelling is not an address a peer gets to name.
	@Test(arguments: ["0177.0.0.1", "127.1", "2130706433", "fe80::1%en0", "1.2.3.4.5"])
	func looselySpelledAddressesAreNotDialable(_ address: String) {
		#expect(DCCWireFormat.isDialableAddress(address) == false)
	}

	/** One address has many spellings, and an expectation compared as text
	 refused the very peer the offer named: `2001:0db8::1` and `2001:db8::1` are
	 the same host, and `Network` reports what it resolved rather than what the
	 offer wrote. The bytes are what a comparison has to be made on. */
	@Test("Two spellings of one address reduce to the same bytes")
	func addressSpellingsReduceToTheSameBytes() throws {
		let padded = try #require(DCCWireFormat.addressBytes(of: "2001:0db8:0000::0001"))
		let compact = try #require(DCCWireFormat.addressBytes(of: "2001:db8::1"))

		#expect(padded == compact)
		#expect(DCCWireFormat.addressBytes(of: "203.0.113.9")?.count == 4)
		#expect(compact.count == 16)
		// Neither family's bytes can collide with the other's: the counts differ.
		#expect(DCCWireFormat.addressBytes(of: "203.0.113.9") != compact)
	}

	/// A cloak or a resolved name is not an address, so there is nothing to
	/// canonicalise and the caller is left comparing the text it was given.
	@Test(arguments: ["user/cloak", "host.example.net", ""])
	func nonAddressesHaveNoBytes(_ text: String) {
		#expect(DCCWireFormat.addressBytes(of: text) == nil)
	}

	/// An IPv6 address is written into an offer as it stands: only IPv4 is
	/// packed into an integer, so the round trip has to leave IPv6 alone.
	@Test
	func ipv6AddressesPassThroughBothDirections() {
		#expect(DCCWireFormat.wireAddress("2001:db8::1") == "2001:db8::1")
		#expect(DCCWireFormat.displayAddress("2001:db8::1") == "2001:db8::1")
	}

	/// The offer is a space-separated CTCP payload, so a filename holding a
	/// space is quoted and an embedded quote escaped.
	@Test
	func filenamesAreQuotedAndEscapedForTheWire() {
		#expect(DCCWireFormat.escapedFilename("report.txt") == "report.txt")
		#expect(DCCWireFormat.escapedFilename("a/b file.txt") == "\"a_b file.txt\"")
		#expect(DCCWireFormat.escapedFilename("say \"hi\".txt") == "\"say \\\"hi\\\".txt\"")
	}
}
