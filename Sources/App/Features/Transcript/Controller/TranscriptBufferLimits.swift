// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** How many lines one transcript keeps, as the reader's setting asks for it.

 A zero or otherwise invalid scrollback setting restores the transcript's
 established defaults. The document, its projection and the trim all measure
 themselves against this. */
nonisolated struct TranscriptBufferLimits: Equatable, Sendable {
	static let defaultHardLimit = 1000
	static let validLimits = 100 ... 50000

	let hardLimit: Int

	init(setting: UInt) {
		if setting >= UInt(Self.validLimits.lowerBound),
		   setting <= UInt(Self.validLimits.upperBound)
		{
			hardLimit = Int(setting)
		} else {
			hardLimit = Self.defaultHardLimit
		}
	}
}
