// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Darwin
import Foundation

/// The DCC CTCP wire spellings: how a filename is quoted in an offer, how an
/// address is written into one and read back out, and which peer-supplied
/// addresses the session is willing to dial.
///
/// Pure transformations over text, so an offer round-trips deterministically
/// and is testable without a socket.
nonisolated enum DCCWireFormat {
	/// `filename` as an offer writes it: sanitised, and quoted when it holds a
	/// space, because the offer is a space-separated CTCP payload.
	static func escapedFilename(_ filename: String) -> String {
		var escaped = filename.safeFilename

		guard escaped.contains(" ") else {
			return escaped
		}

		escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")

		return "\"\(escaped)\""
	}

	/// `address` as an offer carries it: IPv4 packed into its decimal integer,
	/// IPv6 left as written, and `nil` when it is neither.
	static func wireAddress(_ address: String) -> String? {
		if address.isIPv6Address {
			return address
		}

		guard let octets = ipv4Octets(address) else {
			return nil
		}

		var packed: UInt32 = 0

		for octet in octets {
			packed = (packed << 8) | UInt32(octet)
		}

		return String(packed)
	}

	/// The inverse of ``wireAddress(_:)``: a packed IPv4 integer becomes dotted
	/// quads, and anything else is returned as it arrived.
	static func displayAddress(_ address: String) -> String {
		guard address.isEmpty == false,
		      address.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
		      // Anything wider than 32 bits is not a packed IPv4 address, and
		      // saturating it would fabricate one the peer never sent.
		      let packedValue = UInt32(address)
		else {
			return address
		}

		var packed = packedValue
		var octets: [String] = []

		for _ in 0 ..< 4 {
			octets.append(String(packed & 0xFF))
			packed >>= 8
		}

		return octets.reversed().joined(separator: ".")
	}

	/// `true` when a peer supplied address is one the session is willing to
	/// dial. The peer, not the user, chooses this address, so loopback,
	/// link-local, multicast and private ranges are refused.
	///
	/// Both families are parsed into their address bytes and classified from
	/// them. Matching text prefixes let an IPv6 spelling of a refused IPv4
	/// address through — `::ffff:127.0.0.1` and `64:ff9b::7f00:1` both dial
	/// loopback, and `0:0:0:0:0:0:0:1` is `::1` written out in full.
	static func isDialableAddress(_ address: String) -> Bool {
		if let octets = ipv4Bytes(address) {
			return isDialableIPv4(octets)
		}

		guard let bytes = ipv6Bytes(address) else {
			return false
		}

		return isDialableIPv6(bytes)
	}

	/** `address` as the bytes it names, whichever family it is written in, or
	 `nil` when it is not a literal address at all.

	 Two spellings of one address are one address: `2001:0db8::1` and
	 `2001:db8::1` differ only in how they are written, and comparing the text
	 made a peer dialling from the address an offer named look like a stranger.
	 The bytes are what the comparison has to be made on. */
	static func addressBytes(of address: String) -> [UInt8]? {
		ipv4Bytes(address) ?? ipv6Bytes(address)
	}

	// MARK: - Classification

	private static func isDialableIPv4(_ octets: [UInt8]) -> Bool {
		switch (octets[0], octets[1]) {
		case (0, _), (10, _), (127, _):
			false
		case (169, 254):
			false
		case (172, 16 ... 31):
			false
		case (192, 168):
			false
		case (100, 64 ... 127):
			false
		// 192.0.0.0/24 IETF protocol assignments and 192.0.2.0/24 TEST-NET-1.
		case (192, 0):
			octets[2] != 0 && octets[2] != 2
		// 198.18.0.0/15 benchmarking, and 198.51.100.0/24 TEST-NET-2.
		case (198, 18), (198, 19):
			false
		case (198, 51):
			octets[2] != 100
		// 203.0.113.0/24 TEST-NET-3.
		case (203, 0):
			octets[2] != 113
		case (224 ... 255, _):
			false
		default:
			true
		}
	}

	/// The IPv6 well-known NAT64 prefix, `64:ff9b::/96`. An address under it
	/// reaches the IPv4 address in its low 32 bits, so that is what decides.
	private static let nat64WellKnownPrefix: [UInt8] = [
		0x00, 0x64, 0xFF, 0x9B, 0, 0, 0, 0, 0, 0, 0, 0,
	]

	private static func isDialableIPv6(_ bytes: [UInt8]) -> Bool {
		// Unspecified (::) and loopback (::1), however they were spelled.
		if bytes.dropLast().allSatisfy({ $0 == 0 }), bytes[15] <= 1 {
			return false
		}

		// ::ffff:0:0/96 mapped, ::/96 compatible, and 64:ff9b::/96 NAT64 all
		// carry an IPv4 address in their low 32 bits.
		let highBytes = Array(bytes.prefix(12))
		let isMapped = highBytes.prefix(10).allSatisfy { $0 == 0 } && highBytes[10] == 0xFF && highBytes[11] == 0xFF
		let isCompatible = highBytes.allSatisfy { $0 == 0 }

		if isMapped || isCompatible || highBytes == nat64WellKnownPrefix {
			return isDialableIPv4(Array(bytes.suffix(4)))
		}

		// fe80::/10 link-local, fc00::/7 unique-local, ff00::/8 multicast.
		if bytes[0] == 0xFE, bytes[1] & 0xC0 == 0x80 {
			return false
		}

		if bytes[0] & 0xFE == 0xFC || bytes[0] == 0xFF {
			return false
		}

		// 100::/64, the RFC 6666 discard-only prefix.
		if bytes[0] == 0x01, bytes[1] == 0x00, bytes.dropFirst(2).prefix(6).allSatisfy({ $0 == 0 }) {
			return false
		}

		return true
	}

	// MARK: - Parsing

	private static func ipv4Bytes(_ address: String) -> [UInt8]? {
		/* `inet_pton` reads a leading zero as decimal padding, and a resolver
		 that reads it as octal reaches a different host: `0177.0.0.1` is either
		 177.0.0.1 or loopback depending on who parses it. An offer written that
		 way is not one to resolve either way. */
		guard address.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({
			$0.count == 1 || $0.hasPrefix("0") == false
		}) else {
			return nil
		}

		return addressBytes(address, family: AF_INET, byteCount: 4)
	}

	private static func ipv6Bytes(_ address: String) -> [UInt8]? {
		addressBytes(address, family: AF_INET6, byteCount: 16)
	}

	/// The address bytes `inet_pton` reads out of `address`, or `nil` when the
	/// text is not an address of that family. `inet_pton` refuses a zone suffix
	/// and any of the loose forms `inet_aton` accepts, which is what makes the
	/// byte classification above exhaustive.
	private static func addressBytes(_ address: String, family: Int32, byteCount: Int) -> [UInt8]? {
		var bytes = [UInt8](repeating: 0, count: byteCount)
		var parsed: Int32 = 0

		bytes.withUnsafeMutableBytes { buffer in
			parsed = inet_pton(family, address, buffer.baseAddress)
		}

		return parsed == 1 ? bytes : nil
	}

	private static func ipv4Octets(_ address: String) -> [UInt8]? {
		let components = address.components(separatedBy: ".")

		guard components.count == 4 else {
			return nil
		}

		var octets: [UInt8] = []

		for component in components {
			guard component.isEmpty == false,
			      component.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
			      let value = UInt8(component)
			else {
				return nil
			}

			octets.append(value)
		}

		return octets
	}
}
