// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// Keeps display progress below the rate of file blocks without losing the
/// latest byte count. The transfer flushes it before completion, failure or
/// cancellation, so progress cannot arrive after a terminal event.
nonisolated struct DCCProgressSampler {
	let minimumInterval: Duration
	private var lastEmission: ContinuousClock.Instant?
	private var lastReportedBytes: UInt64?
	private var pendingBytes: UInt64?

	init(minimumInterval: Duration) {
		self.minimumInterval = minimumInterval
	}

	mutating func record(_ bytes: UInt64, at now: ContinuousClock.Instant) -> UInt64? {
		guard (pendingBytes ?? lastReportedBytes).map({ bytes > $0 }) ?? true else { return nil }
		if let lastEmission, now - lastEmission < minimumInterval {
			pendingBytes = bytes
			return nil
		}
		lastEmission = now
		lastReportedBytes = bytes
		pendingBytes = nil
		return bytes
	}

	mutating func flush() -> UInt64? {
		guard let pendingBytes else { return nil }
		self.pendingBytes = nil
		lastReportedBytes = pendingBytes
		return pendingBytes
	}
}
