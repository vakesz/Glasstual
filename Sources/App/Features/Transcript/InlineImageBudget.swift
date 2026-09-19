// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** The ceiling on inline previews: how many may be in flight, how many may be
 kept, and how many bytes they may hold — per view and for the process.

 A reservation is taken before a download starts, narrowed to what the decoded
 preview actually holds once it is resident, and released when the line that
 drew it goes. */
@MainActor
final class InlineImageBudget {
	static let shared = InlineImageBudget()

	private struct Reservation {
		let view: String
		var bytes: Int
		var active = true
	}

	private let maximumRequests: Int
	private let maximumViewRequests: Int
	private let maximumBytes: Int
	private let maximumViewBytes: Int
	private let maximumEntries: Int
	private let maximumViewEntries: Int
	private var reservations: [UUID: Reservation] = [:]

	init(
		maximumRequests: Int = 4, maximumViewRequests: Int = 2,
		maximumBytes: Int = 768 * 1024 * 1024, maximumViewBytes: Int = 384 * 1024 * 1024,
		maximumEntries: Int = 128, maximumViewEntries: Int = 32
	) {
		self.maximumRequests = maximumRequests
		self.maximumViewRequests = maximumViewRequests
		self.maximumBytes = maximumBytes
		self.maximumViewBytes = maximumViewBytes
		self.maximumEntries = maximumEntries
		self.maximumViewEntries = maximumViewEntries
	}

	var entryCount: Int {
		reservations.count
	}

	var activeCount: Int {
		reservations.values.filter(\.active).count
	}

	var reservedByteCount: Int {
		reservations.values.reduce(0) { $0 + $1.bytes }
	}

	func reserve(view: String, bytes: Int?) -> UUID? {
		let local = reservations.values.filter { $0.view == view }
		guard let bytes, bytes > 0,
		      reservations.count < maximumEntries, local.count < maximumViewEntries,
		      activeCount < maximumRequests, local.filter(\.active).count < maximumViewRequests,
		      bytes <= maximumBytes, reservedByteCount <= maximumBytes - bytes,
		      bytes <= maximumViewBytes, local.reduce(0, { $0 + $1.bytes }) <= maximumViewBytes - bytes
		else { return nil }
		let identifier = UUID()
		reservations[identifier] = Reservation(view: view, bytes: bytes)
		return identifier
	}

	func retain(_ identifier: UUID, bytes: Int) {
		guard var reservation = reservations[identifier] else { return }
		reservation.bytes = min(reservation.bytes, max(0, bytes))
		reservation.active = false
		reservations[identifier] = reservation
	}

	func release(_ identifier: UUID) {
		reservations.removeValue(forKey: identifier)
	}
}
