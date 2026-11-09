// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** The host lookups in flight, one per name.

 `getaddrinfo` cannot be cancelled, so a lookup a caller has given up on still
 holds a thread until the system resolver answers. Callers asking for a name
 that is already being looked up wait on that lookup instead of starting
 another, and only a few distinct names may be in flight at once: a page that
 names many hosts would otherwise pin a thread for each.

 A lookup keeps its place until it really finishes, not until a caller's
 deadline, which is what makes the bound a bound on threads. Nothing is kept
 once a lookup is done, so an answer is never reused. */
actor InlineImageLookups {
	/// How many distinct names may be in flight, abandoned ones included.
	static let defaultMaximumInFlight = 4

	private let maximumInFlight: Int
	private var inFlight: [String: Task<[String], Never>] = [:]

	init(maximumInFlight: Int = InlineImageLookups.defaultMaximumInFlight) {
		self.maximumInFlight = maximumInFlight
	}

	/// The lookup for `host`, started if none is running, or `nil` when the
	/// bound is reached and the name is not one already in flight.
	func lookup(
		_ host: String,
		using addresses: @escaping @Sendable (String) async -> [String]
	) -> Task<[String], Never>? {
		let key = Self.key(for: host)

		if let running = inFlight[key] {
			return running
		}

		guard inFlight.count < maximumInFlight else { return nil }

		let task = Task {
			let result = await addresses(host)
			finish(key)
			return result
		}
		inFlight[key] = task

		return task
	}

	private func finish(_ key: String) {
		inFlight.removeValue(forKey: key)
	}

	/// Spelled as `InlineImageHostPolicy` reads a name: case and trailing dots
	/// do not make another host.
	private static func key(for host: String) -> String {
		var key = host.lowercased()

		while key.hasSuffix(".") {
			key.removeLast()
		}

		return key
	}
}
