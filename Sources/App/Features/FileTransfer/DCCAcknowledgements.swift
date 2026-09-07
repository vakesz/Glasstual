/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation

/// DCC SEND uses cumulative network-order UInt32 ACKs, modulo 4 GiB.
nonisolated struct DCCAcknowledgements { // nonisolated: value
	private var pending: [UInt8] = []
	private(set) var hasBytes = false
	private(set) var acknowledged: UInt64
	let offeredSize: UInt64

	init(offset: UInt64, offeredSize: UInt64) {
		acknowledged = offset
		self.offeredSize = offeredSize
	}

	var isComplete: Bool {
		hasBytes && pending.isEmpty && acknowledged == offeredSize
	}

	mutating func append(_ data: Data) throws {
		for byte in data {
			hasBytes = true
			pending.append(byte)
			guard pending.count == 4 else { continue }
			let value = pending.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
			pending.removeAll(keepingCapacity: true)
			let delta = UInt64(value &- UInt32(truncatingIfNeeded: acknowledged))
			guard acknowledged <= offeredSize, delta <= offeredSize - acknowledged else {
				throw DCCTransferError.badParameter
			}
			acknowledged += delta
		}
	}
}
