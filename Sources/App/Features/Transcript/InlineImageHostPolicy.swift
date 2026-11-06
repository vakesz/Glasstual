// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Darwin
import Foundation

/** The addresses a host name resolves to, as numeric text.

 Injectable so the policy can be exercised without a network. The system
 resolver runs off the main actor, and a name it cannot resolve answers with
 nothing: the download that follows fails on its own account. */
nonisolated struct InlineImageHostResolver: Sendable {
	let addresses: @Sendable (String) async -> [String]

	static let system = InlineImageHostResolver { host in
		await systemAddresses(for: host)
	}

	/// Resolves nothing, for downloads served by a stubbed URL protocol that
	/// never reaches the network.
	static let literalOnly = InlineImageHostResolver { _ in [] }

	@concurrent
	private static func systemAddresses(for host: String) async -> [String] {
		var hints = addrinfo()
		hints.ai_family = AF_UNSPEC
		hints.ai_socktype = SOCK_STREAM
		var head: UnsafeMutablePointer<addrinfo>?

		guard getaddrinfo(host, nil, &hints, &head) == 0, let head else {
			return []
		}

		defer { freeaddrinfo(head) }

		var addresses: [String] = []
		var cursor: UnsafeMutablePointer<addrinfo>? = head

		while let entry = cursor {
			var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))

			if getnameinfo(
				entry.pointee.ai_addr, entry.pointee.ai_addrlen,
				&buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST
			) == 0 {
				let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
				if let address = String(bytes: bytes, encoding: .utf8) {
					addresses.append(address)
				}
			}

			cursor = entry.pointee.ai_next
		}

		return addresses
	}
}

/** Which hosts an inline image may be fetched from.

 The address in a chat line is chosen by whoever wrote it, and fetching it
 from this Mac reaches whatever this Mac can reach: a router's admin page, a
 service bound to loopback, a cloud metadata address. A host is refused when
 it is a literal loopback, private, link-local or unique-local address, a name
 that is local by construction, or a name that resolves to any such address.

 The check and the connection resolve the name separately, so a host that
 answers differently the second time is not caught here. */
nonisolated enum InlineImageHostPolicy {
	enum Verdict: Equatable {
		case refused
		case allowed
		/// A public-looking name: only its resolved addresses can say.
		case needsResolution
	}

	/// What the host's spelling alone decides.
	static func verdict(forHost host: String?) -> Verdict {
		guard var host = host?.lowercased(), host.isEmpty == false else {
			return .refused
		}

		if let zone = host.firstIndex(of: "%") {
			host = String(host[..<zone])
		}

		while host.hasSuffix(".") {
			host.removeLast()
		}

		if DCCWireFormat.addressBytes(of: host) != nil {
			return DCCWireFormat.isDialableAddress(host) ? .allowed : .refused
		}

		let labels = host.split(separator: ".", omittingEmptySubsequences: false)

		guard labels.count >= 2, labels.allSatisfy({ $0.isEmpty == false }),
		      let top = labels.last
		else {
			// A single label names a machine on the local network.
			return .refused
		}

		/* A top-level label that is a number is no name: `127.1`, `0x7f.1` and
		 `2130706433` are loose spellings of an IPv4 address that the system
		 resolver accepts and `inet_pton` does not. */
		if top.allSatisfy(\.isNumber) || top.hasPrefix("0x") {
			return .refused
		}

		let localSuffixes = ["localhost", "local", "internal", "lan", "home", "arpa", "localdomain"]

		if localSuffixes.contains(String(top)) {
			return .refused
		}

		return .needsResolution
	}

	/// Whether `url` may be fetched, resolving its host when the spelling is
	/// not enough.
	static func permits(_ url: URL, resolver: InlineImageHostResolver) async -> Bool {
		switch verdict(forHost: url.host(percentEncoded: false)) {
		case .refused:
			return false
		case .allowed:
			return true
		case .needsResolution:
			guard let host = url.host(percentEncoded: false) else { return false }

			for address in await resolver.addresses(host) {
				let numeric = address.split(separator: "%", maxSplits: 1).first.map(String.init) ?? address

				guard DCCWireFormat.isDialableAddress(numeric) else {
					return false
				}
			}

			return true
		}
	}
}
