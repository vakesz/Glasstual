// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Darwin
import Foundation

/** The addresses a host name resolves to, as numeric text.

 Injectable so the policy can be exercised without a network. The system
 resolver runs off the main actor, and a name it cannot resolve answers with
 nothing: the download that follows fails on its own account. */
nonisolated struct InlineImageHostResolver: Sendable {
	let addresses: @Sendable (String) async -> [String]
	private let lookups: InlineImageLookups

	/// `maximumInFlight` bounds the distinct names being looked up at once; a
	/// name past it is refused rather than queued. Each resolver shares lookups
	/// among its own callers only.
	init(
		addresses: @escaping @Sendable (String) async -> [String],
		maximumInFlight: Int = InlineImageLookups.defaultMaximumInFlight
	) {
		self.addresses = addresses
		lookups = InlineImageLookups(maximumInFlight: maximumInFlight)
	}

	/// How long a lookup may take before the caller stops waiting for it.
	static let deadline = Duration.seconds(5)

	/** The addresses for `host`, or `nil` when the lookup outlived `limit`, the
	 caller was cancelled, or too many other names are being looked up.

	 `getaddrinfo` cannot be cancelled, so a lookup that overruns is abandoned
	 rather than stopped: its answer is discarded when it finally arrives. The
	 first of the answer, the deadline and the cancellation is what the caller
	 gets, through a stream that keeps only that first value.

	 Callers asking for the same name wait on one lookup, and awaiting its value
	 does not cancel it, so one caller giving up leaves the others waiting. */
	func resolve(_ host: String, within limit: Duration = InlineImageHostResolver.deadline) async -> [String]? {
		guard Task.isCancelled == false,
		      let shared = await lookups.lookup(host, using: addresses)
		else { return nil }

		let (outcomes, report) = AsyncStream<[String]?>.makeStream(bufferingPolicy: .bufferingOldest(1))
		let lookupTask = Task {
			await report.yield(shared.value)
		}
		let timer = Task {
			try? await Task.sleep(for: limit)
			report.yield(nil)
		}
		defer {
			lookupTask.cancel()
			timer.cancel()
		}

		return await withTaskCancellationHandler {
			for await outcome in outcomes {
				return outcome
			}
			return nil
		} onCancel: {
			report.yield(nil)
		}
	}

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
 answers differently the second time (DNS rebinding) is not caught by the
 check above. `InlineImageTransfer` closes most of that gap by reading the
 address each connection actually reached from `URLSessionTaskMetrics` and
 passing it to `permitsRemoteAddress(_:)`, discarding the body of a response
 that came from a refused address.

 Residual risk: URLSession offers no hook before it connects, so the request
 itself (a GET with no credentials or cookies) is still sent to a rebound
 private address, and only its response is withheld. A blind side effect of a
 GET is therefore possible. Metrics also carry no address when the system
 reports none or when the connection goes through a proxy, whose own address
 is not the origin's; those cases are allowed, so they rest on the name check
 alone. Closing the rest would need a Network.framework connection that
 pins the resolved address.

 A session configured for a proxy fetches through that proxy, and the proxy,
 not this Mac, resolves the name: looking it up here would reveal it to the
 local resolver. Only the spelling is checked then, so literal private
 addresses and local names are still refused, but a public-looking name the
 proxy resolves to an address on its own network would be reached. A reader's
 own SOCKS5 or HTTP proxy therefore fetches an image only when the reader asks
 for it, and never a network icon (`InlineImageRoute.inlineImageFetch`). Tor
 exits refuse private addresses themselves. */
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

	/** Whether a connection that reached `address` may deliver an image.

	 `nil` means the system did not say, and is allowed: the name check is then
	 all there is. */
	static func permitsRemoteAddress(_ address: String?) -> Bool {
		guard let address, address.isEmpty == false else { return true }
		let numeric = address.split(separator: "%", maxSplits: 1).first.map(String.init) ?? address
		return DCCWireFormat.isDialableAddress(numeric)
	}

	/** Whether `url` may be fetched, resolving its host when the spelling is
	 not enough.

	 A `nil` resolver means a proxy resolves names: a public-looking name is
	 then allowed on its spelling, without a lookup on this Mac. */
	static func permits(
		_ url: URL,
		resolver: InlineImageHostResolver?,
		deadline: Duration = InlineImageHostResolver.deadline
	) async -> Bool {
		switch verdict(forHost: url.host(percentEncoded: false)) {
		case .refused:
			return false
		case .allowed:
			return true
		case .needsResolution:
			guard let host = url.host(percentEncoded: false) else { return false }
			guard let resolver else { return true }

			/* A lookup that does not finish in time, or a caller that has gone
			 away, is refused: the check cannot say the name is public. */
			guard let addresses = await resolver.resolve(host, within: deadline) else {
				return false
			}

			for address in addresses {
				let numeric = address.split(separator: "%", maxSplits: 1).first.map(String.init) ?? address

				guard DCCWireFormat.isDialableAddress(numeric) else {
					return false
				}
			}

			return true
		}
	}
}
