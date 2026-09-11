/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

@MainActor
struct IRCClientDCCAddressTests {
	/// `UInt64(address) ?? UInt64.max` fabricated 255.255.255.255 for an
	/// overflowing digit string and silently dropped the high bits of
	/// anything above UInt32.max.
	@Test(arguments: ["4294967296", "99999999999999999999", "18446744073709551616"])
	func addressesWiderThanThirtyTwoBitsAreNotTurnedIntoIPv4(_ address: String) {
		#expect(ClientWireUtilities.displayDCCAddress(address) == address)
	}

	@Test
	func packedAddressesStillRoundTrip() {
		#expect(ClientWireUtilities.displayDCCAddress("3232235786") == "192.168.1.10")
		#expect(ClientWireUtilities.displayDCCAddress("4294967295") == "255.255.255.255")
		#expect(ClientWireUtilities.wireDCCAddress("192.168.1.10") == "3232235786")
		#expect(ClientWireUtilities.wireDCCAddress("255.255.255.255") == "4294967295")
	}

	/// Octets went through `integerValue` and were OR-ed in, so an
	/// out-of-range octet corrupted its neighbours.
	@Test(arguments: ["192.168.1.256", "192.168.1.-1", "999.1.1.1", "1.2.3", "1.2.3.4.5", "a.b.c.d", "1..2.3"])
	func outOfRangeOctetsAreRejected(_ address: String) {
		#expect(ClientWireUtilities.wireDCCAddress(address) == nil)
	}

	@Test(arguments: [
		"127.0.0.1", "10.1.2.3", "192.168.0.5", "172.16.0.1", "172.31.255.254",
		"169.254.1.1", "0.0.0.0", "100.64.0.1", "224.0.0.1", "255.255.255.255",
		"::1", "fe80::1", "fd00::1", "not-an-address", "",
	])
	func nonRoutableAddressesAreNotDialable(_ address: String) {
		#expect(ClientWireUtilities.isDialableDCCAddress(address) == false)
	}

	@Test(arguments: ["93.184.216.34", "8.8.8.8", "172.32.0.1", "2001:db8::1"])
	func routableAddressesAreDialable(_ address: String) {
		#expect(ClientWireUtilities.isDialableDCCAddress(address))
	}

	/** Matching text prefixes let every IPv6 spelling of a refused IPv4 address
	 through: `::ffff:` maps one, the deprecated compatible form embeds one with
	 no marker at all, and `64:ff9b::/96` reaches one through NAT64. */
	@Test(arguments: [
		"::ffff:127.0.0.1", "::ffff:10.0.0.1", "::ffff:192.168.1.1", "::FFFF:169.254.1.1",
		"::127.0.0.1", "64:ff9b::7f00:1", "64:ff9b::a00:1",
	])
	func ipv6SpellingsOfRefusedIPv4AddressesAreNotDialable(_ address: String) {
		#expect(ClientWireUtilities.isDialableDCCAddress(address) == false)
	}

	/// `::1` written out in full is still loopback, and `::` in full is still
	/// unspecified. Comparing the text against the compressed spelling missed both.
	@Test(arguments: ["0:0:0:0:0:0:0:1", "0000:0000:0000:0000:0000:0000:0000:0001", "0:0:0:0:0:0:0:0"])
	func expandedLoopbackAndUnspecifiedAddressesAreNotDialable(_ address: String) {
		#expect(ClientWireUtilities.isDialableDCCAddress(address) == false)
	}

	/// The documentation and benchmarking ranges route nowhere, so an offer that
	/// names one is either a mistake or an attempt to have the client dial itself.
	@Test(arguments: [
		"192.0.2.1", "192.0.0.1", "198.18.0.1", "198.19.255.254", "198.51.100.7", "203.0.113.9",
	])
	func documentationAndBenchmarkRangesAreNotDialable(_ address: String) {
		#expect(ClientWireUtilities.isDialableDCCAddress(address) == false)
	}

	/// The neighbours of those ranges are ordinary routable space and stay dialable.
	@Test(arguments: ["192.0.3.1", "198.20.0.1", "198.51.101.1", "203.0.114.1", "2606:4700::1111"])
	func neighboursOfTheReservedRangesStayDialable(_ address: String) {
		#expect(ClientWireUtilities.isDialableDCCAddress(address))
	}

	/// A mapped address whose embedded IPv4 half is routable is still routable.
	@Test
	func mappedRoutableAddressesAreDialable() {
		#expect(ClientWireUtilities.isDialableDCCAddress("::ffff:8.8.8.8"))
	}

	/// `inet_pton` is strict where `inet_aton` is not: an octal, short or
	/// zone-suffixed spelling is not an address a peer gets to name.
	@Test(arguments: ["0177.0.0.1", "127.1", "2130706433", "fe80::1%en0", "1.2.3.4.5"])
	func looselySpelledAddressesAreNotDialable(_ address: String) {
		#expect(ClientWireUtilities.isDialableDCCAddress(address) == false)
	}

	/** One address has many spellings, and an expectation compared as text
	 refused the very peer the offer named: `2001:0db8::1` and `2001:db8::1` are
	 the same host, and `Network` reports what it resolved rather than what the
	 offer wrote. The bytes are what a comparison has to be made on. */
	@Test("Two spellings of one address reduce to the same bytes")
	func addressSpellingsReduceToTheSameBytes() throws {
		let padded = try #require(ClientWireUtilities.addressBytes(of: "2001:0db8:0000::0001"))
		let compact = try #require(ClientWireUtilities.addressBytes(of: "2001:db8::1"))

		#expect(padded == compact)
		#expect(ClientWireUtilities.addressBytes(of: "203.0.113.9")?.count == 4)
		#expect(compact.count == 16)
		// Neither family's bytes can collide with the other's: the counts differ.
		#expect(ClientWireUtilities.addressBytes(of: "203.0.113.9") != compact)
	}

	/// A cloak or a resolved name is not an address, so there is nothing to
	/// canonicalise and the caller is left comparing the text it was given.
	@Test(arguments: ["user/cloak", "host.example.net", ""])
	func nonAddressesHaveNoBytes(_ text: String) {
		#expect(ClientWireUtilities.addressBytes(of: text) == nil)
	}
}

@MainActor
struct IRCClientNicknameFormatPaddingTests {
	/// `scanInt()` yields Int.min for this format, and `abs(Int.min)` traps.
	@Test
	func extremeNegativePaddingDoesNotTrap() {
		let formatted = ClientWireUtilities.formatNickname(
			"nick",
			modeSymbol: "@",
			format: "%-9223372036854775808n"
		)

		#expect(formatted.hasSuffix("nick"))
	}

	@Test
	func ordinaryPaddingIsUnchanged() {
		#expect(
			ClientWireUtilities.formatNickname("ab", modeSymbol: "@", format: "<%-5n>") == "<   ab>"
		)
		#expect(
			ClientWireUtilities.formatNickname("ab", modeSymbol: "@", format: "<%5n>") == "<ab   >"
		)
	}
}
